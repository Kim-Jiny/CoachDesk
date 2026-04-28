import { prisma } from '../../utils/prisma';
import { canCancelAt, canReserveAt } from '../../utils/reservation-policy';
import {
  formatDateOnly,
  getKstDayOfWeek,
  parseDateOnly,
} from '../../utils/kst-date';
import { decodeMemoFields } from '../../utils/memo-fields';
import { findFirstScheduleCompat, findScheduleOverridesCompat } from '../../utils/schedule-access';
import { isTimeRangeClosed } from '../../utils/slot-blocking';
import { findGeneratedSlot } from '../../utils/slot-service';
import { isOverlappingTimeRange } from '../shared/time-range';
import { reservationRelations } from './queries';

export class MemberReservationError extends Error {
  constructor(
    public readonly code:
      | 'NOT_MEMBER'
      | 'ORG_NOT_FOUND'
      | 'RESERVE_WINDOW_CLOSED'
      | 'DATE_CLOSED'
      | 'TIME_CLOSED'
      | 'INVALID_SLOT'
      | 'NO_SCHEDULE'
      | 'DUPLICATE'
      | 'FULL'
      | 'RESERVATION_NOT_FOUND'
      | 'CANNOT_CANCEL'
      | 'CANCEL_WINDOW_CLOSED',
    public readonly meta?: Record<string, unknown>,
  ) {
    super(code);
  }
}

type ReserveMemberSlotInput = {
  memberAccountId: string;
  organizationId: string;
  coachId: string;
  date: string;
  startTime: string;
  endTime: string;
};

export async function reserveMemberSlot(input: ReserveMemberSlotInput) {
  const [member, coach] = await Promise.all([
    prisma.member.findFirst({
      where: {
        organizationId: input.organizationId,
        memberAccountId: input.memberAccountId,
        status: 'ACTIVE',
      },
    }),
    prisma.user.findFirst({
      where: {
        id: input.coachId,
        memberships: {
          some: { organizationId: input.organizationId },
        },
      },
      select: {
        bookingMode: true,
        reservationPolicy: true,
        reservationOpenDaysBefore: true,
        reservationOpenHoursBefore: true,
        reservationCancelDeadlineMinutes: true,
      },
    }),
  ]);

  if (!member) {
    throw new MemberReservationError('NOT_MEMBER');
  }
  if (!coach) {
    throw new MemberReservationError('ORG_NOT_FOUND');
  }

  if (
    !canReserveAt(input.date, input.startTime, {
      reservationOpenDaysBefore: coach.reservationOpenDaysBefore,
      reservationOpenHoursBefore: coach.reservationOpenHoursBefore,
      reservationCancelDeadlineMinutes: 0,
    })
  ) {
    throw new MemberReservationError('RESERVE_WINDOW_CLOSED');
  }

  if (coach.bookingMode !== 'PUBLIC') {
    throw new MemberReservationError('INVALID_SLOT');
  }

  const targetDate = parseDateOnly(input.date);
  const dayOfWeek = getKstDayOfWeek(input.date);

  const matchedSlot = await findGeneratedSlot({
    organizationId: input.organizationId,
    date: input.date,
    coachId: input.coachId,
    startTime: input.startTime,
    endTime: input.endTime,
    includePast: false,
  });
  if (!matchedSlot) {
    throw new MemberReservationError('INVALID_SLOT');
  }

  const closedOverrides = await findScheduleOverridesCompat({
    organizationId: input.organizationId,
    coachId: input.coachId,
    date: targetDate,
  });
  const blockedByOverride = closedOverrides.some((candidate) =>
    isTimeRangeClosed(candidate, input.startTime, input.endTime),
  );
  if (blockedByOverride && !matchedSlot) {
    throw new MemberReservationError('TIME_CLOSED');
  }

  let maxCapacity: number | null = null;
  const override = closedOverrides.find(
    (candidate) =>
      candidate.type === 'OPEN' &&
      candidate.startTime === input.startTime &&
      candidate.endTime === input.endTime,
  );
  if (override?.type === 'OPEN') {
    maxCapacity = override.maxCapacity || 1;
  } else {
    const schedule = await findFirstScheduleCompat({
      organizationId: input.organizationId,
      coachId: input.coachId,
      dayOfWeek,
      isActive: true,
    });
    if (!schedule) {
      throw new MemberReservationError('NO_SCHEDULE');
    }
    maxCapacity = schedule.maxCapacity;
  }

  const finalStatus =
    coach.reservationPolicy === 'REQUEST_APPROVAL'
      ? 'PENDING'
      : 'CONFIRMED';

  const reservation = await prisma.$transaction(async (tx) => {
    const duplicate = await tx.reservation.findFirst({
      where: {
        memberId: member.id,
        coachId: input.coachId,
        date: targetDate,
        startTime: input.startTime,
        status: { notIn: ['CANCELLED'] },
      },
    });
    if (duplicate) {
      throw new MemberReservationError('DUPLICATE');
    }

    const overlappingReservations = await tx.reservation.findMany({
      where: {
        organizationId: input.organizationId,
        coachId: input.coachId,
        date: targetDate,
        status: { in: ['PENDING', 'CONFIRMED'] },
      },
      select: { startTime: true, endTime: true, memo: true },
    });
    // 지연된 예약은 원래 슬롯으로만 충돌 판정.
    const bookedOverlaps = overlappingReservations.filter((reservation) => {
      const memoFields = decodeMemoFields(reservation.memo);
      return isOverlappingTimeRange(
        input.startTime,
        input.endTime,
        memoFields.originalStartTime ?? reservation.startTime,
        memoFields.originalEndTime ?? reservation.endTime,
      );
    }).length;
    if (bookedOverlaps >= maxCapacity!) {
      throw new MemberReservationError('FULL');
    }

    return tx.reservation.create({
      data: {
        organizationId: input.organizationId,
        coachId: input.coachId,
        memberId: member.id,
        date: targetDate,
        startTime: input.startTime,
        endTime: input.endTime,
        status: finalStatus,
      },
      include: reservationRelations,
    });
  });

  return {
    reservation,
    finalStatus,
  };
}

