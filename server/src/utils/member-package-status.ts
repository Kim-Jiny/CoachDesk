import { formatDateOnly } from './kst-date';

type MemberPackageLike = {
  status: string;
  remainingSessions: number;
  expiryDate?: Date | string | null;
  pauseStartDate?: Date | string | null;
  pauseEndDate?: Date | string | null;
};

export type MemberPackageStatusSummary = {
  packageStatus: 'PACKAGE_ACTIVE' | 'PACKAGE_PAUSED' | 'PACKAGE_ENDED' | 'GENERAL_MEMBER';
  packageStatusLabel: string;
};

function toDate(value?: Date | string | null): Date | null {
  if (!value) return null;
  return value instanceof Date ? value : new Date(value);
}

export function deriveMemberPackageStatus(
  packages: MemberPackageLike[],
  now = new Date(),
): MemberPackageStatusSummary {
  if (packages.length === 0) {
    return {
      packageStatus: 'GENERAL_MEMBER',
      packageStatusLabel: '일반 회원',
    };
  }

  const today = formatDateOnly(now);
  const hasPaused = packages.some((memberPackage) => {
    const pauseStartDate = toDate(memberPackage.pauseStartDate);
    const pauseEndDate = toDate(memberPackage.pauseEndDate);
    if (pauseStartDate == null || pauseEndDate == null) return false;

    const start = formatDateOnly(pauseStartDate);
    const end = formatDateOnly(pauseEndDate);
    return start <= today && today <= end;
  });
  if (hasPaused) {
    return {
      packageStatus: 'PACKAGE_PAUSED',
      packageStatusLabel: '패키지 정지',
    };
  }

  const hasActive = packages.some((memberPackage) => {
    const expiryDate = toDate(memberPackage.expiryDate);
    const notExpired = expiryDate == null || expiryDate >= now;
    return memberPackage.status === 'ACTIVE' &&
      memberPackage.remainingSessions > 0 &&
      notExpired;
  });

  if (hasActive) {
    return {
      packageStatus: 'PACKAGE_ACTIVE',
      packageStatusLabel: '패키지 이용 회원',
    };
  }

  return {
    packageStatus: 'PACKAGE_ENDED',
    packageStatusLabel: '패키지 종료 회원',
  };
}
