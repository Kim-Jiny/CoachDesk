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
      role: 'COACH',
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

  const organization = await prisma.organization.findUnique({
    where: { id: params.organizationId },
    select: {
      id: true,
      name: true,
      reservationNoticeText: true,
      reservationNoticeImageUrl: true,
      reservationOpenDaysBefore: true,
      reservationOpenHoursBefore: true,
      reservationCancelDeadlineMinutes: true,
    },
  });
  if (!organization) {
    throw new MemberAccountQueryError('ORG_NOT_FOUND');
  }

  return {
    organizationId: organization.id,
    organizationName: organization.name,
    reservationNoticeText: organization.reservationNoticeText,
    reservationNoticeImageUrl: organization.reservationNoticeImageUrl,
    reservationOpenDaysBefore: organization.reservationOpenDaysBefore,
    reservationOpenHoursBefore: organization.reservationOpenHoursBefore,
    reservationCancelDeadlineMinutes: organization.reservationCancelDeadlineMinutes,
  };
}

export async function getStudioSlots(params: {
  memberAccountId: string;
  organizationId: string;
  date?: string;
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

  const [slots, organization] = await Promise.all([
    getAvailableSlots({
      organizationId: params.organizationId,
      date: params.date,
      includeCoachNames: true,
    }),
    prisma.organization.findUnique({
      where: { id: params.organizationId },
      select: {
        reservationOpenDaysBefore: true,
        reservationOpenHoursBefore: true,
      },
    }),
  ]);

  if (!organization) {
    throw new MemberAccountQueryError('ORG_NOT_FOUND');
  }

  return slots
    .filter((slot) => slot.isPublic)
    .filter((slot) =>
      canReserveAt(params.date!, slot.startTime, {
        reservationOpenDaysBefore: organization.reservationOpenDaysBefore,
        reservationOpenHoursBefore: organization.reservationOpenHoursBefore,
        reservationCancelDeadlineMinutes: 0,
      }),
    );
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
