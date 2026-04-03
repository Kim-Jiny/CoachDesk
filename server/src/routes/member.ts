import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { getCurrentOrgId } from '../utils/org-access';
import { decodeMemoFields, encodeMemoFields } from '../utils/memo-fields';

const router = Router();
router.use(authMiddleware);

function serializeMember<T extends { memo?: string | null } & Record<string, unknown>>(member: T) {
  const memoFields = decodeMemoFields(member.memo);
  return {
    ...member,
    quickMemo: memoFields.quickMemo ?? null,
    memo: memoFields.memo ?? null,
  };
}

// ─── List Members ──────────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const { search, status } = req.query;

    const members = await prisma.member.findMany({
      where: {
        organizationId: orgId,
        ...(status ? { status: status as any } : {}),
        ...(search
          ? {
              OR: [
                { name: { contains: search as string, mode: 'insensitive' } },
                { phone: { contains: search as string } },
                { email: { contains: search as string, mode: 'insensitive' } },
              ],
            }
          : {}),
      },
      orderBy: { name: 'asc' },
    });

    res.json(members.map(serializeMember));
  } catch (err) {
    console.error('List members error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Get Member ────────────────────────────────────────────
router.get('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const member = await prisma.member.findFirst({
      where: { id: req.params.id as string, organizationId: orgId },
      include: {
        memberPackages: { include: { package: true }, orderBy: { createdAt: 'desc' } },
        sessions: { orderBy: { date: 'desc' }, take: 10 },
      },
    });

    if (!member) { res.status(404).json({ error: 'Member not found' }); return; }
    res.json(serializeMember(member));
  } catch (err) {
    console.error('Get member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Create Member ─────────────────────────────────────────
const createMemberSchema = z.object({
  name: z.string().min(1),
  phone: z.string().optional(),
  email: z.string().email().optional(),
  birthDate: z.string().optional(),
  gender: z.enum(['MALE', 'FEMALE', 'OTHER']).optional(),
  quickMemo: z.string().optional(),
  memo: z.string().optional(),
});

router.post('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = createMemberSchema.parse(req.body);

    const member = await prisma.member.create({
      data: {
        organizationId: orgId,
        name: body.name,
        phone: body.phone,
        email: body.email,
        birthDate: body.birthDate ? new Date(body.birthDate) : undefined,
        gender: body.gender,
        memo: encodeMemoFields({ quickMemo: body.quickMemo, memo: body.memo }),
      },
    });

    res.status(201).json(serializeMember(member));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Create member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Update Member ─────────────────────────────────────────
const updateMemberSchema = z.object({
  name: z.string().min(1).optional(),
  phone: z.string().optional(),
  email: z.string().email().optional(),
  birthDate: z.string().optional(),
  gender: z.enum(['MALE', 'FEMALE', 'OTHER']).optional(),
  quickMemo: z.string().optional(),
  memo: z.string().optional(),
  status: z.enum(['ACTIVE', 'INACTIVE', 'ARCHIVED']).optional(),
});

router.put('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = updateMemberSchema.parse(req.body);
    const { birthDate, quickMemo, memo, ...rest } = body;
    const shouldUpdateMemo = Object.prototype.hasOwnProperty.call(body, 'quickMemo')
      || Object.prototype.hasOwnProperty.call(body, 'memo');

    const member = await prisma.member.updateMany({
      where: { id: req.params.id as string, organizationId: orgId },
      data: {
        ...rest,
        ...(shouldUpdateMemo ? { memo: encodeMemoFields({ quickMemo, memo }) } : {}),
        birthDate: birthDate ? new Date(birthDate) : undefined,
      },
    });

    if (member.count === 0) { res.status(404).json({ error: 'Member not found' }); return; }

    const updated = await prisma.member.findUnique({ where: { id: req.params.id as string } });
    res.json(updated ? serializeMember(updated) : updated);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Delete Member ─────────────────────────────────────────
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const result = await prisma.member.deleteMany({
      where: { id: req.params.id as string, organizationId: orgId },
    });

    if (result.count === 0) { res.status(404).json({ error: 'Member not found' }); return; }
    res.json({ message: 'Member deleted' });
  } catch (err) {
    console.error('Delete member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
