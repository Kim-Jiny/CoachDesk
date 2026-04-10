import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { getCurrentOrgId, isUserInOrganization } from '../utils/org-access';
import { formatDateOnly, parseDateOnly } from '../utils/kst-date';
import { findSchedulesCompat, findScheduleOverridesCompat } from '../utils/schedule-access';
import { timeToMinutes } from '../utils/slot-blocking';
import { getAvailableSlots } from '../utils/slot-service';

const router = Router();
router.use(authMiddleware);

// ─── List Schedules ────────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const coachId = req.query.coachId as string | undefined;

    const schedules = await findSchedulesCompat({
      organizationId: orgId,
      coachId,
    });

    res.json(schedules);
  } catch (err) {
    console.error('List schedules error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Create Schedule ───────────────────────────────────────
const createScheduleSchema = z.object({
  dayOfWeek: z.number().min(0).max(6).optional(),
  dayOfWeeks: z.array(z.number().min(0).max(6)).min(1).optional(),
  startTime: z.string().regex(/^\d{2}:\d{2}$/),
  endTime: z.string().regex(/^\d{2}:\d{2}$/),
  slotDuration: z.number().min(15).default(60),
  breakMinutes: z.number().min(0).max(180).default(0),
  maxCapacity: z.number().min(1).default(1),
  isPublic: z.boolean().default(false),
});

router.post('/', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = createScheduleSchema.parse(req.body);
    const dayOfWeeks = body.dayOfWeeks ?? (body.dayOfWeek != null ? [body.dayOfWeek] : []);

    if (dayOfWeeks.length == 0) {
      res.status(400).json({ error: '요일을 하나 이상 선택해주세요' });
      return;
    }

    if (timeToMinutes(body.startTime) >= timeToMinutes(body.endTime)) {
      res.status(400).json({ error: '시작시간이 종료시간보다 빨라야 합니다' });
      return;
    }

    const uniqueDayOfWeeks = [...new Set(dayOfWeeks)];
    const schedules = await prisma.$transaction(
      uniqueDayOfWeeks.map((dayOfWeek) => prisma.schedule.create({
        data: {
          organizationId: orgId,
          coachId: req.user!.userId,
          dayOfWeek,
          startTime: body.startTime,
          endTime: body.endTime,
          slotDuration: body.slotDuration,
          breakMinutes: body.breakMinutes,
          maxCapacity: body.maxCapacity,
          isPublic: body.isPublic,
        },
      })),
    );

    res.status(201).json(
      schedules.length === 1
          ? schedules[0]
          : {
              created: schedules.length,
              schedules,
            },
    );
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Create schedule error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const updateScheduleSchema = z.object({
  dayOfWeek: z.number().min(0).max(6).optional(),
  startTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  endTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  slotDuration: z.number().min(15).optional(),
  breakMinutes: z.number().min(0).max(180).optional(),
  maxCapacity: z.number().min(1).optional(),
  isPublic: z.boolean().optional(),
});

// ─── Update Schedule ───────────────────────────────────────
router.put('/:id', async (req: Request, res: Response) => {
  try {
    const id = req.params.id as string;
    const schedule = await prisma.schedule.findUnique({ where: { id } });
    if (!schedule || schedule.coachId !== req.user!.userId) {
      res.status(404).json({ error: 'Schedule not found' });
      return;
    }

    const body = updateScheduleSchema.parse(req.body);

    // Validate time order if both are present, or if one is present with existing
    const startTime = body.startTime ?? schedule.startTime;
    const endTime = body.endTime ?? schedule.endTime;
    if (timeToMinutes(startTime) >= timeToMinutes(endTime)) {
      res.status(400).json({ error: '시작시간이 종료시간보다 빨라야 합니다' });
      return;
    }

    const updated = await prisma.schedule.update({
      where: { id },
      data: body,
    });

    res.json(updated);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update schedule error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Delete Schedule ───────────────────────────────────────
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const id = req.params.id as string;
    const schedule = await prisma.schedule.findUnique({ where: { id } });
    if (!schedule || schedule.coachId !== req.user!.userId) {
      res.status(404).json({ error: 'Schedule not found' });
      return;
    }

    await prisma.schedule.delete({ where: { id } });
    res.json({ message: 'Schedule deleted' });
  } catch (err) {
    console.error('Delete schedule error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Schedule Override CRUD ────────────────────────────────

const createOverrideSchema = z.object({
  coachId: z.string().uuid().optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  type: z.enum(['OPEN', 'CLOSED', 'VISIBLE', 'HIDDEN']),
  startTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  endTime: z.string().regex(/^\d{2}:\d{2}$/).optional(),
  slotDuration: z.number().min(15).optional(),
  breakMinutes: z.number().min(0).max(180).optional(),
  maxCapacity: z.number().min(1).optional(),
  isPublic: z.boolean().optional(),
});

router.post('/overrides', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const body = createOverrideSchema.parse(req.body);
    const coachId = body.coachId || req.user!.userId;

    const coachInOrg = await isUserInOrganization(coachId, orgId);
    if (!coachInOrg) {
      res.status(403).json({ error: 'Coach is not part of this organization' });
      return;
    }

    if ((body.type === 'OPEN' || body.type === 'VISIBLE' || body.type === 'HIDDEN') &&
        (!body.startTime || !body.endTime)) {
      res.status(400).json({ error: '선택한 오버라이드는 시작시간과 종료시간이 필요합니다' });
      return;
    }

    if (body.startTime && body.endTime && timeToMinutes(body.startTime) >= timeToMinutes(body.endTime)) {
      res.status(400).json({ error: '시작시간이 종료시간보다 빨라야 합니다' });
      return;
    }

    const override = await prisma.scheduleOverride.create({
      data: {
        organizationId: orgId,
        coachId,
        date: parseDateOnly(body.date),
        type: body.type,
        startTime: body.startTime,
        endTime: body.endTime,
        slotDuration: body.slotDuration,
        breakMinutes: body.breakMinutes,
        maxCapacity: body.maxCapacity,
        isPublic: body.type === 'OPEN'
            ? (body.isPublic ?? false)
            : body.type === 'VISIBLE'
            ? true
            : body.type === 'HIDDEN'
            ? false
            : body.isPublic,
      },
    });

    res.status(201).json(override);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Create override error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/overrides', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const startDate = req.query.startDate as string | undefined;
    const endDate = req.query.endDate as string | undefined;
    const coachId = req.query.coachId as string | undefined;

    const overrides = await findScheduleOverridesCompat({
      organizationId: orgId,
      coachId,
      startDate: startDate ? parseDateOnly(startDate) : undefined,
      endDate: endDate ? parseDateOnly(endDate) : undefined,
      includeCoach: true,
    });

    res.json(overrides.map((override) => ({
      ...override,
      date: formatDateOnly(override.date),
      breakMinutes: (override as any).breakMinutes,
      isPublic: (override as any).isPublic,
    })));
  } catch (err) {
    console.error('List overrides error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/overrides/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const id = req.params.id as string;
    const override = await prisma.scheduleOverride.findUnique({ where: { id } });
    if (!override || override.organizationId !== orgId) {
      res.status(404).json({ error: 'Override not found' });
      return;
    }

    await prisma.scheduleOverride.delete({ where: { id } });
    res.json({ message: 'Override deleted' });
  } catch (err) {
    console.error('Delete override error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Get Available Slots (with Override support) ──────────
router.get('/slots', async (req: Request, res: Response) => {
  try {
    const orgId = await getCurrentOrgId(req.user!.userId, req.header('x-organization-id') ?? undefined);
    if (!orgId) { res.status(403).json({ error: 'No organization' }); return; }

    const date = req.query.date as string | undefined;
    const slotCoachId = req.query.coachId as string | undefined;
    const includePast = req.query.includePast === 'true';
    if (!date) { res.status(400).json({ error: 'date query parameter required' }); return; }

    const slots = await getAvailableSlots({
      organizationId: orgId,
      date,
      coachId: slotCoachId,
      includePast,
      includeCoachNames: true,
    });
    res.json(slots);
  } catch (err) {
    console.error('Get slots error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
