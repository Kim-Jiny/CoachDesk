export function addMinutesToTime(time: string, minutesToAdd: number): string {
  const [hour, minute] = time.split(':').map(Number);
  const total = hour * 60 + minute + minutesToAdd;
  const normalized = ((total % (24 * 60)) + (24 * 60)) % (24 * 60);

  return `${String(Math.floor(normalized / 60)).padStart(2, '0')}:${String(
    normalized % 60,
  ).padStart(2, '0')}`;
}

export function isOverlappingTimeRange(
  leftStart: string,
  leftEnd: string,
  rightStart: string,
  rightEnd: string,
) {
  const leftStartMinutes =
    Number(leftStart.slice(0, 2)) * 60 + Number(leftStart.slice(3, 5));
  const leftEndMinutes =
    Number(leftEnd.slice(0, 2)) * 60 + Number(leftEnd.slice(3, 5));
  const rightStartMinutes =
    Number(rightStart.slice(0, 2)) * 60 + Number(rightStart.slice(3, 5));
  const rightEndMinutes =
    Number(rightEnd.slice(0, 2)) * 60 + Number(rightEnd.slice(3, 5));

  return (
    leftStartMinutes < rightEndMinutes && leftEndMinutes > rightStartMinutes
  );
}
