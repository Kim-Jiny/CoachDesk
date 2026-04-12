import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { authMiddleware } from '../middleware/auth';
import { requireCurrentOrgId, requireOrgRole, respondValidationError } from './_shared';
import {
  createMember,
  createMemberGroup,
  deleteMember,
  deleteMemberGroup,
  MemberMutationError,
  moveMemberToGroup,
  updateMember,
  updateMemberGroup,
} from '../features/member/mutations';
import {
  getMemberSummaryWithPackages,
  getMemberWithPackages,
  listMemberGroups,
  listMembers,
} from '../features/member/queries';
import { serializeMember } from '../features/member/serializer';

const router = Router();
router.use(authMiddleware);

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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    res.json(await listMemberGroups(orgId));
  } catch (err) {
    console.error('List member groups error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/groups', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    const body = createMemberGroupSchema.parse(req.body);
    const group = await createMemberGroup({
      organizationId: orgId,
      name: body.name,
    });

    res.status(201).json(group);
  } catch (err) {
    if (respondValidationError(res, err)) return;
    console.error('Create member group error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/groups/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    const body = updateMemberGroupSchema.parse(req.body);
    const updated = await updateMemberGroup({
      organizationId: orgId,
      groupId: req.params.id as string,
      name: body.name,
      sortOrder: body.sortOrder,
    });
    res.json(updated);
  } catch (err) {
    if (err instanceof MemberMutationError && err.code === 'GROUP_NOT_FOUND') {
      res.status(404).json({ error: 'Group not found' });
      return;
    }
    if (respondValidationError(res, err)) return;
    console.error('Update member group error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/groups/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    await deleteMemberGroup({
      organizationId: orgId,
      groupId: req.params.id as string,
    });

    res.json({ message: 'Group deleted' });
  } catch (err) {
    if (err instanceof MemberMutationError && err.code === 'GROUP_NOT_FOUND') {
      res.status(404).json({ error: 'Group not found' });
      return;
    }
    console.error('Delete member group error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── List Members ──────────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const { search, status } = req.query;
    const members = await listMembers({
      organizationId: orgId,
      search: typeof search === 'string' ? search : undefined,
      status: typeof status === 'string' ? status : undefined,
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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const member = await getMemberWithPackages({
      organizationId: orgId,
      memberId: req.params.id as string,
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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    const body = createMemberSchema.parse(req.body);
    const member = await createMember({
      organizationId: orgId,
      ...body,
    });

    res.status(201).json(serializeMember(member));
  } catch (err) {
    if (respondValidationError(res, err)) return;
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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    const body = updateMemberSchema.parse(req.body);
    const updated = await updateMember({
      organizationId: orgId,
      memberId: req.params.id as string,
      ...body,
    });
    if (!updated) {
      res.json(updated);
      return;
    }
    res.json(serializeMember(updated));
  } catch (err) {
    if (err instanceof MemberMutationError && err.code === 'MEMBER_NOT_FOUND') {
      res.status(404).json({ error: 'Member not found' });
      return;
    }
    if (respondValidationError(res, err)) return;
    console.error('Update member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.patch('/:id/group', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    const body = moveMemberGroupSchema.parse(req.body);
    const member = await moveMemberToGroup({
      organizationId: orgId,
      memberId: req.params.id as string,
      memberGroupId: body.memberGroupId,
    });
    if (!member) {
      res.status(404).json({ error: 'Member not found' });
      return;
    }
    res.json(serializeMember(member));
  } catch (err) {
    if (err instanceof MemberMutationError) {
      if (err.code === 'GROUP_NOT_FOUND') {
        res.status(404).json({ error: 'Group not found' });
        return;
      }
      if (err.code === 'MEMBER_NOT_FOUND') {
        res.status(404).json({ error: 'Member not found' });
        return;
      }
    }
    if (respondValidationError(res, err)) return;
    console.error('Move member group error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Delete Member ─────────────────────────────────────────
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER']))) return;

    await deleteMember({
      organizationId: orgId,
      memberId: req.params.id as string,
    });
    res.json({ message: 'Member deleted' });
  } catch (err) {
    if (err instanceof MemberMutationError && err.code === 'MEMBER_NOT_FOUND') {
      res.status(404).json({ error: 'Member not found' });
      return;
    }
    console.error('Delete member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
