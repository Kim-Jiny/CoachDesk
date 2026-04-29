import { Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { prisma } from './prisma';
import { env } from '../config/env';

const ADMIN_TOKEN_KIND = 'admin';
const ADMIN_TOKEN_EXPIRES_IN = '12h';

export interface AdminTokenPayload {
  adminId: string;
  username: string;
  kind: typeof ADMIN_TOKEN_KIND;
}

export function signAdminToken(payload: { adminId: string; username: string }) {
  return jwt.sign({ ...payload, kind: ADMIN_TOKEN_KIND }, env.JWT_SECRET, {
    expiresIn: ADMIN_TOKEN_EXPIRES_IN,
  });
}

export function verifyAdminToken(token: string): AdminTokenPayload | null {
  try {
    const decoded = jwt.verify(token, env.JWT_SECRET) as AdminTokenPayload;
    if (decoded.kind !== ADMIN_TOKEN_KIND) return null;
    return decoded;
  } catch {
    return null;
  }
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      adminAccount?: { id: string; username: string };
    }
  }
}

export function adminAuthMiddleware(
  req: Request,
  res: Response,
  next: NextFunction,
) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }
  const payload = verifyAdminToken(header.slice(7));
  if (!payload) {
    res.status(401).json({ error: 'Invalid admin token' });
    return;
  }
  req.adminAccount = { id: payload.adminId, username: payload.username };
  next();
}

const DEFAULT_ADMIN_USERNAME = 'jiny';
const DEFAULT_ADMIN_PASSWORD = '1204';

export async function ensureDefaultAdminAccount() {
  const count = await prisma.adminAccount.count();
  if (count > 0) return;
  const hashed = await bcrypt.hash(DEFAULT_ADMIN_PASSWORD, 10);
  await prisma.adminAccount.create({
    data: { username: DEFAULT_ADMIN_USERNAME, password: hashed },
  });
  console.log(
    `[admin] Default admin account created (username: ${DEFAULT_ADMIN_USERNAME}). Change the password in /admin.`,
  );
}
