import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { sendPush } from '../utils/firebase';
import { getCurrentOrgId, isUserInOrganization } from '../utils/org-access';
import { formatDateOnly, getKstDayOfWeek, hasKstTimePassed, parseDateOnly } from '../utils/kst-date';
import { findFirstScheduleCompat, findFirstScheduleOverrideCompat, findScheduleOverridesCompat } from '../utils/schedule-access';
import { decodeMemoFields, encodeMemoFields } from '../utils/memo-fields';
import { isTimeRangeClosed } from '../utils/slot-blocking';
import { findGeneratedSlot, getAvailableSlots } from '../utils/slot-service';
import { emitReservationCreated, emitReservationUpdated, emitReservationCancelled } from '../socket/emitters';
import { shouldSendPushForType } from '../utils/notification-preferences';

const router = Router();
router.use(authMiddleware);

async function findReservationInOrg(reservationId: string, organizationId: string) {
  return prisma.reservation.findFirst({
    where: { id: reservationId, organizationId },
    include: {
      member: { select: { id: true, name: true, memberAccountId: true, memo: true } },
      coach: { select: { id: true, name: true } },
    },
  });
}

export function serializeReservation<T extends {
  date: Date;
  memo?: string | null;
  member?: { id: string; name: string; phone?: string | null; memberAccountId?: string | null; memo?: string | null } | null;
  coach?: { id: string; name: string } | null;
} & Record<string, unknown>>(reservation: T) {
  const memoFields = decodeMemoFields(reservation.memo);
  const memberMemoFields = decodeMemoFields(reservation.member?.memo);
  return {
    ...reservation,
    date: formatDateOnly(reservation.date),
    quickMemo: memoFields.quickMemo ?? null,
    memberQuickMemo: memberMemoFields.quickMemo ?? null,
    memo: memoFields.memo ?? null,
    delayMinutes: memoFields.delayMinutes ?? 0,
    originalStartTime: memoFields.originalStartTime ?? null,
    originalEndTime: memoFields.originalEndTime ?? null,
  };
}

function addMinutesToTime(time: string, minutesToAdd: number): string {
  const [hour, minute] = time.split(':').map(Number);
  const total = hour * 60 + minute + minutesToAdd;
  const normalized = ((total % (24 * 60)) + (24 * 60)) % (24 * 60);
  return `${String(Math.floor(normalized / 60)).padStart(2, '0')}:${String(normalized % 60).padStart(2, '0')}`;
}

function isOverlappingTimeRange(
  leftStart: string,
  leftEnd: string,
  rightStart: string,
  rightEnd: string,
) {
  const leftStartMinutes = Number(leftStart.slice(0, 2)) * 60 + Number(leftStart.slice(3, 5));
  const leftEndMinutes = Number(leftEnd.slice(0, 2)) * 60 + Number(leftEnd.slice(3, 5));
  const rightStartMinutes = Number(rightStart.slice(0, 2)) * 60 + Number(rightStart.slice(3, 5));
  const rightEndMinutes = Number(rightEnd.slice(0, 2)) * 60 + Number(rightEnd.slice(3, 5));
  return leftStartMinutes < rightEndMinutes && leftEndMinutes > rightStartMinutes;
}

