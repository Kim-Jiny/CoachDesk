const KST_TIME_ZONE = 'Asia/Seoul';

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

function parseDateParts(date: string) {
  const [year, month, day] = date.split('-').map(Number);
  if (!year || !month || !day) {
    throw new Error(`Invalid date format: ${date}`);
  }
  return { year, month, day };
}

export function parseDateOnly(date: string): Date {
  const { year, month, day } = parseDateParts(date);
  return new Date(Date.UTC(year, month - 1, day));
}

export function formatDateOnly(date: Date): string {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: KST_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });

  return formatter.format(date);
}

export function getKstDayOfWeek(date: string): number {
  return parseDateOnly(date).getUTCDay();
}

export function getKstToday(): string {
  return formatDateOnly(new Date());
}

export function isKstToday(date: string): boolean {
  return date === getKstToday();
}

export function getKstCurrentTimeMinutes(): number {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone: KST_TIME_ZONE,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  const parts = formatter.formatToParts(new Date());
  const hour = Number(parts.find((part) => part.type === 'hour')?.value ?? '0');
  const minute = Number(parts.find((part) => part.type === 'minute')?.value ?? '0');
  return hour * 60 + minute;
}

export function hasKstTimePassed(date: string, time: string): boolean {
  const today = getKstToday();
  if (date < today) return true;
  if (date > today) return false;

  const [hour, minute] = time.split(':').map(Number);
  if (Number.isNaN(hour) || Number.isNaN(minute)) {
    throw new Error(`Invalid time format: ${time}`);
  }

  return getKstCurrentTimeMinutes() >= hour * 60 + minute;
}

export function addDays(date: string, days: number): string {
  const base = parseDateOnly(date);
  base.setUTCDate(base.getUTCDate() + days);
  return [
    base.getUTCFullYear(),
    pad(base.getUTCMonth() + 1),
    pad(base.getUTCDate()),
  ].join('-');
}

export function getKstMonthStart(date: string): string {
  const { year, month } = parseDateParts(date);
  return `${year}-${pad(month)}-01`;
}
