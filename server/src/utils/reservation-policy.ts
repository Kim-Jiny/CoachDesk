import { parseKstDateTime } from './kst-date';

type ReservationTimingPolicy = {
  reservationOpenDaysBefore: number;
  reservationOpenHoursBefore: number;
  reservationCancelDeadlineMinutes: number;
};

export function canReserveAt(
  date: string,
  startTime: string,
  policy: ReservationTimingPolicy,
  now: Date = new Date(),
): boolean {
  const classStart = parseKstDateTime(date, startTime);
  const openMs =
    (policy.reservationOpenDaysBefore * 24 + policy.reservationOpenHoursBefore) *
    60 *
    60 *
    1000;
  const opensAt = new Date(classStart.getTime() - openMs);
  return now.getTime() >= opensAt.getTime() && now.getTime() < classStart.getTime();
}

export function canCancelAt(
  date: string,
  startTime: string,
  policy: ReservationTimingPolicy,
  now: Date = new Date(),
): boolean {
  const classStart = parseKstDateTime(date, startTime);
  const cutoffMs = policy.reservationCancelDeadlineMinutes * 60 * 1000;
  return now.getTime() <= classStart.getTime() - cutoffMs;
}

export function buildReservationWindowLabel(policy: ReservationTimingPolicy): string {
  const dayPart = policy.reservationOpenDaysBefore > 0
    ? `${policy.reservationOpenDaysBefore}일`
    : null;
  const hourPart = policy.reservationOpenHoursBefore > 0
    ? `${policy.reservationOpenHoursBefore}시간`
    : null;
  const openParts = [dayPart, hourPart].filter(
    (value): value is string => value != null,
  );

  const openText = openParts.length === 0
    ? '수업 시작 직전'
    : `수업 ${openParts.join(' ')} 전부터`;
  return `${openText} 예약 가능 · 수업 ${policy.reservationCancelDeadlineMinutes}분 전까지 취소 가능`;
}
