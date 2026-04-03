import { getKstCurrentTimeMinutes, getKstDayOfWeek, isKstToday, parseDateOnly } from './kst-date';
import { prisma } from './prisma';
import { findSchedulesCompat, findScheduleOverridesCompat } from './schedule-access';
import { isTimeRangeClosed } from './slot-blocking';

type SlotResult = {
  coachId: string;
  startTime: string;
  endTime: string;
  available: boolean;
  coachName?: string;
};

type ScheduleLike = {
  coachId: string;
  startTime: string;
  endTime: string;
  slotDuration: number;
  breakMinutes?: number | null;
  maxCapacity: number;
  coach?: { name: string } | null;
};

export async function getAvailableSlots(params: {
  organizationId: string;
  date: string;
  coachId?: string;
  includePast?: boolean;
  includeCoachNames?: boolean;
  }) {
  const {
    organizationId,
    date,
    coachId,
    includePast = false,
    includeCoachNames = false,
  } = params;

  const targetDate = parseDateOnly(date);
  const dayOfWeek = getKstDayOfWeek(date);

  const overrides = await findScheduleOverridesCompat({
    organizationId,
    date: targetDate,
    coachId,
    includeCoach: includeCoachNames,
  });

  const fullDayClosedCoachIds = overrides
    .filter((override) => override.type === 'CLOSED' && !override.startTime && !override.endTime)
    .map((override) => override.coachId);
  const openOverrides = overrides.filter((override) => override.type === 'OPEN');
  const closedOverrides = overrides.filter((override) => override.type === 'CLOSED');

  const schedules = await findSchedulesCompat({
    organizationId,
    dayOfWeek,
    coachId,
    excludeCoachIds: fullDayClosedCoachIds,
    isActive: true,
    includeCoach: includeCoachNames,
  });

  const existingReservations = await prisma.reservation.findMany({
    where: {
      organizationId,
      date: targetDate,
      status: { in: ['PENDING', 'CONFIRMED'] },
      ...(coachId ? { coachId } : {}),
    },
    select: {
      coachId: true,
      startTime: true,
    },
  });

  const isToday = isKstToday(date);
  const nowMinutes = isToday && !includePast ? getKstCurrentTimeMinutes() : 0;

  const slotMap = new Map<string, SlotResult>();

  for (const finalSlot of schedules.flatMap((schedule) =>
    generateSlotsFromSchedule(schedule, existingReservations, isToday, nowMinutes, includeCoachNames),
  )) {
    slotMap.set(getSlotKey(finalSlot), finalSlot);
  }

  for (const finalSlot of openOverrides.flatMap((override) => {
      if (!override.startTime || !override.endTime) return [];
      return generateSlotsFromSchedule(
        {
          coachId: override.coachId,
          startTime: override.startTime,
          endTime: override.endTime,
          slotDuration: override.slotDuration || 60,
          breakMinutes: override.breakMinutes || 0,
          maxCapacity: override.maxCapacity || 1,
          coach: (override as { coach?: { name: string } | null }).coach ?? null,
        },
        existingReservations,
        isToday,
        nowMinutes,
        includeCoachNames,
      );
    })) {
    slotMap.set(getSlotKey(finalSlot), finalSlot);
  }

  const slots = [...slotMap.values()];

  return slots.filter((slot) => {
    return !closedOverrides.some(
      (override) =>
        override.coachId === slot.coachId &&
        isTimeRangeClosed(override, slot.startTime, slot.endTime),
    );
  });
}

export async function findGeneratedSlot(params: {
  organizationId: string;
  date: string;
  coachId: string;
  startTime: string;
  endTime: string;
  includePast?: boolean;
}) {
  const slots = await getAvailableSlots({
    organizationId: params.organizationId,
    date: params.date,
    coachId: params.coachId,
    includePast: params.includePast,
  });

  return slots.find(
    (slot) =>
      slot.coachId === params.coachId &&
      slot.startTime === params.startTime &&
      slot.endTime === params.endTime,
  ) ?? null;
}

function getSlotKey(slot: SlotResult): string {
  return `${slot.coachId}|${slot.startTime}|${slot.endTime}`;
}

function generateSlotsFromSchedule(
  schedule: ScheduleLike,
  existingReservations: Array<{ coachId: string; startTime: string }>,
  isToday: boolean,
  nowMinutes: number,
  includeCoachNames: boolean,
): SlotResult[] {
  const result: SlotResult[] = [];
  const [startH, startM] = schedule.startTime.split(':').map(Number);
  const [endH, endM] = schedule.endTime.split(':').map(Number);
  const startMinutes = startH * 60 + startM;
  const endMinutes = endH * 60 + endM;
  const breakMinutes = schedule.breakMinutes ?? 0;

  for (let minute = startMinutes; minute + schedule.slotDuration <= endMinutes; minute += schedule.slotDuration + breakMinutes) {
    if (isToday && minute < nowMinutes) continue;

    const slotStart = `${String(Math.floor(minute / 60)).padStart(2, '0')}:${String(minute % 60).padStart(2, '0')}`;
    const slotEndMinutes = minute + schedule.slotDuration;
    const slotEnd = `${String(Math.floor(slotEndMinutes / 60)).padStart(2, '0')}:${String(slotEndMinutes % 60).padStart(2, '0')}`;

    const booked = existingReservations.filter(
      (reservation) => reservation.coachId === schedule.coachId && reservation.startTime === slotStart,
    ).length;

    result.push({
      coachId: schedule.coachId,
      startTime: slotStart,
      endTime: slotEnd,
      available: booked < schedule.maxCapacity,
      ...(includeCoachNames ? { coachName: schedule.coach?.name ?? '' } : {}),
    });
  }

  return result;
}
