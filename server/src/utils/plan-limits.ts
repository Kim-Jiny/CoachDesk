import { prisma } from './prisma';

/** Checks if the center can accept more admin members (all roles count). */
export async function checkAdminLimit(organizationId: string): Promise<boolean> {
  const org = await prisma.organization.findUnique({
    where: { id: organizationId },
    select: { maxAdminCount: true },
  });
  if (!org) return false;

  const currentCount = await prisma.orgMembership.count({
    where: { organizationId },
  });

  return currentCount < org.maxAdminCount;
}

export async function checkMemberLimit(organizationId: string): Promise<boolean> {
  const org = await prisma.organization.findUnique({
    where: { id: organizationId },
    select: { maxMemberCount: true },
  });
  if (!org) return false;

  const currentCount = await prisma.member.count({
    where: { organizationId, status: 'ACTIVE' },
  });

  return currentCount < org.maxMemberCount;
}
