import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { getCurrentOrgId } from '../utils/org-access';
import { decodeMemoFields, encodeMemoFields } from '../utils/memo-fields';
import { deriveMemberPackageStatus } from '../utils/member-package-status';
import { listMemberPackagesCompat } from '../utils/member-package-access';

const router = Router();
router.use(authMiddleware);

function serializeMember<T extends {
  memo?: string | null;
  memberAccountId?: string | null;
  memberGroup?: { id: string; name: string; sortOrder: number } | null;
  memberPackages?: Array<{
    status: string;
    remainingSessions: number;
    expiryDate?: Date | string | null;
    pausedUntil?: Date | string | null;
  }>;
} & Record<string, unknown>>(member: T) {
  const memoFields = decodeMemoFields(member.memo);
  const packageStatus = deriveMemberPackageStatus(member.memberPackages ?? []);
  return {
    ...member,
    quickMemo: memoFields.quickMemo ?? null,
    memo: memoFields.memo ?? null,
    packageStatus: packageStatus.packageStatus,
    packageStatusLabel: packageStatus.packageStatusLabel,
    hasMemberAccount: member.memberAccountId != null,
    memberSourceLabel: member.memberAccountId != null ? '앱 가입 회원' : '관리자 등록 회원',
    memberAccessLabel: member.memberAccountId != null ? '채팅 가능' : '채팅 미연동',
  };
}

const createMemberGroupSchema = z.object({
  name: z.string().min(1).max(40),
});

const updateMemberGroupSchema = z.object({
  name: z.string().min(1).max(40).optional(),
  sortOrder: z.number().int().min(0).optional(),
});

const moveMemberGroupSchema = z.object({
  memberGroupId: z.string().uuid().nullable(),
});

router.get('/groups', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(
      req.user!.userId,
      req.header('x-organization-id') ?? undefined,
    );
    if (!orgId) {
      res.status(403).json({ error: 'No organization' });
      return;
    }

    const groups = await prisma.memberGroup.findMany({
      where: { organizationId: orgId },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    });

    res.json(groups);
  } catch (err) {
    console.error('List member groups error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/groups', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(
      req.user!.userId,
      req.header('x-organization-id') ?? undefined,
    );
    if (!orgId) {
      res.status(403).json({ error: 'No organization' });
      return;
    }

    const body = createMemberGroupSchema.parse(req.body);
    const lastGroup = await prisma.memberGroup.findFirst({
      where: { organizationId: orgId },
      orderBy: { sortOrder: 'desc' },
      select: { sortOrder: true },
    });

    const group = await prisma.memberGroup.create({
      data: {
        organizationId: orgId,
        name: body.name.trim(),
        sortOrder: (lastGroup?.sortOrder ?? -1) + 1,
      },
    });

    res.status(201).json(group);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Create member group error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/groups/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(
      req.user!.userId,
      req.header('x-organization-id') ?? undefined,
    );
    if (!orgId) {
      res.status(403).json({ error: 'No organization' });
      return;
    }

    const body = updateMemberGroupSchema.parse(req.body);
    const group = await prisma.memberGroup.updateMany({
      where: { id: req.params.id as string, organizationId: orgId },
      data: {
        ...(body.name != null ? { name: body.name.trim() } : {}),
        ...(body.sortOrder != null ? { sortOrder: body.sortOrder } : {}),
      },
    });

    if (group.count === 0) {
      res.status(404).json({ error: 'Group not found' });
      return;
    }

    const updated = await prisma.memberGroup.findUnique({
      where: { id: req.params.id as string },
    });
    res.json(updated);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update member group error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/groups/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(
      req.user!.userId,
      req.header('x-organization-id') ?? undefined,
    );
    if (!orgId) {
      res.status(403).json({ error: 'No organization' });
      return;
    }

    const group = await prisma.memberGroup.findFirst({
      where: { id: req.params.id as string, organizationId: orgId },
      select: { id: true },
    });

    if (!group) {
      res.status(404).json({ error: 'Group not found' });
      return;
    }

    await prisma.$transaction([
      prisma.member.updateMany({
        where: { memberGroupId: group.id, organizationId: orgId },
        data: { memberGroupId: null },
      }),
      prisma.memberGroup.delete({ where: { id: group.id } }),
    ]);

    res.json({ message: 'Group deleted' });
  } catch (err) {
    console.error('Delete member group error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

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
      include: {
        memberGroup: {
          select: {
            id: true,
            name: true,
            sortOrder: true,
          },
        },
      },
      orderBy: { name: 'asc' },
    });

    const memberPackages = await listMemberPackagesCompat({
      memberIds: members.map((member) => member.id),
      organizationId: orgId,
    });
    const packagesByMemberId = new Map<string, any[]>();
    for (const memberPackage of memberPackages) {
      const current = packagesByMemberId.get(memberPackage.memberId) ?? [];
      current.push(memberPackage);
      packagesByMemberId.set(memberPackage.memberId, current);
    }

    res.json(members.map((member) => serializeMember({
      ...member,
      memberPackages: packagesByMemberId.get(member.id) ?? [],
    })));
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
        sessions: { orderBy: { date: 'desc' }, take: 10 },
        memberGroup: {
          select: {
            id: true,
            name: true,
            sortOrder: true,
          },
        },
      },
    });

    if (!member) { res.status(404).json({ error: 'Member not found' }); return; }
    const memberPackages = await listMemberPackagesCompat({
      memberId: member.id,
      organizationId: orgId,
    });
    res.json(serializeMember({
      ...member,
      memberPackages,
    }));
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

    const updated = await prisma.member.findUnique({
      where: { id: req.params.id as string },
    });
    if (!updated) {
      res.json(updated);
      return;
    }
    const memberPackages = await listMemberPackagesCompat({
      memberId: updated.id,
      organizationId: orgId,
    });
    res.json(serializeMember({
      ...updated,
      memberPackages,
    }));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.patch('/:id/group', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(
      req.user!.userId,
      req.header('x-organization-id') ?? undefined,
    );
    if (!orgId) {
      res.status(403).json({ error: 'No organization' });
      return;
    }

    const body = moveMemberGroupSchema.parse(req.body);

    if (body.memberGroupId != null) {
      const group = await prisma.memberGroup.findFirst({
        where: { id: body.memberGroupId, organizationId: orgId },
        select: { id: true },
      });
      if (!group) {
        res.status(404).json({ error: 'Group not found' });
        return;
      }
    }

    const moved = await prisma.member.updateMany({
      where: { id: req.params.id as string, organizationId: orgId },
      data: { memberGroupId: body.memberGroupId },
    });

    if (moved.count === 0) {
      res.status(404).json({ error: 'Member not found' });
      return;
    }

    const member = await prisma.member.findFirst({
      where: { id: req.params.id as string, organizationId: orgId },
      include: {
        memberGroup: {
          select: {
            id: true,
            name: true,
            sortOrder: true,
          },
        },
      },
    });

    if (!member) {
      res.status(404).json({ error: 'Member not found' });
      return;
    }

    const memberPackages = await listMemberPackagesCompat({
      memberId: member.id,
      organizationId: orgId,
    });

    res.json(serializeMember({
      ...member,
      memberPackages,
    }));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Move member group error:', err);
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
