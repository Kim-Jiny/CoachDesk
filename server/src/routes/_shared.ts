import { Request, Response } from 'express';
import { ZodError } from 'zod';
import { OrgRole } from '@prisma/client';
import { prisma } from '../utils/prisma';
import { getCurrentOrgId } from '../utils/org-access';

export async function requireCurrentOrgId(
  req: Request,
  res: Response,
): Promise<string | null> {
  const orgId = await getCurrentOrgId(
    req.user!.userId,
    req.header('x-organization-id') ?? undefined,
  );

  if (!orgId) {
    res.status(403).json({ error: 'No organization' });
    return null;
  }

  return orgId;
}

/**
 * Checks the current user's role in the given org.
 * Returns the role if allowed, or sends 403 and returns null.
 */
export async function requireOrgRole(
  req: Request,
  res: Response,
  orgId: string,
  allowedRoles: OrgRole[],
): Promise<OrgRole | null> {
  const membership = await prisma.orgMembership.findUnique({
    where: {
      userId_organizationId: {
        userId: req.user!.userId,
        organizationId: orgId,
      },
    },
  });

  if (!membership || !allowedRoles.includes(membership.role)) {
    res.status(403).json({ error: 'Insufficient permissions' });
    return null;
  }

  return membership.role;
}

export function respondValidationError(res: Response, err: unknown): boolean {
  if (err instanceof ZodError) {
    res.status(400).json({ error: 'Validation error', details: err.errors });
    return true;
  }

  return false;
}
