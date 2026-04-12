import { decodeMemoFields } from '../../utils/memo-fields';
import { formatDateOnly } from '../../utils/kst-date';

export function serializeReservation<T extends {
  date: Date;
  memo?: string | null;
  member?: {
    id: string;
    name: string;
    phone?: string | null;
    memberAccountId?: string | null;
    memo?: string | null;
  } | null;
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
    delayMinutes: memoFields.delayMinutes ?? 0,
    originalStartTime: memoFields.originalStartTime ?? null,
    originalEndTime: memoFields.originalEndTime ?? null,
  };
}
