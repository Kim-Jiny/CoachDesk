import { prisma } from '../../utils/prisma';
import { formatDateOnly, getKstDayOfWeek } from '../../utils/kst-date';
import {
  findFirstScheduleCompat,
  findFirstScheduleOverrideCompat,
  findScheduleOverridesCompat,
} from '../../utils/schedule-access';
import { decodeMemoFields, encodeMemoFields } from '../../utils/memo-fields';
import { isTimeRangeClosed } from '../../utils/slot-blocking';
import { addMinutesToTime, isOverlappingTimeRange } from '../shared/time-range';
import { reservationOwnerRelations, reservationRelations } from './queries';

export class ReservationMutationError extends Error {
  constructor(
    public readonly code:
      | 'RESERVATION_NOT_FOUND'
      | 'INVALID_STATUS'
      | 'DELAY_NOT_ALLOWED'
      | 'DELAY_BLOCKED_BY_OVERRIDE'
      | 'DELAY_NO_SCHEDULE'
      | 'DELAY_OUT_OF_RANGE'
      | 'DELAY_CONFLICT',
  ) {
    super(code);
  }
}

export async function findReservationInOrg(
  reservationId: string,
  organizationId: string,
) {
  return prisma.reservation.findFirst({
    where: { id: reservationId, organizationId },
    include: reservationOwnerRelations(),
  });
}

export async function updateReservationStatus(params: {
  organizationId: string;
  reservationId: string;
  status: 'PENDING' | 'CONFIRMED' | 'CANCELLED' | 'NO_SHOW';
}) {
  const existingReservation = await findReservationInOrg(
    params.reservationId,
    params.organizationId,
  );
  if (!existingReservation) {
    throw new ReservationMutationError('RESERVATION_NOT_FOUND');
  }

  const reservation = await prisma.reservation.update({
    where: { id: existingReservation.id },
    data: { status: params.status },
    include: reservationRelations,
  });

  return { existingReservation, reservation };
}

export async function updateReservationMemo(params: {
  organizationId: string;
  reservationId: string;
  quickMemo?: string;
  memo?: string;
}) {
  const existingReservation = await findReservationInOrg(
    params.reservationId,
    params.organizationId,
  );
  if (!existingReservation) {
    throw new ReservationMutationError('RESERVATION_NOT_FOUND');
  }

  const memoFields = decodeMemoFields(existingReservation.memo);
  const updated = await prisma.reservation.update({
    where: { id: existingReservation.id },
    data: {
      memo: encodeMemoFields({
        quickMemo: params.quickMemo ?? memoFields.quickMemo,
        memo: params.memo ?? memoFields.memo,
        delayMinutes: memoFields.delayMinutes,
        originalStartTime: memoFields.originalStartTime,
        originalEndTime: memoFields.originalEndTime,
      }),
    },
    include: reservationRelations,
  });

  return {
    existingReservation,
    reservation: updated,
  };
}

export async function delayReservation(params: {
  organizationId: string;
  reservationId: string;
  delayMinutes: number;
  force?: boolean;
}) {
  const existingReservation = await findReservationInOrg(
    params.reservationId,
    params.organizationId,
  );
  if (!existingReservation) {
    throw new ReservationMutationError('RESERVATION_NOT_FOUND');
  }
  if (!['PENDING', 'CONFIRMED'].includes(existingReservation.status)) {
    throw new ReservationMutationError('DELAY_NOT_ALLOWED');
  }

  const newStartTime = addMinutesToTime(
    existingReservation.startTime,
    params.delayMinutes,
  );
  const newEndTime = addMinutesToTime(
    existingReservation.endTime,
    params.delayMinutes,
  );
  const dateStr = formatDateOnly(existingReservation.date);
  const dayOfWeek = getKstDayOfWeek(dateStr);

  const override = await findFirstScheduleOverrideCompat({
    organizationId: params.organizationId,
    coachId: existingReservation.coachId,
    date: existingReservation.date,
  });
  const closedOverrides = await findScheduleOverridesCompat({
    organizationId: params.organizationId,
    coachId: existingReservation.coachId,
    date: existingReservation.date,
  });
  const blockedByOverride = closedOverrides.some(
    (candidate: { type: string; startTime?: string | null; endTime?: string | null }) =>
      isTimeRangeClosed(candidate, newStartTime, newEndTime),
  );
  if (!params.force && blockedByOverride) {
    throw new ReservationMutationError('DELAY_BLOCKED_BY_OVERRIDE');
  }

  const schedule =
    override?.type === 'OPEN'
      ? override
      : await findFirstScheduleCompat({
          organizationId: params.organizationId,
          coachId: existingReservation.coachId,
          dayOfWeek,
          isActive: true,
        });

  if (!schedule && !params.force) {
    throw new ReservationMutationError('DELAY_NO_SCHEDULE');
  }

  const scheduleStart = (schedule?.startTime ?? '') as string;
  const scheduleEnd = (schedule?.endTime ?? '') as string;
  if ((!scheduleStart || !scheduleEnd) && !params.force) {
    throw new ReservationMutationError('DELAY_NO_SCHEDULE');
  }

  const scheduleContainsRange =
    !isOverlappingTimeRange(newStartTime, newEndTime, '00:00', scheduleStart) &&
    !isOverlappingTimeRange(newStartTime, newEndTime, scheduleEnd, '24:00');
  if (!params.force && !scheduleContainsRange) {
    throw new ReservationMutationError('DELAY_OUT_OF_RANGE');
  }

  const conflictingReservations = await prisma.reservation.findMany({
    where: {
      organizationId: params.organizationId,
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

  if (
    !params.force &&
    conflictingReservations.some((reservation) =>
      isOverlappingTimeRange(
        newStartTime,
        newEndTime,
        reservation.startTime,
        reservation.endTime,
      ),
    )
  ) {
    throw new ReservationMutationError('DELAY_CONFLICT');
  }

  const memoFields = decodeMemoFields(existingReservation.memo);
  const updated = await prisma.$transaction(async (tx) => {
    await tx.scheduleOverride.create({
      data: {
        organizationId: params.organizationId,
        coachId: existingReservation.coachId,
        date: existingReservation.date,
        type: 'CLOSED',
        startTime: existingReservation.startTime,
        endTime: existingReservation.endTime,
      },
    });

    return tx.reservation.update({
      where: { id: existingReservation.id },
      data: {
        startTime: newStartTime,
        endTime: newEndTime,
        memo: encodeMemoFields({
          quickMemo: memoFields.quickMemo,
          memo: memoFields.memo,
          delayMinutes: (memoFields.delayMinutes ?? 0) + params.delayMinutes,
          originalStartTime:
            memoFields.originalStartTime ?? existingReservation.startTime,
          originalEndTime:
            memoFields.originalEndTime ?? existingReservation.endTime,
        }),
      },
      include: reservationRelations,
    });
  });

  return {
    existingReservation,
    reservation: updated,
    dateStr,
    newStartTime,
  };
}

export async function deleteReservation(params: {
  organizationId: string;
  reservationId: string;
}) {
  const reservation = await findReservationInOrg(
    params.reservationId,
    params.organizationId,
  );
  if (!reservation) {
    throw new ReservationMutationError('RESERVATION_NOT_FOUND');
  }

  await prisma.reservation.delete({ where: { id: reservation.id } });
  return { reservation };
}
