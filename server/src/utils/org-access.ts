import { OrgMembership, Organization } from '@prisma/client';
import { prisma } from './prisma';

export type MembershipWithOrganization = OrgMembership & {
  organization?: Organization;
};

export function pickPrimaryMembership<T extends { createdAt: Date }>(memberships: T[]): T | null {
  if (memberships.length == 0) return null;

  return memberships.reduce((latest, current) => {
    return current.createdAt > latest.createdAt ? current : latest;
  });
}

export async function getCurrentMembership(userId: string, preferredOrganizationId?: string) {
  if (preferredOrganizationId) {
    return prisma.orgMembership.findUnique({
      where: {
        userId_organizationId: {
          userId,
          organizationId: preferredOrganizationId,
        },
      },
      include: { organization: true },
    });
  }

  return prisma.orgMembership.findFirst({
    where: { userId },
    orderBy: { createdAt: 'desc' },
    include: { organization: true },
  });
}

export async function getCurrentOrgId(userId: string, preferredOrganizationId?: string): Promise<string | null> {
  const membership = await getCurrentMembership(userId, preferredOrganizationId);
  return membership?.organizationId ?? null;
}

export async function isUserInOrganization(userId: string, organizationId: string): Promise<boolean> {
  const membership = await prisma.orgMembership.findUnique({
    where: { userId_organizationId: { userId, organizationId } },
    select: { id: true },
  });

  return membership != null;
}
