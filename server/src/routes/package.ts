import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { authMiddleware } from '../middleware/auth';
import { requireCurrentOrgId, requireOrgRole, respondValidationError } from './_shared';
import {
  approvePauseRequest,
  assignPackageToMember,
  createPackage,
  PackageMutationError,
  rejectPauseRequest,
  updatePackage,
} from '../features/package/mutations';
import {
  getMemberPackages,
  listPackagesWithStats,
} from '../features/package/queries';

const router = Router();
router.use(authMiddleware);

// ─── List Packages ─────────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    res.json(await listPackagesWithStats({
      organizationId: orgId,
      userId: req.user!.userId,
    }));
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
  scope: z.enum(['CENTER', 'ADMIN']).default('CENTER'),
});

router.post('/', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const body = createPackageSchema.parse(req.body);
    const { scope, ...packageData } = body;
    if (scope === 'CENTER' && role === 'STAFF') {
      res.status(403).json({ error: '센터 패키지는 소유자 또는 매니저만 만들 수 있습니다' });
      return;
    }
    const pkg = await createPackage({
      organizationId: orgId,
      scope,
      coachId: scope === 'ADMIN' ? req.user!.userId : null,
      ...packageData,
    });

    res.status(201).json(pkg);
  } catch (err) {
    if (respondValidationError(res, err)) return;
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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const body = updatePackageSchema.parse(req.body);
    const { scope, ...packageData } = body;
    if (scope === 'CENTER' && role === 'STAFF') {
      res.status(403).json({ error: '센터 패키지는 소유자 또는 매니저만 수정할 수 있습니다' });
      return;
    }
    const pkg = await updatePackage({
      organizationId: orgId,
      userId: req.user!.userId,
      canManageCenterPackage: role !== 'STAFF',
      packageId: req.params.id as string,
      scope,
      coachId: scope === undefined
        ? undefined
        : scope === 'ADMIN'
          ? req.user!.userId
          : null,
      ...packageData,
    });
    res.json(pkg);
  } catch (err) {
    if (err instanceof PackageMutationError && err.code === 'PACKAGE_NOT_FOUND') {
      res.status(404).json({ error: 'Package not found' });
      return;
    }
    if (respondValidationError(res, err)) return;
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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const body = assignPackageSchema.parse(req.body);
    const memberPackage = await assignPackageToMember({
      organizationId: orgId,
      userId: req.user!.userId,
      canManageCenterPackage: role !== 'STAFF',
      ...body,
    });

    res.status(201).json(memberPackage);
  } catch (err) {
    if (err instanceof PackageMutationError) {
      if (err.code === 'PACKAGE_NOT_FOUND') {
        res.status(404).json({ error: 'Package not found' });
        return;
      }
      if (err.code === 'MEMBER_NOT_FOUND') {
        res.status(404).json({ error: 'Member not found' });
        return;
      }
    }
    if (respondValidationError(res, err)) return;
    console.error('Assign package error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const pauseDecisionSchema = z.object({
  note: z.string().max(300).optional(),
});

router.post('/member-packages/:id/pause/approve', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    pauseDecisionSchema.parse(req.body ?? {});
    const { memberPackage, extensionDays } = await approvePauseRequest({
      organizationId: orgId,
      memberPackageId: req.params.id as string,
    });

    res.json({
      message: `정지 승인 완료. 만료일이 ${extensionDays}일 연장됩니다`,
      memberPackage,
      extensionDays,
    });
  } catch (err) {
    if (err instanceof PackageMutationError) {
      if (err.code === 'MEMBER_PACKAGE_NOT_FOUND') {
        res.status(404).json({ error: 'Member package not found' });
        return;
      }
      if (err.code === 'NO_PENDING_PAUSE_REQUEST') {
        res.status(400).json({ error: '승인 대기 중인 정지 신청이 없습니다' });
        return;
      }
    }
    if (respondValidationError(res, err)) return;
    console.error('Approve pause request error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/member-packages/:id/pause/reject', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    const body = pauseDecisionSchema.parse(req.body ?? {});
    await rejectPauseRequest({
      organizationId: orgId,
      memberPackageId: req.params.id as string,
      note: body.note,
    });

    res.json({ message: '정지 신청을 반려했습니다' });
  } catch (err) {
    if (err instanceof PackageMutationError) {
      if (err.code === 'MEMBER_PACKAGE_NOT_FOUND') {
        res.status(404).json({ error: 'Member package not found' });
        return;
      }
      if (err.code === 'NO_PENDING_PAUSE_REQUEST') {
        res.status(400).json({ error: '승인 대기 중인 정지 신청이 없습니다' });
        return;
      }
    }
    if (respondValidationError(res, err)) return;
    console.error('Reject pause request error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Get Member Packages ───────────────────────────────────
router.get('/member/:memberId', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const memberPackages = await getMemberPackages({
      organizationId: orgId,
      memberId: req.params.memberId as string,
    });
    if (!memberPackages) {
      res.status(404).json({ error: 'Member not found' });
      return;
    }

    res.json(memberPackages);
  } catch (err) {
    console.error('Get member packages error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
