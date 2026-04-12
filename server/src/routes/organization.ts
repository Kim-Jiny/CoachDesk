import { randomUUID } from 'crypto';
import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { getCurrentMembership } from '../utils/org-access';
import { uploadFile } from '../utils/storage';

const router = Router();
router.use(authMiddleware);

const updateOrgSchema = z.object({
  name: z.string().min(1).optional(),
  description: z.string().nullable().optional(),
  bookingMode: z.enum(['PRIVATE', 'PUBLIC']).optional(),
  reservationPolicy: z.enum(['AUTO_CONFIRM', 'REQUEST_APPROVAL']).optional(),
  reservationNoticeText: z.string().max(5000).nullable().optional(),
  reservationNoticeImageUrl: z.string().url().nullable().optional(),
  reservationOpenDaysBefore: z.number().int().min(0).max(365).optional(),
  reservationOpenHoursBefore: z.number().int().min(0).max(23).optional(),
  reservationCancelDeadlineMinutes: z.number().int().min(0).max(7 * 24 * 60).optional(),
});

const uploadReservationNoticeImageSchema = z.object({
  fileName: z.string().min(1).max(255),
  contentType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  base64Data: z.string().min(1),
});

async function requireOrganizationEditor(userId: string, organizationId: string) {
  const membership = await prisma.orgMembership.findUnique({
    where: { userId_organizationId: { userId, organizationId } },
  });

  if (!membership || membership.role !== 'OWNER') {
    return null;
  }

  return membership;
}

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

router.put('/:id', async (req: Request, res: Response) => {
  try {
    const body = updateOrgSchema.parse(req.body);
    const organizationId = req.params.id as string;
    const membership = await requireOrganizationEditor(req.user!.userId, organizationId);

    if (!membership) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

    const org = await prisma.organization.update({
      where: { id: organizationId },
      data: {
        ...body,
        reservationNoticeText: body.reservationNoticeText?.trim() ?? body.reservationNoticeText ?? undefined,
      },
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

router.post('/:id/reservation-notice-image', async (req: Request, res: Response) => {
  try {
    const organizationId = req.params.id as string;
    const membership = await requireOrganizationEditor(req.user!.userId, organizationId);
    if (!membership) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

    const body = uploadReservationNoticeImageSchema.parse(req.body);
    const buffer = Buffer.from(body.base64Data, 'base64');
    if (buffer.length === 0) {
      res.status(400).json({ error: 'Image data required' });
      return;
    }

    if (buffer.length > 8 * 1024 * 1024) {
      res.status(400).json({ error: '이미지는 8MB 이하만 업로드할 수 있습니다' });
      return;
    }

    const safeFileName = body.fileName.replace(/[^a-zA-Z0-9._-]/g, '_');
    const extension = safeFileName.includes('.') ? safeFileName.split('.').pop() : 'jpg';
    const objectName = `organizations/${organizationId}/reservation-notices/${randomUUID()}.${extension}`;
    const imageUrl = await uploadFile(objectName, buffer, body.contentType);

    await prisma.organization.update({
      where: { id: organizationId },
      data: { reservationNoticeImageUrl: imageUrl },
    });

    res.json({ imageUrl });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Upload reservation notice image error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Join Organization by Invite Code (deprecated: use POST /centers/join-request) ──
router.post('/join', async (req: Request, res: Response) => {
  res.status(410).json({
    error: 'This endpoint is deprecated. Use POST /api/centers/join-request instead.',
  });
});

export default router;
