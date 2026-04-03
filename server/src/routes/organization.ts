import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { getCurrentMembership } from '../utils/org-access';

const router = Router();
router.use(authMiddleware);

// ─── Get My Organization ───────────────────────────────────
router.get('/mine', async (req: Request, res: Response) => {
  try {
    const currentMembership = await getCurrentMembership(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!currentMembership) {
      res.status(404).json({ error: 'No organization found' });
      return;
    }

    const membership = await prisma.orgMembership.findUnique({
      where: {
        userId_organizationId: {
          userId: req.user!.userId,
          organizationId: currentMembership.organizationId,
        },
      },
      include: {
        organization: {
          include: {
            memberships: {
              include: { user: { select: { id: true, name: true, email: true, profileImage: true } } },
              orderBy: { createdAt: 'asc' },
            },
          },
        },
      },
    });

    if (!membership) {
      res.status(404).json({ error: 'No organization found' });
      return;
    }

    res.json({
      ...membership.organization,
      myRole: membership.role,
      members: membership.organization.memberships.map((m) => ({
        ...m.user,
        role: m.role,
      })),
    });
  } catch (err) {
    console.error('Get org error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Update Organization ───────────────────────────────────
const updateOrgSchema = z.object({
  name: z.string().min(1).optional(),
  description: z.string().optional(),
  bookingMode: z.enum(['PRIVATE', 'PUBLIC']).optional(),
  reservationPolicy: z.enum(['AUTO_CONFIRM', 'REQUEST_APPROVAL']).optional(),
});

router.put('/:id', async (req: Request, res: Response) => {
  try {
    const body = updateOrgSchema.parse(req.body);

    const membership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId: req.user!.userId, organizationId: req.params.id as string } },
    });

    if (!membership || !['OWNER', 'ADMIN'].includes(membership.role)) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

    const org = await prisma.organization.update({
      where: { id: req.params.id as string },
      data: body,
    });

    res.json(org);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update org error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Join Organization by Invite Code ──────────────────────
router.post('/join', async (req: Request, res: Response) => {
  try {
    const { inviteCode } = req.body;
    if (!inviteCode) {
      res.status(400).json({ error: 'Invite code required' });
      return;
    }

    const org = await prisma.organization.findUnique({ where: { inviteCode } });
    if (!org) {
      res.status(404).json({ error: 'Invalid invite code' });
      return;
    }

    const existing = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId: req.user!.userId, organizationId: org.id } },
    });

    if (existing) {
      res.status(409).json({ error: 'Already a member of this organization' });
      return;
    }

    await prisma.orgMembership.create({
      data: {
        userId: req.user!.userId,
        organizationId: org.id,
        role: 'COACH',
      },
    });

    res.json({ message: 'Joined organization', organization: { id: org.id, name: org.name } });
  } catch (err) {
    console.error('Join org error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
