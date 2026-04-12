import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { parseDateOnly } from '../utils/kst-date';
import { requireCurrentOrgId, respondValidationError } from './_shared';

const router = Router();
router.use(authMiddleware);

// ─── List Sessions ─────────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const memberId = req.query.memberId as string | undefined;
    const startDate = req.query.startDate as string | undefined;
    const endDate = req.query.endDate as string | undefined;

    const where: any = { organizationId: orgId };
    if (memberId) where.memberId = memberId;
    if (startDate && endDate) {
      where.date = { gte: parseDateOnly(startDate), lte: parseDateOnly(endDate) };
    }

    const sessions = await prisma.session.findMany({
      where,
      include: {
        member: { select: { id: true, name: true } },
        coach: { select: { id: true, name: true } },
        reservation: { select: { startTime: true, endTime: true } },
      },
      orderBy: { date: 'desc' },
    });

    res.json(sessions);
  } catch (err) {
    console.error('List sessions error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Get Session ───────────────────────────────────────────
router.get('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const session = await prisma.session.findFirst({
      where: { id: req.params.id as string, organizationId: orgId },
      include: {
        member: { select: { id: true, name: true } },
        coach: { select: { id: true, name: true } },
        reservation: true,
        memberPackage: { include: { package: true } },
      },
    });

    if (!session) { res.status(404).json({ error: 'Session not found' }); return; }
    res.json(session);
  } catch (err) {
    console.error('Get session error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Update Session ────────────────────────────────────────
const updateSessionSchema = z.object({
  memo: z.string().optional(),
  workoutRecords: z.any().optional(),
  feedback: z.string().optional(),
  attendance: z.enum(['PRESENT', 'NO_SHOW', 'LATE', 'CANCELLED']).optional(),
});

router.put('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const body = updateSessionSchema.parse(req.body);

    const existingSession = await prisma.session.findFirst({
      where: { id: req.params.id as string, organizationId: orgId },
      select: { id: true },
    });
    if (!existingSession) {
      res.status(404).json({ error: 'Session not found' });
      return;
    }

    const session = await prisma.session.update({
      where: { id: existingSession.id },
      data: body,
    });

    res.json(session);
  } catch (err) {
    if (respondValidationError(res, err)) return;
    console.error('Update session error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
