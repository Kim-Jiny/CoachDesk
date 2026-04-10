import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { getCurrentOrgId } from '../utils/org-access';
import { addDays, formatDateOnly, parseDateOnly } from '../utils/kst-date';
import {
  findMemberPackageCompat,
  listMemberPackagesCompat,
  updateMemberPackagePauseCompat,
} from '../utils/member-package-access';
import { sendPush } from '../utils/firebase';

const router = Router();
router.use(authMiddleware);

function calculatePauseDays(startDate: string, endDate: string) {
  const start = parseDateOnly(startDate);
  const end = parseDateOnly(endDate);
  const diffMs = end.getTime() - start.getTime();
  return Math.floor(diffMs / (24 * 60 * 60 * 1000)) + 1;
}

function extendDate(date: Date, days: number) {
  return parseDateOnly(addDays(formatDateOnly(date), days));
}

// ─── List Packages ─────────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const packages = await prisma.package.findMany({
      where: { organizationId: orgId },
      orderBy: { createdAt: 'desc' },
    });

    res.json(packages);
  } catch (err) {
    console.error('List packages error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Create Package ────────────────────────────────────────
const createPackageSchema = z.object({
  name: z.string().min(1),
  totalSessions: z.number().min(1),
  price: z.number().min(0),
  validDays: z.number().min(1).optional(),
  isActive: z.boolean().optional(),
  isPublic: z.boolean().optional(),
});

router.post('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = createPackageSchema.parse(req.body);

    const pkg = await prisma.package.create({
      data: {
        organizationId: orgId,
        ...body,
      },
    });

    res.status(201).json(pkg);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Create package error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Update Package ────────────────────────────────────────
const updatePackageSchema = createPackageSchema.partial().extend({
  isActive: z.boolean().optional(),
  isPublic: z.boolean().optional(),
});

router.put('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = updatePackageSchema.parse(req.body);
    const existingPackage = await prisma.package.findFirst({
      where: { id: req.params.id as string, organizationId: orgId },
      select: { id: true },
    });
    if (!existingPackage) {
      res.status(404).json({ error: 'Package not found' });
      return;
    }

    const pkg = await prisma.package.update({
      where: { id: existingPackage.id },
      data: body,
    });
    res.json(pkg);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update package error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Assign Package to Member ──────────────────────────────
const assignPackageSchema = z.object({
  memberId: z.string().uuid(),
  packageId: z.string().uuid(),
  paidAmount: z.number().min(0),
  paymentMethod: z.enum(['CASH', 'CARD', 'TRANSFER']).default('CASH'),
});

router.post('/assign', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = assignPackageSchema.parse(req.body);

    const [pkg, member] = await Promise.all([
      prisma.package.findFirst({ where: { id: body.packageId, organizationId: orgId } }),
      prisma.member.findFirst({ where: { id: body.memberId, organizationId: orgId }, select: { id: true } }),
    ]);
    if (!pkg) { res.status(404).json({ error: 'Package not found' }); return; }
    if (!member) { res.status(404).json({ error: 'Member not found' }); return; }

    const expiryDate = pkg.validDays
      ? new Date(Date.now() + pkg.validDays * 24 * 60 * 60 * 1000)
      : undefined;

    const memberPackage = await prisma.memberPackage.create({
      data: {
        memberId: body.memberId,
        packageId: body.packageId,
        totalSessions: pkg.totalSessions,
        remainingSessions: pkg.totalSessions,
        paidAmount: body.paidAmount,
        paymentMethod: body.paymentMethod,
        expiryDate,
      },
      include: { package: true },
    });

    res.status(201).json(memberPackage);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Assign package error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const pauseDecisionSchema = z.object({
  note: z.string().max(300).optional(),
});

router.post('/member-packages/:id/pause/approve', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(
      req.user!.userId,
      req.header('x-organization-id') ?? undefined,
    );
    if (!orgId) {
      res.status(403).json({ error: 'No organization' });
      return;
    }

    pauseDecisionSchema.parse(req.body ?? {});

    const memberPackage = await findMemberPackageCompat({
      id: req.params.id as string,
      organizationId: orgId,
    });
    if (!memberPackage) {
      res.status(404).json({ error: 'Member package not found' });
      return;
    }

    if (memberPackage.pauseRequestStatus !== 'PENDING'
        || !memberPackage.pauseRequestedStartDate
        || !memberPackage.pauseRequestedEndDate) {
      res.status(400).json({ error: '승인 대기 중인 정지 신청이 없습니다' });
      return;
    }

    const startDate = formatDateOnly(new Date(memberPackage.pauseRequestedStartDate));
    const endDate = formatDateOnly(new Date(memberPackage.pauseRequestedEndDate));
    const extensionDays = calculatePauseDays(startDate, endDate);
    const nextExpiryDate = memberPackage.expiryDate
      ? extendDate(new Date(memberPackage.expiryDate), extensionDays)
      : null;

    await updateMemberPackagePauseCompat(memberPackage.id, {
      pauseStartDate: parseDateOnly(startDate),
      pauseEndDate: parseDateOnly(endDate),
      pauseRequestedStartDate: null,
      pauseRequestedEndDate: null,
      pauseRequestStatus: 'NONE',
      pauseExtensionDaysDelta: extensionDays,
      expiryDate: nextExpiryDate,
    });

    const updated = await findMemberPackageCompat({ id: memberPackage.id, organizationId: orgId });

    const memberAccountId = memberPackage.member?.memberAccountId as string | undefined;
    if (memberAccountId) {
      const memberAccount = await prisma.memberAccount.findUnique({
        where: { id: memberAccountId },
        select: { fcmToken: true },
      });
      if (memberAccount?.fcmToken) {
        await sendPush(
          memberAccount.fcmToken,
          '패키지 정지 승인',
          `${startDate}부터 ${endDate}까지 정지 승인되었고, 만료일이 ${extensionDays}일 연장됩니다`,
          { memberPackageId: memberPackage.id },
        );
      }
    }

    res.json({
      message: `정지 승인 완료. 만료일이 ${extensionDays}일 연장됩니다`,
      memberPackage: updated,
      extensionDays,
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Approve pause request error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/member-packages/:id/pause/reject', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(
      req.user!.userId,
      req.header('x-organization-id') ?? undefined,
    );
    if (!orgId) {
      res.status(403).json({ error: 'No organization' });
      return;
    }

    const body = pauseDecisionSchema.parse(req.body ?? {});

    const memberPackage = await findMemberPackageCompat({
      id: req.params.id as string,
      organizationId: orgId,
    });
    if (!memberPackage) {
      res.status(404).json({ error: 'Member package not found' });
      return;
    }

    if (memberPackage.pauseRequestStatus !== 'PENDING') {
      res.status(400).json({ error: '승인 대기 중인 정지 신청이 없습니다' });
      return;
    }

    await updateMemberPackagePauseCompat(memberPackage.id, {
      pauseRequestedStartDate: null,
      pauseRequestedEndDate: null,
      pauseRequestStatus: 'NONE',
      pauseRequestReason: null,
    });

    const memberAccountId = memberPackage.member?.memberAccountId as string | undefined;
    if (memberAccountId) {
      const memberAccount = await prisma.memberAccount.findUnique({
        where: { id: memberAccountId },
        select: { fcmToken: true },
      });
      if (memberAccount?.fcmToken) {
        await sendPush(
          memberAccount.fcmToken,
          '패키지 정지 반려',
          (body.note?.trim().length ?? 0) > 0
            ? `정지 신청이 반려되었습니다: ${body.note!.trim()}`
            : '패키지 정지 신청이 반려되었습니다',
          { memberPackageId: memberPackage.id },
        );
      }
    }

    res.json({ message: '정지 신청을 반려했습니다' });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Reject pause request error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Get Member Packages ───────────────────────────────────
router.get('/member/:memberId', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const member = await prisma.member.findFirst({
      where: { id: req.params.memberId as string, organizationId: orgId },
      select: { id: true },
    });
    if (!member) {
      res.status(404).json({ error: 'Member not found' });
      return;
    }

    const memberPackages = await listMemberPackagesCompat({
      memberId: member.id,
      organizationId: orgId,
    });

    res.json(memberPackages);
  } catch (err) {
    console.error('Get member packages error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
