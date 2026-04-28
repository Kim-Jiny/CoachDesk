import bcrypt from 'bcryptjs';
import { prisma } from '../../utils/prisma';
import { toMemberAccountPayload, toMemberLinks, toOrganizationsPayload, toUserPayload } from './payloads';

export class AuthFlowError extends Error {
  constructor(
    public readonly code:
      | 'EMAIL_ALREADY_REGISTERED'
      | 'INVALID_CREDENTIALS'
      | 'REFRESH_TOKEN_REQUIRED'
      | 'USER_NOT_FOUND'
      | 'MEMBER_ACCOUNT_NOT_FOUND'
      | 'LAST_ORG_ADMIN'
      | 'INVALID_NAME',
  ) {
    super(code);
  }
}

export async function registerUserAccount(params: {
  email: string;
  password: string;
  name: string;
  phone?: string;
  generateAccessToken: (payload: { userId: string; email: string }) => string;
  generateRefreshToken: (payload: { userId: string; email: string }) => string;
}) {
  const existing = await prisma.user.findUnique({ where: { email: params.email } });
  if (existing) {
    throw new AuthFlowError('EMAIL_ALREADY_REGISTERED');
  }

  const hashedPassword = await bcrypt.hash(params.password, 12);

  const user = await prisma.user.create({
    data: {
      email: params.email,
      password: hashedPassword,
      name: params.name,
      phone: params.phone,
    },
  });

  const tokenPayload = { userId: user.id, email: user.email };
  return {
    accessToken: params.generateAccessToken(tokenPayload),
    refreshToken: params.generateRefreshToken(tokenPayload),
    user: toUserPayload(user),
    organizations: [],
  };
}

export async function loginUserAccount(params: {
  email: string;
  password: string;
  generateAccessToken: (payload: { userId: string; email: string }) => string;
  generateRefreshToken: (payload: { userId: string; email: string }) => string;
}) {
  const user = await prisma.user.findUnique({
    where: { email: params.email },
    include: {
      memberships: {
        orderBy: { createdAt: 'asc' },
        include: { organization: true },
      },
    },
  });

  if (!user || !(await bcrypt.compare(params.password, user.password))) {
    throw new AuthFlowError('INVALID_CREDENTIALS');
  }

  const tokenPayload = { userId: user.id, email: user.email };
  return {
    accessToken: params.generateAccessToken(tokenPayload),
    refreshToken: params.generateRefreshToken(tokenPayload),
    user: toUserPayload(user),
    organizations: toOrganizationsPayload(user),
  };
}

export async function refreshAccessToken(params: {
  refreshToken?: string;
  verifyRefreshToken: (token: string) => { userId: string; email: string };
  generateAccessToken: (payload: { userId: string; email: string }) => string;
}) {
  if (!params.refreshToken) {
    throw new AuthFlowError('REFRESH_TOKEN_REQUIRED');
  }

  const payload = params.verifyRefreshToken(params.refreshToken);

  const user = await prisma.user.findUnique({ where: { id: payload.userId } });
  if (user) {
    return {
      accessToken: params.generateAccessToken({ userId: user.id, email: user.email }),
    };
  }

  const memberAccount = await prisma.memberAccount.findUnique({
    where: { id: payload.userId },
  });
  if (memberAccount) {
    return {
      accessToken: params.generateAccessToken({
        userId: memberAccount.id,
        email: memberAccount.email,
      }),
    };
  }

  throw new AuthFlowError('USER_NOT_FOUND');
}

export async function getUserProfile(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: {
      memberships: {
        orderBy: { createdAt: 'asc' },
        include: { organization: true },
      },
    },
  });

  if (!user) {
    throw new AuthFlowError('USER_NOT_FOUND');
  }

  return {
    user: toUserPayload(user),
    organizations: toOrganizationsPayload(user),
  };
}

export async function updateUserProfile(params: {
  userId: string;
  name?: string;
  phone?: string;
  profileImage?: string;
  bookingMode?: 'PRIVATE' | 'PUBLIC';
  reservationPolicy?: 'AUTO_CONFIRM' | 'REQUEST_APPROVAL';
  reservationNoticeText?: string | null;
  reservationNoticeImageUrl?: string | null;
  reservationOpenDaysBefore?: number;
  reservationOpenHoursBefore?: number;
  reservationCancelDeadlineMinutes?: number;
}) {
  const user = await prisma.user.update({
    where: { id: params.userId },
    data: {
      name: params.name,
      phone: params.phone,
      profileImage: params.profileImage,
      bookingMode: params.bookingMode,
      reservationPolicy: params.reservationPolicy,
      reservationNoticeText: params.reservationNoticeText,
      reservationNoticeImageUrl: params.reservationNoticeImageUrl,
      reservationOpenDaysBefore: params.reservationOpenDaysBefore,
      reservationOpenHoursBefore: params.reservationOpenHoursBefore,
      reservationCancelDeadlineMinutes: params.reservationCancelDeadlineMinutes,
    },
  });

  return toUserPayload(user);
}

