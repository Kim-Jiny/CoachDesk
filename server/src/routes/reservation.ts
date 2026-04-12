import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { sendPush } from '../utils/firebase';
import { formatDateOnly, parseDateOnly } from '../utils/kst-date';
import { createAdminReservation, CreateAdminReservationError } from '../features/reservation/create-admin-reservation';
import { completeReservation, CompleteReservationError } from '../features/reservation/complete-reservation';
import {
  deleteReservation,
  delayReservation,
  ReservationMutationError,
  updateReservationMemo,
  updateReservationStatus,
} from '../features/reservation/mutations';
import { serializeReservation } from '../features/reservation/serializer';
import { emitReservationCreated, emitReservationUpdated, emitReservationCancelled } from '../socket/emitters';
import { shouldSendPushForType } from '../utils/notification-preferences';
import { requireCurrentOrgId, respondValidationError } from './_shared';

const router = Router();
router.use(authMiddleware);

async function sendMemberReservationCancelledPush(params: {
  memberAccountId?: string | null;
  reservationId: string;
  date: Date;
  startTime: string;
}) {
  if (!params.memberAccountId) return;

  const memberAccount = await prisma.memberAccount.findUnique({
    where: { id: params.memberAccountId },
    select: { fcmToken: true, notificationPreferences: true },
  });

  if (
    !memberAccount?.fcmToken ||
    !shouldSendPushForType(
      memberAccount.notificationPreferences,
      'RESERVATION_CANCELLED',
    )
  ) {
    return;
  }

  sendPush(
    memberAccount.fcmToken,
    '예약 취소',
    `${formatDateOnly(params.date)} ${params.startTime} 예약이 취소되었습니다`,
    { type: 'RESERVATION_CANCELLED', reservationId: params.reservationId },
  );
}

