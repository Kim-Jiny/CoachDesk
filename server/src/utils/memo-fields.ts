const MEMO_PREFIX = '__coachdesk_memo_v1__:';

type EncodedMemoShape = {
  quickMemo?: string | null;
  memo?: string | null;
  delayMinutes?: number | null;
  originalStartTime?: string | null;
  originalEndTime?: string | null;
};

export function decodeMemoFields(rawMemo?: string | null): {
  quickMemo?: string;
  memo?: string;
  delayMinutes?: number;
  originalStartTime?: string;
  originalEndTime?: string;
} {
  if (!rawMemo) {
    return {};
  }

  if (!rawMemo.startsWith(MEMO_PREFIX)) {
    return { memo: rawMemo };
  }

  try {
    const parsed = JSON.parse(rawMemo.slice(MEMO_PREFIX.length)) as EncodedMemoShape;
    return {
      quickMemo: parsed.quickMemo?.trim() || undefined,
      memo: parsed.memo?.trim() || undefined,
      delayMinutes: typeof parsed.delayMinutes === 'number' ? parsed.delayMinutes : undefined,
      originalStartTime: parsed.originalStartTime?.trim() || undefined,
      originalEndTime: parsed.originalEndTime?.trim() || undefined,
    };
  } catch {
    return { memo: rawMemo };
  }
}

export function encodeMemoFields({
  quickMemo,
  memo,
  delayMinutes,
  originalStartTime,
  originalEndTime,
}: {
  quickMemo?: string | null;
  memo?: string | null;
  delayMinutes?: number | null;
  originalStartTime?: string | null;
  originalEndTime?: string | null;
}): string | null | undefined {
  const normalizedQuickMemo = quickMemo?.trim() || '';
  const normalizedMemo = memo?.trim() || '';
  const normalizedOriginalStartTime = originalStartTime?.trim() || '';
  const normalizedOriginalEndTime = originalEndTime?.trim() || '';
  const normalizedDelayMinutes = typeof delayMinutes === 'number' && delayMinutes > 0
    ? delayMinutes
    : undefined;

  if (!normalizedQuickMemo && !normalizedMemo && !normalizedDelayMinutes && !normalizedOriginalStartTime && !normalizedOriginalEndTime) {
    return null;
  }

  return `${MEMO_PREFIX}${JSON.stringify({
    quickMemo: normalizedQuickMemo || undefined,
    memo: normalizedMemo || undefined,
    delayMinutes: normalizedDelayMinutes,
    originalStartTime: normalizedOriginalStartTime || undefined,
    originalEndTime: normalizedOriginalEndTime || undefined,
  })}`;
}
