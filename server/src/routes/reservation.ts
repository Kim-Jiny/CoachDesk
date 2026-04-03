import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { sendPush } from '../utils/firebase';
import { getCurrentOrgId, isUserInOrganization } from '../utils/org-access';
import { formatDateOnly, getKstDayOfWeek, hasKstTimePassed, parseDateOnly } from '../utils/kst-date';
import { findFirstScheduleCompat, findFirstScheduleOverrideCompat } from '../utils/schedule-access';
import { decodeMemoFields, encodeMemoFields } from '../utils/memo-fields';
import { isTimeRangeClosed } from '../utils/slot-blocking';
import { findGeneratedSlot } from '../utils/slot-service';

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

function serializeReservation<T extends {
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
  };
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

    const matchedSlot = await findGeneratedSlot({
      organizationId: orgId,
      date: body.date,
      coachId,
      startTime: body.startTime,
      endTime: body.endTime,
      includePast: true,
    });
    if (!matchedSlot) {
      res.status(409).json({ error: '실제 스케줄 슬롯에 맞는 시간만 예약할 수 있습니다' });
      return;
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

    if (maxCapacity != null) {
      const booked = await prisma.reservation.count({
        where: {
          organizationId: orgId,
          coachId,
          date: targetDate,
          startTime: body.startTime,
          status: { in: ['PENDING', 'CONFIRMED'] },
        },
      });

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

    // Push notification to member's MemberAccount if linked
    if (member?.memberAccountId) {
      const memberAccount = await prisma.memberAccount.findUnique({
        where: { id: member.memberAccountId },
        select: { fcmToken: true },
      });
      if (memberAccount?.fcmToken) {
        sendPush(
          memberAccount.fcmToken,
          '새 예약 등록',
          `${body.date} ${body.startTime} 예약이 등록되었습니다`,
          { type: 'NEW_RESERVATION', reservationId: reservation.id },
        );
      }
    }

    res.status(201).json(serializeReservation(reservation));
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
        member: { select: { id: true, name: true } },
        coach: { select: { id: true, name: true } },
      },
    });

    if (existingReservation.member.memberAccountId) {
      const memberAccount = await prisma.memberAccount.findUnique({
        where: { id: existingReservation.member.memberAccountId },
        select: { fcmToken: true },
      });

      let notificationTitle = '예약 상태 변경';
      let notificationBody = '${existingReservation.member.name}님의 예약 상태가 변경되었습니다';

      if (status === 'CONFIRMED') {
        notificationTitle = '예약 승인';
        notificationBody = '${existingReservation.member.name}님의 예약이 승인되었습니다';
      } else if (status === 'CANCELLED') {
        notificationTitle = '예약 취소';
        notificationBody = '${existingReservation.member.name}님의 예약이 취소되었습니다';
      }

      if (memberAccount?.fcmToken) {
        sendPush(
          memberAccount.fcmToken,
          notificationTitle,
          notificationBody,
          { type: 'RESERVATION_STATUS_UPDATED', reservationId: reservation.id },
        );
      }
    }

    res.json(serializeReservation(reservation));
  } catch (err) {
    console.error('Update reservation status error:', err);
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
    res.json({ message: 'Reservation deleted' });
  } catch (err) {
    console.error('Delete reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
