import { prisma } from '../../utils/prisma';
import { listMemberPackagesCompat } from '../../utils/member-package-access';

export async function listPackagesWithStats(params: {
  organizationId: string;
  userId: string;
}) {
  const [packages, memberPackages] = await Promise.all([
    prisma.package.findMany({
      where: {
        organizationId: params.organizationId,
        OR: [
          { scope: 'CENTER' },
          { scope: 'ADMIN', coachId: params.userId },
        ],
      },
      include: { coach: { select: { id: true, name: true } } },
      orderBy: { createdAt: 'desc' },
    }),
    prisma.memberPackage.findMany({
      where: {
        package: {
          organizationId: params.organizationId,
          OR: [
            { scope: 'CENTER' },
            { scope: 'ADMIN', coachId: params.userId },
          ],
        },
      },
      select: {
        packageId: true,
        memberId: true,
        usedSessions: true,
        status: true,
      },
    }),
  ]);

  const statsByPackageId = new Map<
    string,
    {
      activeMemberIds: Set<string>;
      totalUsedSessions: number;
    }
  >();

  for (const memberPackage of memberPackages) {
    const current = statsByPackageId.get(memberPackage.packageId) ?? {
      activeMemberIds: new Set<string>(),
      totalUsedSessions: 0,
    };
    current.totalUsedSessions += memberPackage.usedSessions;
    if (memberPackage.status === 'ACTIVE') {
      current.activeMemberIds.add(memberPackage.memberId);
    }
    statsByPackageId.set(memberPackage.packageId, current);
  }

  return packages.map((pkg) => {
    const stats = statsByPackageId.get(pkg.id);
    return {
      ...pkg,
      coachName: pkg.coach?.name ?? null,
      activeMemberCount: stats?.activeMemberIds.size ?? 0,
      totalUsedSessions: stats?.totalUsedSessions ?? 0,
    };
  });
}

export async function getMemberPackages(params: {
  organizationId: string;
  memberId: string;
}) {
  const member = await prisma.member.findFirst({
    where: { id: params.memberId, organizationId: params.organizationId },
    select: { id: true },
  });

  if (!member) {
    return null;
  }

  return listMemberPackagesCompat({
    memberId: member.id,
    organizationId: params.organizationId,
  });
}