export async function cancelMemberReservation(params: {
  memberAccountId: string;
  reservationId: string;
}) {
  const reservation = await prisma.reservation.findUnique({
    where: { id: params.reservationId },
    include: { member: { select: { memberAccountId: true } } },
  });

  if (!reservation || reservation.member?.memberAccountId !== params.memberAccountId) {
    throw new MemberReservationError('RESERVATION_NOT_FOUND');
  }

  if (!['PENDING', 'CONFIRMED'].includes(reservation.status)) {
    throw new MemberReservationError('CANNOT_CANCEL');
  }

  const coach = await prisma.user.findFirst({
    where: {
      id: reservation.coachId,
      memberships: {
        some: { organizationId: reservation.organizationId },
      },
    },
    select: { reservationCancelDeadlineMinutes: true },
  });
  if (!coach) {
    throw new MemberReservationError('ORG_NOT_FOUND');
  }

  if (
    !canCancelAt(formatDateOnly(reservation.date), reservation.startTime, {
      reservationOpenDaysBefore: 0,
      reservationOpenHoursBefore: 0,
      reservationCancelDeadlineMinutes:
        coach.reservationCancelDeadlineMinutes,
    })
  ) {
    throw new MemberReservationError('CANCEL_WINDOW_CLOSED', {
      deadlineMinutes: coach.reservationCancelDeadlineMinutes,
    });
  }

  const updatedReservation = await prisma.reservation.update({
    where: { id: params.reservationId },
    data: { status: 'CANCELLED' },
    include: reservationRelations,
  });

  return {
    reservation,
    updatedReservation,
    deadlineMinutes: coach.reservationCancelDeadlineMinutes,
  };
}
