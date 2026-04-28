import { Request, Response } from 'express';
import { env } from '../config/env';

export function isSuperAdminEmail(email?: string | null) {
  if (!email) return false;
  return env.SUPER_ADMIN_EMAILS.includes(email.trim().toLowerCase());
}

export function isSuperAdminRequest(req: Request) {
  return isSuperAdminEmail(req.user?.email);
}

export function requireSuperAdmin(req: Request, res: Response) {
  if (!isSuperAdminRequest(req)) {
    res.status(403).json({ error: 'Super admin access required' });
    return false;
  }
  return true;
}
