import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { getCurrentOrgId } from '../utils/org-access';

const router = Router();
router.use(authMiddleware);

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
});

router.post('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = createPackageSchema.parse(req.body);

    const pkg = await prisma.package.create({
      data: { organizationId: orgId, ...body },
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

    const memberPackages = await prisma.memberPackage.findMany({
      where: { memberId: member.id },
      include: { package: true },
      orderBy: { createdAt: 'desc' },
    });

    res.json(memberPackages);
  } catch (err) {
    console.error('Get member packages error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
