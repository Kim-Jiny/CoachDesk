import { prisma } from '../../utils/prisma';
import { isUserInOrganization } from '../../utils/org-access';
import { getKstDayOfWeek, parseDateOnly } from '../../utils/kst-date';
import { findFirstScheduleCompat, findScheduleOverridesCompat } from '../../utils/schedule-access';
import { decodeMemoFields, encodeMemoFields } from '../../utils/memo-fields';
import { isTimeRangeClosed } from '../../utils/slot-blocking';
import { getAvailableSlots } from '../../utils/slot-service';
import { isOverlappingTimeRange } from '../shared/time-range';
import { reservationRelations } from './queries';

export class CreateAdminReservationError extends Error {
  constructor(
    public readonly code:
      | 'MEMBER_NOT_FOUND'
      | 'COACH_NOT_IN_ORG'
      | 'DATE_CLOSED'
      | 'TIME_CLOSED'
      | 'OPEN_SLOT_OVERLAP'
      | 'INVALID_SLOT'
      | 'DUPLICATE'
      | 'FULL',
  ) {
    super(code);
  }
}

type CreateAdminReservationInput = {
  organizationId: string;
  requesterUserId: string;
  memberId: string;
  date: string;
  startTime: string;
  endTime: string;
  coachId?: string;
  quickMemo?: string;
  memo?: string;
  manualTime?: boolean;
  force?: boolean;
};

export async function createAdminReservation(
  input: CreateAdminReservationInput,
) {
  const coachId = input.coachId || input.requesterUserId;
  const targetDate = parseDateOnly(input.date);
  const dayOfWeek = getKstDayOfWeek(input.date);

  const [member, coachMembership] = await Promise.all([
    prisma.member.findFirst({
      where: { id: input.memberId, organizationId: input.organizationId },
      select: { id: true, memberAccountId: true },
    }),
    isUserInOrganization(coachId, input.organizationId),
  ]);

  if (!member) {
    throw new CreateAdminReservationError('MEMBER_NOT_FOUND');
  }

  if (!coachMembership) {
    throw new CreateAdminReservationError('COACH_NOT_IN_ORG');
  }

  const generatedSlots = await getAvailableSlots({
    organizationId: input.organizationId,
    date: input.date,
    coachId,
    includePast: true,
  });
  const overlappingGeneratedSlots = generatedSlots.filter(
    (slot) =>
      !slot.blocked &&
      isOverlappingTimeRange(
        input.startTime,
        input.endTime,
        slot.startTime,
        slot.endTime,
      ),
  );

  const closedOverrides = await findScheduleOverridesCompat({
    organizationId: input.organizationId,
    coachId,
    date: targetDate,
  });

  if (
    overlappingGeneratedSlots.length === 0 &&
    closedOverrides.some((candidate) =>
      isTimeRangeClosed(candidate, input.startTime, input.endTime),
    )
  ) {
    throw new CreateAdminReservationError('TIME_CLOSED');
  }

  if (input.manualTime) {
    if (overlappingGeneratedSlots.length > 0 && input.force !== true) {
      throw new CreateAdminReservationError('OPEN_SLOT_OVERLAP');
    }
  } else {
    const matchedSlot =
      overlappingGeneratedSlots.find(
        (slot) =>
          slot.startTime === input.startTime && slot.endTime === input.endTime,
      ) ?? null;

    if (!matchedSlot) {
      throw new CreateAdminReservationError('INVALID_SLOT');
    }
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
      organizationId: input.organizationId,
      coachId,
      memberId: member.id,
      date: targetDate,
      startTime: input.startTime,
      status: { notIn: ['CANCELLED'] },
    },
    select: { id: true },
  });

  if (duplicate) {
    throw new CreateAdminReservationError('DUPLICATE');
  }

  if (maxCapacity != null && !(input.manualTime && input.force === true)) {
    const overlappingReservations = await prisma.reservation.findMany({
      where: {
        organizationId: input.organizationId,
        coachId,
        date: targetDate,
        status: { in: ['PENDING', 'CONFIRMED'] },
      },
      select: {
        startTime: true,
        endTime: true,
        memo: true,
      },
    });

    // 지연된 예약은 원래 슬롯(originalStartTime/EndTime)으로만 충돌 판정한다.
    const booked = overlappingReservations.filter((reservation) => {
      const memoFields = decodeMemoFields(reservation.memo);
      return isOverlappingTimeRange(
        input.startTime,
        input.endTime,
        memoFields.originalStartTime ?? reservation.startTime,
        memoFields.originalEndTime ?? reservation.endTime,
      );
    }).length;

    if (booked >= maxCapacity) {
      throw new CreateAdminReservationError('FULL');
    }
  }

  const reservation = await prisma.reservation.create({
    data: {
      organizationId: input.organizationId,
      coachId,
      memberId: member.id,
      date: targetDate,
      startTime: input.startTime,
      endTime: input.endTime,
      memo: encodeMemoFields({
        quickMemo: input.quickMemo,
        memo: input.memo,
      }),
      status: 'CONFIRMED',
    },
    include: reservationRelations,
  });

  return {
    reservation,
    memberAccountId: member.memberAccountId,
  };
}
