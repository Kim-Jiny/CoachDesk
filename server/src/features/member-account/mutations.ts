import { prisma } from '../../utils/prisma';
import { sendPush } from '../../utils/firebase';
import { formatDateOnly, getKstToday, parseDateOnly } from '../../utils/kst-date';
import {
  findMemberPackageCompat,
  updateMemberPackagePauseCompat,
} from '../../utils/member-package-access';
import { checkMemberLimit } from '../../utils/plan-limits';
import { toOrganizationsPayload, toUserPayload } from '../auth/payloads';

function calculatePauseDays(startDate: string, endDate: string) {
  const start = new Date(`${startDate}T00:00:00+09:00`);
  const end = new Date(`${endDate}T00:00:00+09:00`);
  const diffMs = end.getTime() - start.getTime();
  return Math.floor(diffMs / (24 * 60 * 60 * 1000)) + 1;
}

export class MemberAccountMutationError extends Error {
  constructor(
    public readonly code:
      | 'MEMBER_ACCOUNT_NOT_FOUND'
      | 'INVALID_INVITE_CODE'
      | 'MEMBER_LIMIT_REACHED'
      | 'PACKAGE_NOT_FOUND'
      | 'INVALID_PAUSE_RANGE'
      | 'PAUSE_START_IN_PAST'
      | 'PACKAGE_NOT_AVAILABLE'
      | 'PAUSE_AFTER_EXPIRY'
      | 'PAUSE_ALREADY_PENDING',
  ) {
    super(code);
  }
}

export async function joinStudio(params: {
  memberAccountId: string;
  inviteCode: string;
}) {
  const account = await prisma.memberAccount.findUnique({
    where: { id: params.memberAccountId },
  });
  if (!account) {
    throw new MemberAccountMutationError('MEMBER_ACCOUNT_NOT_FOUND');
  }

  const inviteCode = params.inviteCode.trim().toUpperCase();
  const org = await prisma.organization.findUnique({ where: { inviteCode } });
  if (!org) {
    throw new MemberAccountMutationError('INVALID_INVITE_CODE');
  }

  const existing = await prisma.member.findFirst({
    where: { organizationId: org.id, memberAccountId: params.memberAccountId },
  });

  if (existing) {
    if (existing.status === 'ACTIVE') {
      return {
        alreadyJoined: true,
        member: {
          id: existing.id,
          organizationId: existing.organizationId,
          name: existing.name,
          status: existing.status,
        },
        organization: {
          id: org.id,
          name: org.name,
        },
      };
    }

    const withinLimit = await checkMemberLimit(org.id);
    if (!withinLimit) {
      throw new MemberAccountMutationError('MEMBER_LIMIT_REACHED');
    }

    const reactivatedMember = await prisma.member.update({
      where: { id: existing.id },
      data: {
        status: 'ACTIVE',
        name: existing.name || account.name,
      },
    });

    return {
      reactivated: true,
      member: {
        id: reactivatedMember.id,
        organizationId: reactivatedMember.organizationId,
        name: reactivatedMember.name,
        status: reactivatedMember.status,
      },
      organization: {
        id: org.id,
        name: org.name,
      },
    };
  }

  const withinLimit = await checkMemberLimit(org.id);
  if (!withinLimit) {
    throw new MemberAccountMutationError('MEMBER_LIMIT_REACHED');
  }

  const member = await prisma.member.create({
    data: {
      organizationId: org.id,
      memberAccountId: params.memberAccountId,
      name: account.name,
    },
  });

  return {
    member: {
      id: member.id,
      organizationId: member.organizationId,
      name: member.name,
    },
    organization: {
      id: org.id,
      name: org.name,
    },
  };
}