// ─── List Reservations ─────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const date = req.query.date as string | undefined;
    const startDate = req.query.startDate as string | undefined;
    const endDate = req.query.endDate as string | undefined;
    const status = req.query.status as string | undefined;
    const memberId = req.query.memberId as string | undefined;

    const where: any = { organizationId: orgId };
    if (date) where.date = parseDateOnly(date);
    if (startDate && endDate) {
      where.date = { gte: parseDateOnly(startDate), lte: parseDateOnly(endDate) };
    }
    if (status) where.status = status;
    if (memberId) where.memberId = memberId;

    const reservations = await prisma.reservation.findMany({
      where,
      include: {
        member: { select: { id: true, name: true, phone: true, memberAccountId: true, memo: true } },
        coach: { select: { id: true, name: true } },
      },
      orderBy: [{ date: 'asc' }, { startTime: 'asc' }],
    });

    res.json(reservations.map(serializeReservation));
  } catch (err) {
    console.error('List reservations error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Create Reservation ────────────────────────────────────
const createReservationSchema = z.object({
  memberId: z.string().uuid(),
  date: z.string(),
  startTime: z.string().regex(/^\d{2}:\d{2}$/),
  endTime: z.string().regex(/^\d{2}:\d{2}$/),
  coachId: z.string().uuid().optional(),
  quickMemo: z.string().optional(),
  memo: z.string().optional(),
  manualTime: z.boolean().optional(),
  force: z.boolean().optional(),
});

router.post('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = createReservationSchema.parse(req.body);
    const coachId = body.coachId || req.user!.userId;
    const targetDate = parseDateOnly(body.date);
    const dayOfWeek = getKstDayOfWeek(body.date);

    const [member, coachMembership] = await Promise.all([
      prisma.member.findFirst({
        where: { id: body.memberId, organizationId: orgId },
        select: { id: true, memberAccountId: true },
      }),
      isUserInOrganization(coachId, orgId),
    ]);

    if (!member) {
      res.status(404).json({ error: 'Member not found' });
      return;
    }

    if (!coachMembership) {
      res.status(403).json({ error: 'Coach is not part of this organization' });
      return;
    }

    // Check overrides for this date & coach
    const override = await findFirstScheduleOverrideCompat({
      organizationId: orgId,
      coachId,
      date: targetDate,
    });

    if (override?.type === 'CLOSED') {
      res.status(409).json({ error: '해당 날짜는 휴무입니다' });
      return;
    }

    const closedOverrides = await prisma.scheduleOverride.findMany({
      where: {
        organizationId: orgId,
        coachId,
        date: targetDate,
        type: 'CLOSED',
      },
      select: {
        startTime: true,
        endTime: true,
        type: true,
      },
    });

    if (closedOverrides.some((candidate) => isTimeRangeClosed(candidate, body.startTime, body.endTime))) {
      res.status(409).json({ error: '관리자가 예약 마감한 시간입니다' });
      return;
    }

    const generatedSlots = await getAvailableSlots({
      organizationId: orgId,
      date: body.date,
      coachId,
      includePast: true,
    });
    const overlappingGeneratedSlots = generatedSlots.filter(
      (slot) =>
        !slot.blocked &&
        isOverlappingTimeRange(
          body.startTime,
          body.endTime,
          slot.startTime,
          slot.endTime,
        ),
    );

    if (body.manualTime) {
      if (overlappingGeneratedSlots.length > 0 && body.force !== true) {
        res.status(409).json({
          error: '이미 개설되어 있는 시간과 겹칩니다. 그래도 추가할지 확인해주세요',
          code: 'OPEN_SLOT_OVERLAP',
        });
        return;
      }
    } else {
      const matchedSlot = overlappingGeneratedSlots.find(
        (slot) =>
          slot.startTime === body.startTime && slot.endTime === body.endTime,
      ) ?? null;
      if (!matchedSlot) {
        res.status(409).json({ error: '실제 스케줄 슬롯에 맞는 시간만 예약할 수 있습니다' });
        return;
      }
    }

    // Determine maxCapacity from override or weekly schedule
    let maxCapacity: number | null = null;

    if (override?.type === 'OPEN') {
      maxCapacity = override.maxCapacity || 1;
    } else {
      const schedule = await findFirstScheduleCompat({
        organizationId: orgId,
        coachId,
        dayOfWeek,
        isActive: true,
      });
      if (schedule) {
        maxCapacity = schedule.maxCapacity;
      }
    }

    const duplicate = await prisma.reservation.findFirst({
      where: {
        organizationId: orgId,
        coachId,
        memberId: member.id,
        date: targetDate,
        startTime: body.startTime,
        status: { notIn: ['CANCELLED'] },
      },
      select: { id: true },
    });

    if (duplicate) {
      res.status(409).json({ error: '이미 예약된 시간입니다' });
      return;
    }

    if (maxCapacity != null && !(body.manualTime && body.force === true)) {
      const overlappingReservations = await prisma.reservation.findMany({
        where: {
          organizationId: orgId,
          coachId,
          date: targetDate,
          status: { in: ['PENDING', 'CONFIRMED'] },
        },
        select: {
          startTime: true,
          endTime: true,
        },
      });

      const booked = overlappingReservations.filter((reservation) =>
        isOverlappingTimeRange(
          body.startTime,
          body.endTime,
          reservation.startTime,
          reservation.endTime,
        ),
      ).length;

      if (booked >= maxCapacity) {
        res.status(409).json({ error: '이 시간대는 정원이 가득 찼습니다' });
        return;
      }
    }

    const reservation = await prisma.reservation.create({
      data: {
        organizationId: orgId,
        coachId,
        memberId: member.id,
        date: targetDate,
        startTime: body.startTime,
        endTime: body.endTime,
        memo: encodeMemoFields({ quickMemo: body.quickMemo, memo: body.memo }),
        status: 'CONFIRMED',
      },
      include: {
        member: { select: { id: true, name: true, phone: true, memo: true } },
        coach: { select: { id: true, name: true } },
      },
    });

    const serialized = serializeReservation(reservation);

    // Socket.IO real-time emit
    emitReservationCreated(orgId, serialized, member?.memberAccountId);

    // Push notification to member's MemberAccount if linked
    if (member?.memberAccountId) {
      const memberAccount = await prisma.memberAccount.findUnique({
        where: { id: member.memberAccountId },
        select: { fcmToken: true, notificationPreferences: true },
      });
      if (
        memberAccount?.fcmToken &&
        shouldSendPushForType(
          memberAccount.notificationPreferences,
          'NEW_RESERVATION',
        )
      ) {
        sendPush(
          memberAccount.fcmToken,
          '새 예약 등록',
          `${body.date} ${body.startTime} 예약이 등록되었습니다`,
          { type: 'NEW_RESERVATION', reservationId: reservation.id },
        );
      }
    }

    res.status(201).json(serialized);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Create reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Update Reservation Status ─────────────────────────────
router.patch('/:id/status', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const { status } = req.body;
    const validStatuses = ['PENDING', 'CONFIRMED', 'CANCELLED', 'NO_SHOW'];
    if (!validStatuses.includes(status)) {
      res.status(400).json({ error: 'Invalid status' });
      return;
    }

    const existingReservation = await findReservationInOrg(req.params.id as string, orgId);
    if (!existingReservation) {
      res.status(404).json({ error: 'Reservation not found' });
      return;
    }

    const reservation = await prisma.reservation.update({
      where: { id: existingReservation.id },
      data: { status },
      include: {
        member: { select: { id: true, name: true, memberAccountId: true, memo: true } },
        coach: { select: { id: true, name: true } },
      },
    });

    const serialized = serializeReservation(reservation);

    // Socket.IO real-time emit
    if (status === 'CANCELLED') {
      emitReservationCancelled(orgId, serialized, undefined, existingReservation.member.memberAccountId);
    } else {
      emitReservationUpdated(orgId, serialized, existingReservation.member.memberAccountId);
    }

    if (existingReservation.member.memberAccountId) {
      const memberAccount = await prisma.memberAccount.findUnique({
        where: { id: existingReservation.member.memberAccountId },
        select: { fcmToken: true, notificationPreferences: true },
      });

      let notificationTitle = '예약 상태 변경';
      let notificationBody = `${existingReservation.member.name}님의 예약 상태가 변경되었습니다`;

      if (status === 'CONFIRMED') {
        notificationTitle = '예약 승인';
        notificationBody = `${existingReservation.member.name}님의 예약이 승인되었습니다`;
      } else if (status === 'CANCELLED') {
        if (existingReservation.status === 'PENDING') {
          notificationTitle = '예약 신청 거절';
          notificationBody = `${existingReservation.member.name}님의 예약 신청이 거절되었습니다`;
        } else {
          notificationTitle = '예약 취소';
          notificationBody = `${existingReservation.member.name}님의 예약이 취소되었습니다`;
        }
      }

      if (
        memberAccount?.fcmToken &&
        shouldSendPushForType(
          memberAccount.notificationPreferences,
          'RESERVATION_STATUS_UPDATED',
        )
      ) {
        sendPush(
          memberAccount.fcmToken,
          notificationTitle,
          notificationBody,
          { type: 'RESERVATION_STATUS_UPDATED', reservationId: reservation.id },
        );
      }
    }

    res.json(serialized);
  } catch (err) {
    console.error('Update reservation status error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const delayReservationSchema = z.object({
  delayMinutes: z
    .number()
    .int()
    .min(-120)
    .max(120)
    .refine((v) => v !== 0, { message: 'delayMinutes must not be zero' }),
  force: z.boolean().optional(),
});

const updateReservationMemoSchema = z.object({
  quickMemo: z.string().max(100).optional(),
  memo: z.string().max(2000).optional(),
});

router.patch('/:id/memo', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = updateReservationMemoSchema.parse(req.body);
    const existingReservation = await findReservationInOrg(req.params.id as string, orgId);
    if (!existingReservation) {
      res.status(404).json({ error: 'Reservation not found' });
      return;
    }

    const memoFields = decodeMemoFields(existingReservation.memo);
    const updated = await prisma.reservation.update({
      where: { id: existingReservation.id },
      data: {
        memo: encodeMemoFields({
          quickMemo: body.quickMemo ?? memoFields.quickMemo,
          memo: body.memo ?? memoFields.memo,
          delayMinutes: memoFields.delayMinutes,
          originalStartTime: memoFields.originalStartTime,
          originalEndTime: memoFields.originalEndTime,
        }),
      },
      include: {
        member: { select: { id: true, name: true, memberAccountId: true, memo: true } },
        coach: { select: { id: true, name: true } },
      },
    });

    const serialized = serializeReservation(updated);
    emitReservationUpdated(orgId, serialized, existingReservation.member.memberAccountId);
    res.json(serialized);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update reservation memo error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.patch('/:id/delay', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = delayReservationSchema.parse(req.body);
    const existingReservation = await findReservationInOrg(req.params.id as string, orgId);
    if (!existingReservation) {
      res.status(404).json({ error: 'Reservation not found' });
      return;
    }
    if (!['PENDING', 'CONFIRMED'].includes(existingReservation.status)) {
      res.status(400).json({ error: '대기 또는 확정 예약만 미룰 수 있습니다' });
      return;
    }

    const newStartTime = addMinutesToTime(existingReservation.startTime, body.delayMinutes);
    const newEndTime = addMinutesToTime(existingReservation.endTime, body.delayMinutes);
    const dateStr = formatDateOnly(existingReservation.date);
    const dayOfWeek = getKstDayOfWeek(dateStr);

    const override = await findFirstScheduleOverrideCompat({
      organizationId: orgId,
      coachId: existingReservation.coachId,
      date: existingReservation.date,
    });
    const closedOverrides = await findScheduleOverridesCompat({
      organizationId: orgId,
      coachId: existingReservation.coachId,
      date: existingReservation.date,
    });
    const blockedByOverride = closedOverrides.some((candidate: { type: string; startTime?: string | null; endTime?: string | null }) =>
      isTimeRangeClosed(candidate, newStartTime, newEndTime),
    );
    if (!body.force && blockedByOverride) {
      res.status(409).json({ error: '미룬 시간이 예약 마감 구간과 겹칩니다' });
      return;
    }

    const schedule = override?.type === 'OPEN'
      ? override
      : await findFirstScheduleCompat({
          organizationId: orgId,
          coachId: existingReservation.coachId,
          dayOfWeek,
          isActive: true,
        });

    if (!schedule && !body.force) {
      res.status(409).json({ error: '해당 날짜에 적용 가능한 스케줄을 찾지 못했습니다' });
      return;
    }

    const scheduleStart = (schedule?.startTime ?? '') as string;
    const scheduleEnd = (schedule?.endTime ?? '') as string;
    if ((!scheduleStart || !scheduleEnd) && !body.force) {
      res.status(409).json({ error: '해당 날짜에 적용 가능한 스케줄을 찾지 못했습니다' });
      return;
    }

    const scheduleContainsRange =
      !isOverlappingTimeRange(newStartTime, newEndTime, '00:00', scheduleStart) &&
      !isOverlappingTimeRange(newStartTime, newEndTime, scheduleEnd, '24:00');
    if (!body.force && !scheduleContainsRange) {
      res.status(409).json({ error: '미룬 시간이 코치 가용 시간 범위를 벗어납니다' });
      return;
    }

    const conflictingReservations = await prisma.reservation.findMany({
      where: {
        organizationId: orgId,
        coachId: existingReservation.coachId,
        date: existingReservation.date,
        status: { in: ['PENDING', 'CONFIRMED'] },
        id: { not: existingReservation.id },
      },
      select: {
        id: true,
        startTime: true,
        endTime: true,
      },
    });

    if (!body.force && conflictingReservations.some((reservation) => isOverlappingTimeRange(
      newStartTime,
      newEndTime,
      reservation.startTime,
      reservation.endTime,
    ))) {
      res.status(409).json({ error: '조정한 시간이 다른 예약과 겹칩니다' });
      return;
    }

    const memoFields = decodeMemoFields(existingReservation.memo);
    const updated = await prisma.reservation.update({
      where: { id: existingReservation.id },
      data: {
        startTime: newStartTime,
        endTime: newEndTime,
        memo: encodeMemoFields({
          quickMemo: memoFields.quickMemo,
          memo: memoFields.memo,
          delayMinutes: (memoFields.delayMinutes ?? 0) + body.delayMinutes,
          originalStartTime: memoFields.originalStartTime ?? existingReservation.startTime,
          originalEndTime: memoFields.originalEndTime ?? existingReservation.endTime,
        }),
      },
      include: {
        member: { select: { id: true, name: true, memberAccountId: true, memo: true } },
        coach: { select: { id: true, name: true } },
      },
    });

    const serialized = serializeReservation(updated);
    emitReservationUpdated(orgId, serialized, existingReservation.member.memberAccountId);

    if (existingReservation.member.memberAccountId) {
      const memberAccount = await prisma.memberAccount.findUnique({
        where: { id: existingReservation.member.memberAccountId },
        select: { fcmToken: true, notificationPreferences: true },
      });
      if (
        memberAccount?.fcmToken &&
        shouldSendPushForType(
          memberAccount.notificationPreferences,
          'RESERVATION_DELAYED',
        )
      ) {
        const absMinutes = Math.abs(body.delayMinutes);
        const direction = body.delayMinutes > 0 ? '미뤄져' : '앞당겨져';
        sendPush(
          memberAccount.fcmToken,
          '예약 시간이 변경되었습니다',
          `${dateStr} 예약이 ${absMinutes}분 ${direction} ${newStartTime}에 시작합니다`,
          { type: 'RESERVATION_DELAYED', reservationId: updated.id },
        );
      }
    }

    res.json(serialized);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Delay reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Complete Reservation (핵심 트랜잭션) ──────────────────
const completeSchema = z.object({
  memberPackageId: z.string().uuid().optional(),
  attendance: z.enum(['PRESENT', 'NO_SHOW', 'LATE', 'CANCELLED']).default('PRESENT'),
  memo: z.string().optional(),
  workoutRecords: z.any().optional(),
  feedback: z.string().optional(),
});

router.post('/:id/complete', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = completeSchema.parse(req.body);

    const result = await prisma.$transaction(async (tx) => {
      // 1. Validate reservation
      const reservation = await tx.reservation.findUnique({
        where: { id: req.params.id as string },
      });

      if (!reservation || reservation.organizationId !== orgId) {
        throw new Error('Reservation not found');
      }
      if (reservation.status !== 'CONFIRMED') {
        throw new Error('Reservation is not in CONFIRMED status');
      }
      if (!hasKstTimePassed(formatDateOnly(reservation.date), reservation.endTime)) {
        throw new Error('수업 종료 시간 이후에만 완료 처리할 수 있습니다');
      }

      // 2. Deduct from package if provided
      if (body.memberPackageId) {
        const memberPackage = await tx.memberPackage.findUnique({
          where: { id: body.memberPackageId },
        });

        if (!memberPackage || memberPackage.status !== 'ACTIVE') {
          throw new Error('Invalid or inactive package');
        }
        if (memberPackage.memberId !== reservation.memberId) {
          throw new Error('Package does not belong to this member');
        }
        if (memberPackage.remainingSessions <= 0) {
          throw new Error('No remaining sessions in package');
        }

        const packageMember = await tx.member.findFirst({
          where: {
            id: memberPackage.memberId,
            organizationId: orgId,
          },
          select: { id: true },
        });
        if (!packageMember) {
          throw new Error('Package does not belong to this organization');
        }

        await tx.memberPackage.update({
          where: { id: body.memberPackageId },
          data: {
            usedSessions: { increment: 1 },
            remainingSessions: { decrement: 1 },
            status: memberPackage.remainingSessions <= 1 ? 'EXHAUSTED' : 'ACTIVE',
          },
        });
      }

      // 3. Create session record
      const session = await tx.session.create({
        data: {
          organizationId: orgId,
          reservationId: reservation.id,
          coachId: reservation.coachId,
          memberId: reservation.memberId,
          memberPackageId: body.memberPackageId,
          date: reservation.date,
          attendance: body.attendance,
          memo: body.memo,
          workoutRecords: body.workoutRecords,
          feedback: body.feedback,
        },
      });

      // 4. Update reservation status
      await tx.reservation.update({
        where: { id: reservation.id },
        data: { status: 'COMPLETED' },
      });

      return session;
    });

    res.json(result);
  } catch (err: any) {
    if (err.message && !err.message.includes('Internal')) {
      res.status(400).json({ error: err.message });
      return;
    }
    console.error('Complete reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Delete Reservation ────────────────────────────────────
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const reservation = await findReservationInOrg(req.params.id as string, orgId);
    if (!reservation) {
      res.status(404).json({ error: 'Reservation not found' });
      return;
    }

    await prisma.reservation.delete({ where: { id: reservation.id } });

    // Socket.IO real-time emit
    emitReservationCancelled(
      orgId,
      { ...serializeReservation(reservation), deleted: true },
      reservation.coach?.id,
      reservation.member?.memberAccountId,
    );

    res.json({ message: 'Reservation deleted' });
  } catch (err) {
    console.error('Delete reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
