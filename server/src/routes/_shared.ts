import { Request, Response } from 'express';
import { ZodError } from 'zod';
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

export function respondValidationError(res: Response, err: unknown): boolean {
  if (err instanceof ZodError) {
    res.status(400).json({ error: 'Validation error', details: err.errors });
    return true;
  }

  return false;
}