export async function requestPackagePause(params: {
  memberAccountId: string;
  memberPackageId: string;
  startDate: string;
  endDate: string;
  reason?: string;
}) {
  if (params.endDate < params.startDate) {
    throw new MemberAccountMutationError('INVALID_PAUSE_RANGE');
  }

  const today = getKstToday();
  if (params.startDate < today) {
    throw new MemberAccountMutationError('PAUSE_START_IN_PAST');
  }

  const memberPackage = await findMemberPackageCompat({ id: params.memberPackageId });
  if (!memberPackage || memberPackage.member?.memberAccountId !== params.memberAccountId) {
    throw new MemberAccountMutationError('PACKAGE_NOT_FOUND');
  }

  if (memberPackage.status !== 'ACTIVE' || memberPackage.remainingSessions <= 0) {
    throw new MemberAccountMutationError('PACKAGE_NOT_AVAILABLE');
  }

  if (
    memberPackage.expiryDate &&
    params.startDate > formatDateOnly(new Date(memberPackage.expiryDate))
  ) {
    throw new MemberAccountMutationError('PAUSE_AFTER_EXPIRY');
  }

  if (memberPackage.pauseRequestStatus === 'PENDING') {
    throw new MemberAccountMutationError('PAUSE_ALREADY_PENDING');
  }

  const packageName = memberPackage.package?.name ?? '패키지';
  const extensionDays = calculatePauseDays(params.startDate, params.endDate);

  await updateMemberPackagePauseCompat(memberPackage.id, {
    pauseRequestedStartDate: parseDateOnly(params.startDate),
    pauseRequestedEndDate: parseDateOnly(params.endDate),
    pauseRequestStatus: 'PENDING',
    pauseRequestReason: params.reason?.trim() || null,
  });

  const adminUsers = await prisma.orgMembership.findMany({
    where: {
      organizationId: memberPackage.member?.organizationId,
      role: { in: ['OWNER', 'MANAGER'] },
      user: { fcmToken: { not: null } },
    },
    select: {
      user: { select: { fcmToken: true } },
    },
  });

  await Promise.all(
    adminUsers.map(async ({ user }) => {
      if (!user.fcmToken) return;
      await sendPush(
        user.fcmToken,
        '패키지 정지 신청',
        `${memberPackage.member?.name ?? '회원'}님이 ${packageName} 정지를 신청했습니다`,
        { memberPackageId: memberPackage.id },
      );
    }),
  );

  return {
    message: `정지 신청이 접수되었습니다. 승인되면 만료일이 ${extensionDays}일 연장됩니다`,
    extensionDays,
  };
}

export async function upgradeToAdmin(params: {
  memberAccountId: string;
  generateAccessToken: (payload: { userId: string; email: string }) => string;
  generateRefreshToken: (payload: { userId: string; email: string }) => string;
}) {
  const account = await prisma.memberAccount.findUnique({
    where: { id: params.memberAccountId },
  });
  if (!account) {
    throw new MemberAccountMutationError('MEMBER_ACCOUNT_NOT_FOUND');
  }

  let user = await prisma.user.findUnique({
    where: { email: account.email },
    include: {
      memberships: {
        include: { organization: true },
        orderBy: { createdAt: 'asc' },
      },
    },
  });

  if (user) {
    const tokenPayload = { userId: user.id, email: user.email };
    return {
      accessToken: params.generateAccessToken(tokenPayload),
      refreshToken: params.generateRefreshToken(tokenPayload),
      user: toUserPayload(user),
      organizations: toOrganizationsPayload(user),
    };
  }

  const newUser = await prisma.user.create({
    data: {
      email: account.email,
      password: account.password,
      name: account.name,
      googleId: (account as any).googleId || undefined,
      appleId: (account as any).appleId || undefined,
    },
  });

  const tokenPayload = { userId: newUser.id, email: newUser.email };
  return {
    accessToken: params.generateAccessToken(tokenPayload),
    refreshToken: params.generateRefreshToken(tokenPayload),
    user: toUserPayload(newUser),
    organizations: [],
  };
}