// ─── List Reservations ─────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const body = createReservationSchema.parse(req.body);
    const { reservation, memberAccountId } = await createAdminReservation({
      organizationId: orgId,
      requesterUserId: req.user!.userId,
      ...body,
    });

    const serialized = serializeReservation(reservation);

    // Socket.IO real-time emit
    emitReservationCreated(orgId, serialized, memberAccountId);

    // Push notification to member's MemberAccount if linked
    if (memberAccountId) {
      const memberAccount = await prisma.memberAccount.findUnique({
        where: { id: memberAccountId },
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
    if (err instanceof CreateAdminReservationError) {
      if (err.code === 'MEMBER_NOT_FOUND') {
        res.status(404).json({ error: 'Member not found' });
        return;
      }
      if (err.code === 'COACH_NOT_IN_ORG') {
        res.status(403).json({ error: 'Coach is not part of this organization' });
        return;
      }
      if (err.code === 'DATE_CLOSED') {
        res.status(409).json({ error: '해당 날짜는 휴무입니다' });
        return;
      }
      if (err.code === 'TIME_CLOSED') {
        res.status(409).json({ error: '관리자가 예약 마감한 시간입니다' });
        return;
      }
      if (err.code === 'OPEN_SLOT_OVERLAP') {
        res.status(409).json({
          error: '이미 개설되어 있는 시간과 겹칩니다. 그래도 추가할지 확인해주세요',
          code: 'OPEN_SLOT_OVERLAP',
        });
        return;
      }
      if (err.code === 'INVALID_SLOT') {
        res.status(409).json({ error: '실제 스케줄 슬롯에 맞는 시간만 예약할 수 있습니다' });
        return;
      }
      if (err.code === 'DUPLICATE') {
        res.status(409).json({ error: '이미 예약된 시간입니다' });
        return;
      }
      if (err.code === 'FULL') {
        res.status(409).json({ error: '이 시간대는 정원이 가득 찼습니다' });
        return;
      }
    }
    if (respondValidationError(res, err)) return;
    console.error('Create reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Update Reservation Status ─────────────────────────────
router.patch('/:id/status', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const { status } = req.body;
    const validStatuses = ['PENDING', 'CONFIRMED', 'CANCELLED', 'NO_SHOW'] as const;
    if (!validStatuses.includes(status)) {
      res.status(400).json({ error: 'Invalid status' });
      return;
    }
    const { existingReservation, reservation } = await updateReservationStatus({
      organizationId: orgId,
      reservationId: req.params.id as string,
      status,
    });

    const serialized = serializeReservation(reservation);

    // Socket.IO real-time emit
    if (status === 'CANCELLED') {
      emitReservationCancelled(
        orgId,
        serialized,
        reservation.coach?.id,
        existingReservation.member.memberAccountId,
      );
    } else {
      emitReservationUpdated(orgId, serialized, existingReservation.member.memberAccountId);
    }

    if (
      status === 'CANCELLED' &&
      existingReservation.status !== 'CANCELLED'
    ) {
      await sendMemberReservationCancelledPush({
        memberAccountId: existingReservation.member.memberAccountId,
        reservationId: reservation.id,
        date: reservation.date,
        startTime: reservation.startTime,
      });
    } else if (existingReservation.member.memberAccountId) {
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
    if (err instanceof ReservationMutationError) {
      if (err.code === 'RESERVATION_NOT_FOUND') {
        res.status(404).json({ error: 'Reservation not found' });
        return;
      }
    }
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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const body = updateReservationMemoSchema.parse(req.body);
    const { existingReservation, reservation } = await updateReservationMemo({
      organizationId: orgId,
      reservationId: req.params.id as string,
      quickMemo: body.quickMemo,
      memo: body.memo,
    });

    const serialized = serializeReservation(reservation);
    emitReservationUpdated(orgId, serialized, existingReservation.member.memberAccountId);
    res.json(serialized);
  } catch (err) {
    if (err instanceof ReservationMutationError) {
      if (err.code === 'RESERVATION_NOT_FOUND') {
        res.status(404).json({ error: 'Reservation not found' });
        return;
      }
    }
    if (respondValidationError(res, err)) return;
    console.error('Update reservation memo error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.patch('/:id/delay', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const body = delayReservationSchema.parse(req.body);
    const { existingReservation, reservation, dateStr, newStartTime } =
      await delayReservation({
        organizationId: orgId,
        reservationId: req.params.id as string,
        delayMinutes: body.delayMinutes,
        force: body.force,
      });

    const serialized = serializeReservation(reservation);
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
          { type: 'RESERVATION_DELAYED', reservationId: reservation.id },
        );
      }
    }

    res.json(serialized);
  } catch (err) {
    if (err instanceof ReservationMutationError) {
      if (err.code === 'RESERVATION_NOT_FOUND') {
        res.status(404).json({ error: 'Reservation not found' });
        return;
      }
      if (err.code === 'DELAY_NOT_ALLOWED') {
        res.status(400).json({ error: '대기 또는 확정 예약만 미룰 수 있습니다' });
        return;
      }
      if (err.code === 'DELAY_BLOCKED_BY_OVERRIDE') {
        res.status(409).json({ error: '미룬 시간이 예약 마감 구간과 겹칩니다' });
        return;
      }
      if (err.code === 'DELAY_NO_SCHEDULE') {
        res.status(409).json({ error: '해당 날짜에 적용 가능한 스케줄을 찾지 못했습니다' });
        return;
      }
      if (err.code === 'DELAY_OUT_OF_RANGE') {
        res.status(409).json({ error: '미룬 시간이 코치 가용 시간 범위를 벗어납니다' });
        return;
      }
      if (err.code === 'DELAY_CONFLICT') {
        res.status(409).json({ error: '조정한 시간이 다른 예약과 겹칩니다' });
        return;
      }
    }
    if (respondValidationError(res, err)) return;
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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const body = completeSchema.parse(req.body);
    const result = await completeReservation({
      organizationId: orgId,
      reservationId: req.params.id as string,
      memberPackageId: body.memberPackageId,
      attendance: body.attendance,
      memo: body.memo,
      workoutRecords: body.workoutRecords,
      feedback: body.feedback,
    });

    res.json(result);
  } catch (err) {
    if (err instanceof CompleteReservationError) {
      res.status(400).json({ error: err.message });
      return;
    }
    if (respondValidationError(res, err)) return;
    console.error('Complete reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Delete Reservation ────────────────────────────────────
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const { reservation } = await deleteReservation({
      organizationId: orgId,
      reservationId: req.params.id as string,
    });

    // Socket.IO real-time emit
    emitReservationCancelled(
      orgId,
      { ...serializeReservation(reservation), deleted: true },
      reservation.coach?.id,
      reservation.member?.memberAccountId,
    );

    await sendMemberReservationCancelledPush({
      memberAccountId: reservation.member?.memberAccountId,
      reservationId: reservation.id,
      date: reservation.date,
      startTime: reservation.startTime,
    });

    res.json({ message: 'Reservation deleted' });
  } catch (err) {
    if (err instanceof ReservationMutationError) {
      if (err.code === 'RESERVATION_NOT_FOUND') {
        res.status(404).json({ error: 'Reservation not found' });
        return;
      }
    }
    console.error('Delete reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
