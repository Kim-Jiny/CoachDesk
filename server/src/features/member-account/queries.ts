import { prisma } from '../../utils/prisma';
import { formatDateOnly, getKstToday, parseDateOnly } from '../../utils/kst-date';
import { getAvailableSlots } from '../../utils/slot-service';
import { canReserveAt } from '../../utils/reservation-policy';
import { listMemberPackagesCompat } from '../../utils/member-package-access';
import { toMemberAccountPayload } from '../auth/payloads';

export class MemberAccountQueryError extends Error {
  constructor(
    public readonly code:
      | 'MEMBER_ACCOUNT_NOT_FOUND'
      | 'NOT_MEMBER_OF_STUDIO'
      | 'ORG_NOT_FOUND'
      | 'DATE_REQUIRED',
  ) {
    super(code);
  }
}

export async function getMemberProfile(memberAccountId: string) {
  const account = await prisma.memberAccount.findUnique({
    where: { id: memberAccountId },
  });

  if (!account) {
    throw new MemberAccountQueryError('MEMBER_ACCOUNT_NOT_FOUND');
  }

  return {
    memberAccount: toMemberAccountPayload(account),
  };
}

export async function getMemberMyClasses(memberAccountId: string) {
  const members = await prisma.member.findMany({
    where: { memberAccountId, status: 'ACTIVE' },
    select: {
      id: true,
      organizationId: true,
      organization: {
        select: {
          id: true,
          name: true,
        },
      },
    },
  });

  if (members.length === 0) {
    return { classes: [] };
  }

  const organizationIds = [...new Set(members.map((member) => member.organizationId))];
  const memberships = await prisma.orgMembership.findMany({
    where: {
      organizationId: { in: organizationIds },
      role: { in: ['OWNER', 'MANAGER', 'STAFF'] },
    },
    select: {
      organizationId: true,
      user: {
        select: {
          id: true,
          name: true,
          profileImage: true,
        },
      },
    },
    orderBy: { createdAt: 'asc' },
  });

  const coachesByOrganization = memberships.reduce<
    Record<string, { id: string; name: string; profileImage: string | null }[]>
  >((acc, membership) => {
    if (!acc[membership.organizationId]) {
      acc[membership.organizationId] = [];
    }
    acc[membership.organizationId].push({
      id: membership.user.id,
      name: membership.user.name,
      profileImage: membership.user.profileImage,
    });
    return acc;
  }, {});

  return {
    classes: members.map((member) => ({
      memberId: member.id,
      organization: {
        id: member.organization.id,
        name: member.organization.name,
      },
      coaches: coachesByOrganization[member.organizationId] ?? [],
    })),
  };
}

export async function getReservationNotice(params: {
  memberAccountId: string;
  organizationId: string;
  coachId?: string;
}) {
  const member = await prisma.member.findFirst({
    where: {
      organizationId: params.organizationId,
      memberAccountId: params.memberAccountId,
      status: 'ACTIVE',
    },
  });
  if (!member) {
    throw new MemberAccountQueryError('NOT_MEMBER_OF_STUDIO');
  }

  const coachId =
    params.coachId ??
    (await prisma.orgMembership.findFirst({
      where: {
        organizationId: params.organizationId,
        role: { in: ['OWNER', 'MANAGER', 'STAFF'] },
      },
      orderBy: { createdAt: 'asc' },
      select: { userId: true },
    }))?.userId;

  if (!coachId) {
    throw new MemberAccountQueryError('ORG_NOT_FOUND');
  }

  const [organization, coach] = await Promise.all([
    prisma.organization.findUnique({
      where: { id: params.organizationId },
      select: {
        id: true,
        name: true,
      },
    }),
    prisma.user.findFirst({
      where: {
        id: coachId,
        memberships: {
          some: { organizationId: params.organizationId },
        },
      },
      select: {
        id: true,
        name: true,
        reservationNoticeText: true,
        reservationNoticeImageUrl: true,
        reservationOpenDaysBefore: true,
        reservationOpenHoursBefore: true,
        reservationCancelDeadlineMinutes: true,
      },
    }),
  ]);

  if (!organization || !coach) {
    throw new MemberAccountQueryError('ORG_NOT_FOUND');
  }

  return {
    organizationId: organization.id,
    organizationName: organization.name,
    coachId: coach.id,
    coachName: coach.name,
    reservationNoticeText: coach.reservationNoticeText,
    reservationNoticeImageUrl: coach.reservationNoticeImageUrl,
    reservationOpenDaysBefore: coach.reservationOpenDaysBefore,
    reservationOpenHoursBefore: coach.reservationOpenHoursBefore,
    reservationCancelDeadlineMinutes: coach.reservationCancelDeadlineMinutes,
  };
}

type CoachReservationPolicy = {
  bookingMode: string;
  reservationOpenDaysBefore: number;
  reservationOpenHoursBefore: number;
};

async function getCoachReservationPolicies(
  organizationId: string,
  coachIds: string[],
) {
  const uniqueCoachIds = [...new Set(coachIds)];
  if (uniqueCoachIds.length === 0) {
    return new Map<string, CoachReservationPolicy>();
  }

  const coaches = await prisma.user.findMany({
    where: {
      id: { in: uniqueCoachIds },
      memberships: {
        some: { organizationId },
      },
    },
    select: {
      id: true,
      bookingMode: true,
      reservationOpenDaysBefore: true,
      reservationOpenHoursBefore: true,
    },
  });

  return new Map(
    coaches.map((coach) => [
      coach.id,
      {
        bookingMode: coach.bookingMode,
        reservationOpenDaysBefore: coach.reservationOpenDaysBefore,
        reservationOpenHoursBefore: coach.reservationOpenHoursBefore,
      },
    ]),
  );
}