export async function deleteUserAccount(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    include: { memberships: true },
  });

  if (!user) {
    throw new AuthFlowError('USER_NOT_FOUND');
  }

  const adminMemberships = user.memberships.filter(
    (membership) => membership.role === 'OWNER' || membership.role === 'MANAGER',
  );

  for (const membership of adminMemberships) {
    const remainingAdminCount = await prisma.orgMembership.count({
      where: {
        organizationId: membership.organizationId,
        userId: { not: userId },
        role: { in: ['OWNER', 'MANAGER'] },
      },
    });

    if (remainingAdminCount === 0) {
      throw new AuthFlowError('LAST_ORG_ADMIN');
    }
  }

  const randomPassword = await bcrypt.hash(`${userId}:${Date.now()}`, 12);
  await prisma.$transaction(async (tx) => {
    await tx.orgMembership.deleteMany({ where: { userId } });
    await tx.user.update({
      where: { id: userId },
      data: {
        email: `deleted-${userId}@deleted.coachdesk.local`,
        password: randomPassword,
        name: '삭제된 관리자',
        phone: null,
        profileImage: null,
        bookingMode: 'PRIVATE',
        reservationPolicy: 'AUTO_CONFIRM',
        reservationNoticeText: null,
        reservationNoticeImageUrl: null,
        reservationOpenDaysBefore: 30,
        reservationOpenHoursBefore: 0,
        reservationCancelDeadlineMinutes: 120,
        fcmToken: null,
        notificationPreferences: null,
        googleId: null,
        appleId: null,
      },
    });
  });

  return { message: 'Admin account deleted' };
}

export async function registerMemberAccount(params: {
  email: string;
  password: string;
  name: string;
  generateAccessToken: (payload: { userId: string; email: string }) => string;
  generateRefreshToken: (payload: { userId: string; email: string }) => string;
}) {
  const existing = await prisma.memberAccount.findUnique({
    where: { email: params.email },
  });
  if (existing) {
    throw new AuthFlowError('EMAIL_ALREADY_REGISTERED');
  }

  const hashedPassword = await bcrypt.hash(params.password, 12);
  const account = await prisma.memberAccount.create({
    data: {
      email: params.email,
      password: hashedPassword,
      name: params.name,
    },
  });

  const tokenPayload = { userId: account.id, email: account.email };
  return {
    accessToken: params.generateAccessToken(tokenPayload),
    refreshToken: params.generateRefreshToken(tokenPayload),
    memberAccount: toMemberAccountPayload(account),
  };
}

export async function updateMemberAccount(params: {
  memberAccountId: string;
  name: string;
}) {
  const account = await prisma.memberAccount.findUnique({
    where: { id: params.memberAccountId },
  });
  if (!account) {
    throw new AuthFlowError('MEMBER_ACCOUNT_NOT_FOUND');
  }

  const trimmed = params.name.trim();
  if (trimmed.length === 0) {
    throw new AuthFlowError('INVALID_NAME');
  }

  const updated = await prisma.memberAccount.update({
    where: { id: params.memberAccountId },
    data: { name: trimmed },
  });

  return { memberAccount: toMemberAccountPayload(updated) };
}

export async function deleteMemberAccount(memberAccountId: string) {
  const account = await prisma.memberAccount.findUnique({
    where: { id: memberAccountId },
  });

  if (!account) {
    throw new AuthFlowError('MEMBER_ACCOUNT_NOT_FOUND');
  }

  await prisma.$transaction(async (tx) => {
    await tx.member.updateMany({
      where: { memberAccountId },
      data: { memberAccountId: null },
    });
    await tx.memberAccount.delete({ where: { id: memberAccountId } });
  });

  return { message: 'Member account deleted' };
}

export async function loginMemberAccount(params: {
  email: string;
  password: string;
  generateAccessToken: (payload: { userId: string; email: string }) => string;
  generateRefreshToken: (payload: { userId: string; email: string }) => string;
}) {
  const account = await prisma.memberAccount.findUnique({
    where: { email: params.email },
    include: { members: true },
  });

  if (!account || !(await bcrypt.compare(params.password, account.password))) {
    throw new AuthFlowError('INVALID_CREDENTIALS');
  }

  const tokenPayload = { userId: account.id, email: account.email };
  return {
    accessToken: params.generateAccessToken(tokenPayload),
    refreshToken: params.generateRefreshToken(tokenPayload),
    memberAccount: toMemberAccountPayload(account),
    members: toMemberLinks(account.members),
  };
}
