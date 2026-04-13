export function timeToMinutes(time: string): number {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
}

export function isTimeRangeClosed(
  override: {
    type: string;
    startTime?: string | null;
    endTime?: string | null;
  },
  slotStartTime: string,
  slotEndTime: string,
): boolean {
  if (override.type !== 'CLOSED') return false;
  if (!override.startTime || !override.endTime) return true;

  return isTimeRangeOverlapping(override, slotStartTime, slotEndTime);
}

/**
 * Checks whether an override's time range overlaps with a slot.
 * Works for any override type (CLOSED, VISIBLE, HIDDEN, etc.).
 */
export function isTimeRangeOverlapping(
  override: {
    startTime?: string | null;
    endTime?: string | null;
  },
  slotStartTime: string,
  slotEndTime: string,
): boolean {
  if (!override.startTime || !override.endTime) return true;

  const overrideStart = timeToMinutes(override.startTime);
  const overrideEnd = timeToMinutes(override.endTime);
  const slotStart = timeToMinutes(slotStartTime);
  const slotEnd = timeToMinutes(slotEndTime);

  return slotStart < overrideEnd && slotEnd > overrideStart;
}