export async function getStudioSlots(params: {
  memberAccountId: string;
  organizationId: string;
  date?: string;
  coachId?: string;
}) {
  if (!params.date) {
    throw new MemberAccountQueryError('DATE_REQUIRED');
  }

  const member = await prisma.member.findFirst({
    where: {
      organizationId: params.organizationId,
      memberAccountId: params.memberAccountId,
      status: 'ACTIVE',
    },
  });
  if (!member) {
    throw new MemberAccountQueryError('NOT_MEMBER_OF_STUDIO');
  }

  const slots = await getAvailableSlots({
    organizationId: params.organizationId,
    date: params.date,
    coachId: params.coachId,
    includeCoachNames: true,
  });

  const policies = await getCoachReservationPolicies(
    params.organizationId,
    slots.map((slot) => slot.coachId),
  );

  return slots
    .filter((slot) => slot.isPublic)
    .filter((slot) => {
      const policy = policies.get(slot.coachId);
      if (!policy) return false;
      if (policy.bookingMode !== 'PUBLIC') return false;
      return canReserveAt(params.date!, slot.startTime, {
        reservationOpenDaysBefore: policy.reservationOpenDaysBefore,
        reservationOpenHoursBefore: policy.reservationOpenHoursBefore,
        reservationCancelDeadlineMinutes: 0,
      });
    });
}

export async function getMyReservations(memberAccountId: string) {
  const members = await prisma.member.findMany({
    where: { memberAccountId, status: 'ACTIVE' },
    select: { id: true, organizationId: true, organization: { select: { name: true } } },
  });

  if (members.length === 0) {
    return { reservations: [] };
  }

  const today = parseDateOnly(getKstToday());
  const reservations = await prisma.reservation.findMany({
    where: {
      memberId: { in: members.map((member) => member.id) },
      status: { in: ['PENDING', 'CONFIRMED', 'COMPLETED'] },
      date: { gte: today },
    },
    include: {
      coach: { select: { id: true, name: true } },
      organization: { select: { id: true, name: true } },
    },
    orderBy: [{ date: 'asc' }, { startTime: 'asc' }],
  });

  return {
    reservations: reservations.map((reservation) => ({
      id: reservation.id,
      organizationId: reservation.organizationId,
      organizationName: reservation.organization.name,
      coachId: reservation.coachId,
      coachName: reservation.coach.name,
      date: formatDateOnly(reservation.date),
      startTime: reservation.startTime,
      endTime: reservation.endTime,
      status: reservation.status,
    })),
  };
}

export async function getMemberPackages(memberAccountId: string) {
  const members = await prisma.member.findMany({
    where: { memberAccountId, status: 'ACTIVE' },
    select: { id: true, organizationId: true },
  });

  if (members.length === 0) {
    return { packages: [] };
  }

  const memberPackages = await listMemberPackagesCompat({
    memberIds: members.map((member) => member.id),
  });

  return { packages: memberPackages };
}

export async function getMemberPackageDetail(params: {
  memberAccountId: string;
  memberPackageId: string;
}) {
  const memberPackage = await prisma.memberPackage.findFirst({
    where: {
      id: params.memberPackageId,
      member: {
        memberAccountId: params.memberAccountId,
        status: 'ACTIVE',
      },
    },
    include: {
      package: true,
      sessions: {
        include: {
          coach: { select: { id: true, name: true } },
          reservation: { select: { startTime: true, endTime: true } },
        },
        orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
      },
      adjustments: {
        include: { admin: { select: { id: true, name: true } } },
        orderBy: { createdAt: 'desc' },
      },
    },
  });

  if (!memberPackage) {
    throw new MemberAccountQueryError('NOT_MEMBER_OF_STUDIO');
  }

  return {
    memberPackage: {
      id: memberPackage.id,
      packageId: memberPackage.packageId,
      packageName: memberPackage.package?.name ?? '패키지',
      totalSessions: memberPackage.totalSessions,
      usedSessions: memberPackage.usedSessions,
      remainingSessions: memberPackage.remainingSessions,
      purchaseDate: memberPackage.purchaseDate.toISOString(),
      expiryDate: memberPackage.expiryDate?.toISOString() ?? null,
      status: memberPackage.status,
      pauseStartDate: memberPackage.pauseStartDate
        ? formatDateOnly(memberPackage.pauseStartDate)
        : null,
      pauseEndDate: memberPackage.pauseEndDate
        ? formatDateOnly(memberPackage.pauseEndDate)
        : null,
      pauseExtensionDays: memberPackage.pauseExtensionDays,
    },
    sessions: memberPackage.sessions.map((session) => ({
      id: session.id,
      date: formatDateOnly(session.date),
      startTime: session.reservation?.startTime ?? null,
      endTime: session.reservation?.endTime ?? null,
      coachId: session.coachId,
      coachName: session.coach?.name ?? '',
      attendance: session.attendance,
    })),
    adjustments: memberPackage.adjustments.map((adjustment) => ({
      id: adjustment.id,
      type: adjustment.type,
      sessionDelta: adjustment.sessionDelta,
      expiryDateBefore: adjustment.expiryDateBefore?.toISOString() ?? null,
      expiryDateAfter: adjustment.expiryDateAfter?.toISOString() ?? null,
      reason: adjustment.reason,
      adminId: adjustment.adminId,
      adminName: adjustment.admin?.name ?? '',
      createdAt: adjustment.createdAt.toISOString(),
    })),
  };
}
