const MEMO_PREFIX = '__coachdesk_memo_v1__:';

type EncodedMemoShape = {
  quickMemo?: string | null;
  memo?: string | null;
};

export function decodeMemoFields(rawMemo?: string | null): { quickMemo?: string; memo?: string } {
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
    };
  } catch {
    return { memo: rawMemo };
  }
}

export function encodeMemoFields({
  quickMemo,
  memo,
}: {
  quickMemo?: string | null;
  memo?: string | null;
}): string | null | undefined {
  const normalizedQuickMemo = quickMemo?.trim() || '';
  const normalizedMemo = memo?.trim() || '';

  if (!normalizedQuickMemo && !normalizedMemo) {
    return null;
  }

  return `${MEMO_PREFIX}${JSON.stringify({
    quickMemo: normalizedQuickMemo || undefined,
    memo: normalizedMemo || undefined,
  })}`;
}
