import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { sendPush } from '../utils/firebase';
import { shouldSendPushForType } from '../utils/notification-preferences';
import { checkAdminLimit } from '../utils/plan-limits';

const router = Router();

// ─── Create Center ────────────────────────────────────────
const createCenterSchema = z.object({
  name: z.string().min(1).max(50),
  description: z.string().max(200).optional(),
});

router.post('/', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = createCenterSchema.parse(req.body);
    const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();

    const result = await prisma.$transaction(async (tx) => {
      const org = await tx.organization.create({
        data: {
          name: body.name,
          description: body.description,
          inviteCode,
        },
      });

      await tx.orgMembership.create({
        data: {
          userId: req.user!.userId,
          organizationId: org.id,
          role: 'OWNER',
        },
      });

      return org;
    });

    res.status(201).json({
      id: result.id,
      name: result.name,
      description: result.description,
      inviteCode: result.inviteCode,
      role: 'OWNER',
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Create center error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── List My Centers ──────────────────────────────────────
router.get('/', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberships = await prisma.orgMembership.findMany({
      where: { userId: req.user!.userId },
      include: {
        organization: {
          include: {
            _count: { select: { members: { where: { status: 'ACTIVE' } } } },
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    const centers = memberships.map((m) => ({
      id: m.organization.id,
      name: m.organization.name,
      description: m.organization.description,
      inviteCode: m.organization.inviteCode,
      role: m.role,
      memberCount: m.organization._count.members,
      createdAt: m.createdAt.toISOString(),
    }));

    res.json({ centers });
  } catch (err) {
    console.error('List centers error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Request to Join Center ───────────────────────────────
const joinRequestSchema = z.object({
  inviteCode: z.string().min(1),
  message: z.string().max(200).optional(),
});

router.post('/join-request', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = joinRequestSchema.parse(req.body);
    const inviteCode = body.inviteCode.trim().toUpperCase();
    const userId = req.user!.userId;

    const org = await prisma.organization.findUnique({ where: { inviteCode } });
    if (!org) {
      res.status(404).json({ error: 'Invalid invite code' });
      return;
    }

    // Already a member?
    const existingMembership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId, organizationId: org.id } },
    });
    if (existingMembership) {
      res.status(409).json({ error: 'Already a member of this center' });
      return;
    }

    // Already has pending request?
    const existingRequest = await prisma.centerJoinRequest.findFirst({
      where: { userId, organizationId: org.id, status: 'PENDING' },
    });
    if (existingRequest) {
      res.status(409).json({ error: 'Already has a pending request' });
      return;
    }

    // Check admin limit
    const withinLimit = await checkAdminLimit(org.id);
    if (!withinLimit) {
      res.status(409).json({ error: 'Center has reached maximum admin count' });
      return;
    }

    const request = await prisma.centerJoinRequest.create({
      data: {
        userId,
        organizationId: org.id,
        message: body.message,
      },
    });

    // Notify center owner
    const owners = await prisma.orgMembership.findMany({
      where: { organizationId: org.id, role: 'OWNER' },
      include: { user: { select: { fcmToken: true, notificationPreferences: true } } },
    });

    const requester = await prisma.user.findUnique({
      where: { id: userId },
      select: { name: true },
    });

    for (const owner of owners) {
      if (
        owner.user.fcmToken &&
        shouldSendPushForType(owner.user.notificationPreferences, 'JOIN_REQUEST')
      ) {
        sendPush(
          owner.user.fcmToken,
          '센터 합류 신청',
          `${requester?.name ?? '관리자'}님이 ${org.name} 합류를 신청했습니다`,
          { type: 'JOIN_REQUEST', requestId: request.id },
        );
      }

      await prisma.notification.create({
        data: {
          userId: owner.userId,
          organizationId: org.id,
          type: 'JOIN_REQUEST',
          title: '센터 합류 신청',
          body: `${requester?.name ?? '관리자'}님이 합류를 신청했습니다`,
          data: { requestId: request.id },
        },
      });
    }

    res.status(201).json({
      id: request.id,
      organizationId: org.id,
      organizationName: org.name,
      status: request.status,
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Join request error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── My Pending Join Requests (must be before /:orgId routes) ──
router.get('/my-requests', authMiddleware, async (req: Request, res: Response) => {
  try {
    const requests = await prisma.centerJoinRequest.findMany({
      where: { userId: req.user!.userId, status: 'PENDING' },
      include: {
        organization: { select: { id: true, name: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json({
      requests: requests.map((r) => ({
        id: r.id,
        organizationId: r.organization.id,
        organizationName: r.organization.name,
        status: r.status,
        message: r.message,
        createdAt: r.createdAt.toISOString(),
      })),
    });
  } catch (err) {
    console.error('My requests error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── List Pending Join Requests (Owner only) ──────────────
router.get('/:orgId/join-requests', authMiddleware, async (req: Request, res: Response) => {
  try {
    const orgId = req.params.orgId as string;
    const userId = req.user!.userId;

    const membership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId, organizationId: orgId } },
    });
    if (!membership || membership.role !== 'OWNER') {
      res.status(403).json({ error: 'Only center owner can view join requests' });
      return;
    }

    const requests = await prisma.centerJoinRequest.findMany({
      where: { organizationId: orgId, status: 'PENDING' },
      include: {
        user: { select: { id: true, name: true, email: true, profileImage: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json({
      requests: requests.map((r) => ({
        id: r.id,
        userId: r.user.id,
        userName: r.user.name,
        userEmail: r.user.email,
        userProfileImage: r.user.profileImage,
        message: r.message,
        createdAt: r.createdAt.toISOString(),
      })),
    });
  } catch (err) {
    console.error('List join requests error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Approve/Reject Join Request (Owner only) ─────────────
const reviewRequestSchema = z.object({
  action: z.enum(['APPROVE', 'REJECT']),
  role: z.enum(['MANAGER', 'STAFF', 'VIEWER']).optional(),
});

router.put('/:orgId/join-requests/:requestId', authMiddleware, async (req: Request, res: Response) => {
  try {
    const orgId = req.params.orgId as string;
    const requestId = req.params.requestId as string;
    const userId = req.user!.userId;
    const body = reviewRequestSchema.parse(req.body);

    const membership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId, organizationId: orgId } },
    });
    if (!membership || membership.role !== 'OWNER') {
      res.status(403).json({ error: 'Only center owner can review join requests' });
      return;
    }

    const request = await prisma.centerJoinRequest.findFirst({
      where: { id: requestId, organizationId: orgId, status: 'PENDING' },
    });
    if (!request) {
      res.status(404).json({ error: 'Join request not found' });
      return;
    }

    if (body.action === 'APPROVE') {
      const withinLimit = await checkAdminLimit(orgId);
      if (!withinLimit) {
        res.status(409).json({ error: 'Center has reached maximum admin count' });
        return;
      }

      await prisma.$transaction(async (tx) => {
        await tx.centerJoinRequest.update({
          where: { id: requestId },
          data: { status: 'APPROVED', reviewedBy: userId, reviewedAt: new Date() },
        });

        await tx.orgMembership.upsert({
          where: {
            userId_organizationId: {
              userId: request.userId,
              organizationId: orgId,
            },
          },
          create: {
            userId: request.userId,
            organizationId: orgId,
            role: body.role ?? 'STAFF',
          },
          update: {},
        });
      });

      // Notify requester
      const requester = await prisma.user.findUnique({
        where: { id: request.userId },
        select: { fcmToken: true, notificationPreferences: true },
      });
      const org = await prisma.organization.findUnique({
        where: { id: orgId },
        select: { name: true },
      });

      if (
        requester?.fcmToken &&
        shouldSendPushForType(requester.notificationPreferences, 'JOIN_REQUEST_APPROVED')
      ) {
        sendPush(
          requester.fcmToken,
          '합류 승인',
          `${org?.name ?? '센터'}에 합류가 승인되었습니다`,
          { type: 'JOIN_REQUEST_APPROVED', organizationId: orgId },
        );
      }

      await prisma.notification.create({
        data: {
          userId: request.userId,
          organizationId: orgId,
          type: 'JOIN_REQUEST_APPROVED',
          title: '합류 승인',
          body: `${org?.name ?? '센터'}에 합류가 승인되었습니다`,
          data: { organizationId: orgId },
        },
      });
    } else {
      await prisma.centerJoinRequest.update({
        where: { id: requestId },
        data: { status: 'REJECTED', reviewedBy: userId, reviewedAt: new Date() },
      });

      // Notify requester
      const requester = await prisma.user.findUnique({
        where: { id: request.userId },
        select: { fcmToken: true, notificationPreferences: true },
      });
      const org = await prisma.organization.findUnique({
        where: { id: orgId },
        select: { name: true },
      });

      if (
        requester?.fcmToken &&
        shouldSendPushForType(requester.notificationPreferences, 'JOIN_REQUEST_REJECTED')
      ) {
        sendPush(
          requester.fcmToken,
          '합류 거절',
          `${org?.name ?? '센터'} 합류 신청이 거절되었습니다`,
          { type: 'JOIN_REQUEST_REJECTED', organizationId: orgId },
        );
      }

      await prisma.notification.create({
        data: {
          userId: request.userId,
          organizationId: orgId,
          type: 'JOIN_REQUEST_REJECTED',
          title: '합류 거절',
          body: `${org?.name ?? '센터'} 합류 신청이 거절되었습니다`,
          data: { organizationId: orgId },
        },
      });
    }

    res.json({ message: body.action === 'APPROVE' ? 'Approved' : 'Rejected' });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Review join request error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── List Center Members (Owner/Manager only) ────────────
router.get('/:orgId/members', authMiddleware, async (req: Request, res: Response) => {
  try {
    const orgId = req.params.orgId as string;
    const userId = req.user!.userId;

    const membership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId, organizationId: orgId } },
    });
    if (!membership || !['OWNER', 'MANAGER'].includes(membership.role)) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

    const members = await prisma.orgMembership.findMany({
      where: { organizationId: orgId },
      include: {
        user: { select: { id: true, name: true, email: true, profileImage: true } },
      },
      orderBy: { createdAt: 'asc' },
    });

    res.json({
      members: members.map((m) => ({
        userId: m.user.id,
        name: m.user.name,
        email: m.user.email,
        profileImage: m.user.profileImage,
        role: m.role,
        joinedAt: m.createdAt.toISOString(),
      })),
    });
  } catch (err) {
    console.error('List center members error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Change Member Role (Owner only) ─────────────────────
const changeRoleSchema = z.object({
  role: z.enum(['MANAGER', 'STAFF', 'VIEWER']),
});

router.put('/:orgId/members/:targetUserId/role', authMiddleware, async (req: Request, res: Response) => {
  try {
    const orgId = req.params.orgId as string;
    const targetUserId = req.params.targetUserId as string;
    const userId = req.user!.userId;
    const body = changeRoleSchema.parse(req.body);

    const membership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId, organizationId: orgId } },
    });
    if (!membership || membership.role !== 'OWNER') {
      res.status(403).json({ error: 'Only center owner can change roles' });
      return;
    }

    if (targetUserId === userId) {
      res.status(400).json({ error: 'Cannot change your own role' });
      return;
    }

    const targetMembership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId: targetUserId, organizationId: orgId } },
    });
    if (!targetMembership) {
      res.status(404).json({ error: 'Member not found in this center' });
      return;
    }

    await prisma.orgMembership.update({
      where: { id: targetMembership.id },
      data: { role: body.role },
    });

    res.json({ message: 'Role updated' });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Change role error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Remove Member from Center (Owner only) ──────────────
router.delete('/:orgId/members/:targetUserId', authMiddleware, async (req: Request, res: Response) => {
  try {
    const orgId = req.params.orgId as string;
    const targetUserId = req.params.targetUserId as string;
    const userId = req.user!.userId;

    const membership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId, organizationId: orgId } },
    });
    if (!membership || membership.role !== 'OWNER') {
      res.status(403).json({ error: 'Only center owner can remove members' });
      return;
    }

    if (targetUserId === userId) {
      res.status(400).json({ error: 'Cannot remove yourself' });
      return;
    }

    const targetMembership = await prisma.orgMembership.findUnique({
      where: { userId_organizationId: { userId: targetUserId, organizationId: orgId } },
    });
    if (!targetMembership) {
      res.status(404).json({ error: 'Member not found in this center' });
      return;
    }

    await prisma.orgMembership.delete({ where: { id: targetMembership.id } });

    // Notify removed user
    const removedUser = await prisma.user.findUnique({
      where: { id: targetUserId },
      select: { fcmToken: true, notificationPreferences: true },
    });
    const org = await prisma.organization.findUnique({
      where: { id: orgId },
      select: { name: true },
    });

    if (
      removedUser?.fcmToken &&
      shouldSendPushForType(removedUser.notificationPreferences, 'REMOVED_FROM_CENTER')
    ) {
      sendPush(
        removedUser.fcmToken,
        '센터 제외',
        `${org?.name ?? '센터'}에서 제외되었습니다`,
        { type: 'REMOVED_FROM_CENTER', organizationId: orgId },
      );
    }

    await prisma.notification.create({
      data: {
        userId: targetUserId,
        organizationId: orgId,
        type: 'REMOVED_FROM_CENTER',
        title: '센터 제외',
        body: `${org?.name ?? '센터'}에서 제외되었습니다`,
        data: { organizationId: orgId },
      },
    });

    res.json({ message: 'Member removed' });
  } catch (err) {
    console.error('Remove member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
