import { decodeMemoFields } from '../../utils/memo-fields';
import { deriveMemberPackageStatus } from '../../utils/member-package-status';

export function serializeMember<T extends {
  memo?: string | null;
  memberAccountId?: string | null;
  memberGroup?: { id: string; name: string; sortOrder: number } | null;
  memberPackages?: Array<{
    status: string;
    remainingSessions: number;
    expiryDate?: Date | string | null;
    pausedUntil?: Date | string | null;
  }>;
} & Record<string, unknown>>(member: T) {
  const memoFields = decodeMemoFields(member.memo);
  const packageStatus = deriveMemberPackageStatus(member.memberPackages ?? []);

  return {
    ...member,
    quickMemo: memoFields.quickMemo ?? null,
    memo: memoFields.memo ?? null,
    packageStatus: packageStatus.packageStatus,
    packageStatusLabel: packageStatus.packageStatusLabel,
    hasMemberAccount: member.memberAccountId != null,
    memberSourceLabel:
      member.memberAccountId != null ? '앱 가입 회원' : '관리자 등록 회원',
    memberAccessLabel:
      member.memberAccountId != null ? '채팅 가능' : '채팅 미연동',
  };
}
