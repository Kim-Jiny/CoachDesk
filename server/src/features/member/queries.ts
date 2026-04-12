import { prisma } from '../../utils/prisma';
import { listMemberPackagesCompat } from '../../utils/member-package-access';

export const memberGroupInclude = {
  memberGroup: {
    select: {
      id: true,
      name: true,
      sortOrder: true,
    },
  },
} as const;

export async function listMemberGroups(organizationId: string) {
  return prisma.memberGroup.findMany({
    where: { organizationId },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });
}

export async function listMembers(params: {
  organizationId: string;
  search?: string;
  status?: string;
}) {
  const members = await prisma.member.findMany({
    where: {
      organizationId: params.organizationId,
      ...(params.status ? { status: params.status as any } : {}),
      ...(params.search
        ? {
            OR: [
              { name: { contains: params.search, mode: 'insensitive' } },
              { phone: { contains: params.search } },
              { email: { contains: params.search, mode: 'insensitive' } },
            ],
          }
        : {}),
    },
    include: memberGroupInclude,
    orderBy: { name: 'asc' },
  });

  const memberPackages = await listMemberPackagesCompat({
    memberIds: members.map((member) => member.id),
    organizationId: params.organizationId,
  });
  const packagesByMemberId = new Map<string, any[]>();

  for (const memberPackage of memberPackages) {
    const current = packagesByMemberId.get(memberPackage.memberId) ?? [];
    current.push(memberPackage);
    packagesByMemberId.set(memberPackage.memberId, current);
  }

  return members.map((member) => ({
    ...member,
    memberPackages: packagesByMemberId.get(member.id) ?? [],
  }));
}

export async function getMemberWithPackages(params: {
  organizationId: string;
  memberId: string;
}) {
  const member = await prisma.member.findFirst({
    where: { id: params.memberId, organizationId: params.organizationId },
    include: {
      sessions: { orderBy: { date: 'desc' }, take: 10 },
      ...memberGroupInclude,
    },
  });

  if (!member) {
    return null;
  }

  const memberPackages = await listMemberPackagesCompat({
    memberId: member.id,
    organizationId: params.organizationId,
  });

  return {
    ...member,
    memberPackages,
  };
}

export async function getMemberSummaryWithPackages(params: {
  organizationId: string;
  memberId: string;
}) {
  const member = await prisma.member.findFirst({
    where: { id: params.memberId, organizationId: params.organizationId },
    include: memberGroupInclude,
  });

  if (!member) {
    return null;
  }

  const memberPackages = await listMemberPackagesCompat({
    memberId: member.id,
    organizationId: params.organizationId,
  });

  return {
    ...member,
    memberPackages,
  };
}
