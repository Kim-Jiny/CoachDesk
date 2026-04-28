import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { isUserInOrganization } from '../utils/org-access';
import { formatDateOnly, parseDateOnly } from '../utils/kst-date';
import { findSchedulesCompat, findScheduleOverridesCompat } from '../utils/schedule-access';
import { timeToMinutes } from '../utils/slot-blocking';
import { getAvailableSlots } from '../utils/slot-service';
import { isOverlappingTimeRange } from '../features/shared/time-range';
import { decodeMemoFields, encodeMemoFields } from '../utils/memo-fields';
import { emitReservationUpdated } from '../socket/emitters';
import { handleReservationDelayedNotification } from '../features/reservation/notifications';
import { serializeReservation } from '../features/reservation/serializer';
import { requireCurrentOrgId, requireOrgRole, respondValidationError } from './_shared';

const router = Router();
router.use(authMiddleware);

// ─── List Schedules ────────────────────────────────────────
router.get('/', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    if (!(await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']))) return;

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
    if (respondValidationError(res, err)) return;
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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const id = req.params.id as string;
    const schedule = await prisma.schedule.findUnique({ where: { id } });
    if (!schedule || schedule.organizationId !== orgId) {
      res.status(404).json({ error: 'Schedule not found' });
      return;
    }
    if (role === 'STAFF' && schedule.coachId !== req.user!.userId) {
      res.status(403).json({ error: 'Insufficient permissions' });
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
    if (respondValidationError(res, err)) return;
    console.error('Update schedule error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Delete Schedule ───────────────────────────────────────
router.delete('/:id', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const id = req.params.id as string;
    const schedule = await prisma.schedule.findUnique({ where: { id } });
    if (!schedule || schedule.organizationId !== orgId) {
      res.status(404).json({ error: 'Schedule not found' });
      return;
    }
    if (role === 'STAFF' && schedule.coachId !== req.user!.userId) {
      res.status(403).json({ error: 'Insufficient permissions' });
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

const moveSlotSchema = z.object({
  coachId: z.string().uuid().optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  currentStartTime: z.string().regex(/^\d{2}:\d{2}$/),
  currentEndTime: z.string().regex(/^\d{2}:\d{2}$/),
  newStartTime: z.string().regex(/^\d{2}:\d{2}$/),
  newEndTime: z.string().regex(/^\d{2}:\d{2}$/),
  slotDuration: z.number().min(1),
  maxCapacity: z.number().min(1).default(1),
  isPublic: z.boolean().default(false),
});

const shiftDayScheduleSchema = z.object({
  coachId: z.string().uuid().optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  fromStartTime: z.string().regex(/^\d{2}:\d{2}$/),
  deltaMinutes: z
    .number()
    .int()
    .min(-180)
    .max(180)
    .refine((value) => value !== 0, { message: 'deltaMinutes must not be zero' }),
});

const closeSlotSchema = z.object({
  coachId: z.string().uuid().optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  startTime: z.string().regex(/^\d{2}:\d{2}$/),
  endTime: z.string().regex(/^\d{2}:\d{2}$/),
});

function overlapsTimeRange(
  leftStart?: string | null,
  leftEnd?: string | null,
  rightStart?: string | null,
  rightEnd?: string | null,
) {
  if (!leftStart || !leftEnd || !rightStart || !rightEnd) return false;
  return timeToMinutes(leftStart) < timeToMinutes(rightEnd) &&
    timeToMinutes(rightStart) < timeToMinutes(leftEnd);
}

type SlotSnapshot = Awaited<ReturnType<typeof getAvailableSlots>>[number];

type SlotShiftPlan = {
  original: SlotSnapshot;
  newStartTime: string;
  newEndTime: string;
};

function shiftTimeWithinDay(time: string, deltaMinutes: number): string | null {
  const shifted = timeToMinutes(time) + deltaMinutes;
  if (shifted < 0 || shifted >= 24 * 60) {
    return null;
  }

  return `${String(Math.floor(shifted / 60)).padStart(2, '0')}:${String(shifted % 60).padStart(2, '0')}`;
}

function getSlotKey(slot: { startTime: string; endTime: string }) {
  return `${slot.startTime}-${slot.endTime}`;
}

async function runScheduleSideEffect(
  label: string,
  task: () => Promise<void>,
) {
  try {
    await task();
  } catch (err) {
    console.error(`${label} failed:`, err);
  }
}

function validateShiftAgainstUnmovedRanges(params: {
  shiftedPlans: Array<{ startTime: string; endTime: string }>;
  unchangedRanges: Array<{ startTime: string; endTime: string }>;
}) {
  return params.shiftedPlans.some((plan) =>
    params.unchangedRanges.some((range) =>
      isOverlappingTimeRange(
        plan.startTime,
        plan.endTime,
        range.startTime,
        range.endTime,
      ),
    ),
  );
}

async function applySlotShiftPlans(params: {
  organizationId: string;
  coachId: string;
  date: string;
  plans: SlotShiftPlan[];
  tx: any;
}) {
  const { organizationId, coachId, date, plans, tx } = params;
  if (plans.length === 0) {
    return { movedSlotCount: 0 };
  }

  const dateOnly = parseDateOnly(date);
  const movedOriginalKeys = new Set(plans.map((plan) => getSlotKey(plan.original)));
  const plansByOverrideId = new Map<string, SlotShiftPlan[]>();
  const openOverrideIds = new Set<string>();

  for (const plan of plans) {
    const sourceOverrideId = plan.original.sourceOverrideId;
    if (!sourceOverrideId) continue;
    openOverrideIds.add(sourceOverrideId);
    const existing = plansByOverrideId.get(sourceOverrideId) ?? [];
    existing.push(plan);
    plansByOverrideId.set(sourceOverrideId, existing);
  }

  const currentSlots = await getAvailableSlots({
    organizationId,
    date,
    coachId,
    includePast: true,
  });

  if (openOverrideIds.size > 0) {
    await tx.scheduleOverride.deleteMany({
      where: {
        organizationId,
        coachId,
        date: dateOnly,
        id: { in: [...openOverrideIds] },
      },
    });
  }

  const openOverridesToCreate: Array<{
    startTime: string;
    endTime: string;
    slotDuration: number;
    maxCapacity: number;
    isPublic: boolean;
  }> = [];

  for (const plan of plans) {
    if (plan.original.sourceType !== 'OPEN_OVERRIDE') {
      await tx.scheduleOverride.create({
        data: {
          organizationId,
          coachId,
          date: dateOnly,
          type: 'CLOSED',
          startTime: plan.original.startTime,
          endTime: plan.original.endTime,
        },
      });
    }

    openOverridesToCreate.push({
      startTime: plan.newStartTime,
      endTime: plan.newEndTime,
      slotDuration:
        timeToMinutes(plan.original.endTime) - timeToMinutes(plan.original.startTime),
      maxCapacity: plan.original.maxCapacity ?? 1,
      isPublic: plan.original.isPublic ?? false,
    });
  }

  for (const [overrideId] of plansByOverrideId.entries()) {
    const remainingSlots = currentSlots
      .filter((slot) => slot.sourceOverrideId == overrideId)
      .filter((slot) => !movedOriginalKeys.has(getSlotKey(slot)));

    for (const slot of remainingSlots) {
      openOverridesToCreate.push({
        startTime: slot.startTime,
        endTime: slot.endTime,
        slotDuration: timeToMinutes(slot.endTime) - timeToMinutes(slot.startTime),
        maxCapacity: slot.maxCapacity ?? 1,
        isPublic: slot.isPublic ?? false,
      });
    }
  }

  for (const override of openOverridesToCreate) {
    await tx.scheduleOverride.create({
      data: {
        organizationId,
        coachId,
        date: dateOnly,
        type: 'OPEN',
        startTime: override.startTime,
        endTime: override.endTime,
        slotDuration: override.slotDuration,
        breakMinutes: 0,
        maxCapacity: override.maxCapacity,
        isPublic: override.isPublic,
      },
    });
  }

  return { movedSlotCount: plans.length };
}

async function closeSlotWithSourceAwareness(params: {
  organizationId: string;
  coachId: string;
  date: string;
  startTime: string;
  endTime: string;
  tx: any;
}) {
  const { organizationId, coachId, date, startTime, endTime, tx } = params;
  const dateOnly = parseDateOnly(date);
  const currentSlots = await getAvailableSlots({
    organizationId,
    date,
    coachId,
    includePast: true,
  });
  const targetSlot = currentSlots.find(
    (slot) => slot.startTime === startTime && slot.endTime === endTime,
  );

  if (!targetSlot) {
    return false;
  }

  await tx.scheduleOverride.create({
    data: {
      organizationId,
      coachId,
      date: dateOnly,
      type: 'CLOSED',
      startTime,
      endTime,
    },
  });

  if (
    targetSlot.sourceType === 'OPEN_OVERRIDE' &&
    targetSlot.sourceOverrideId != null
  ) {
    const sourceOverrideId = targetSlot.sourceOverrideId;
    const siblingSlots = currentSlots.filter(
      (slot) =>
        slot.sourceOverrideId === sourceOverrideId &&
        !(slot.startTime === startTime && slot.endTime === endTime),
    );

    await tx.scheduleOverride.delete({
      where: { id: sourceOverrideId },
    });

    for (const slot of siblingSlots) {
      await tx.scheduleOverride.create({
        data: {
          organizationId,
          coachId,
          date: dateOnly,
          type: 'OPEN',
          startTime: slot.startTime,
          endTime: slot.endTime,
          slotDuration:
            timeToMinutes(slot.endTime) - timeToMinutes(slot.startTime),
          breakMinutes: 0,
          maxCapacity: slot.maxCapacity ?? 1,
          isPublic: slot.isPublic ?? false,
        },
      });
    }
  }

  return true;
}

router.post('/overrides', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const body = createOverrideSchema.parse(req.body);
    const coachId = body.coachId || req.user!.userId;

    if (role === 'STAFF' && coachId !== req.user!.userId) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

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

    const targetDate = parseDateOnly(body.date);
    const createData = {
      organizationId: orgId,
      coachId,
      date: targetDate,
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
    };

    const override = body.type === 'OPEN'
      ? await prisma.$transaction(async (tx) => {
          const closedOverrides = await tx.scheduleOverride.findMany({
            where: {
              organizationId: orgId,
              coachId,
              date: targetDate,
              type: 'CLOSED',
            },
            select: { id: true, startTime: true, endTime: true },
          });
          const overlappingClosedIds = closedOverrides
            .filter((candidate) =>
              overlapsTimeRange(
                candidate.startTime,
                candidate.endTime,
                body.startTime,
                body.endTime,
              ),
            )
            .map((candidate) => candidate.id);

          if (overlappingClosedIds.length > 0) {
            await tx.scheduleOverride.deleteMany({
              where: { id: { in: overlappingClosedIds } },
            });
          }

          return tx.scheduleOverride.create({ data: createData });
        })
      : await prisma.scheduleOverride.create({ data: createData });

    res.status(201).json(override);
  } catch (err) {
    if (respondValidationError(res, err)) return;
    console.error('Create override error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/move-slot', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const body = moveSlotSchema.parse(req.body);
    const coachId = body.coachId || req.user!.userId;

    if (role === 'STAFF' && coachId !== req.user!.userId) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

    const coachInOrg = await isUserInOrganization(coachId, orgId);
    if (!coachInOrg) {
      res.status(403).json({ error: 'Coach is not part of this organization' });
      return;
    }

    if (timeToMinutes(body.currentStartTime) >= timeToMinutes(body.currentEndTime)) {
      res.status(400).json({ error: '기존 시간의 시작이 종료보다 빨라야 합니다' });
      return;
    }

    if (timeToMinutes(body.newStartTime) >= timeToMinutes(body.newEndTime)) {
      res.status(400).json({ error: '새 시간의 시작이 종료보다 빨라야 합니다' });
      return;
    }

    const currentSlots = await getAvailableSlots({
      organizationId: orgId,
      date: body.date,
      coachId,
      includePast: true,
    });
    const targetSlot = currentSlots.find(
      (slot) =>
        slot.startTime === body.currentStartTime &&
        slot.endTime === body.currentEndTime,
    );

    if (!targetSlot) {
      res.status(404).json({ error: '이동할 빈 타임을 찾지 못했습니다' });
      return;
    }

    const conflictsWithOtherSlots = currentSlots
      .filter(
        (slot) =>
          slot.startTime !== body.currentStartTime ||
          slot.endTime !== body.currentEndTime,
      )
      .some((slot) =>
        isOverlappingTimeRange(
          body.newStartTime,
          body.newEndTime,
          slot.startTime,
          slot.endTime,
        ),
      );

    if (conflictsWithOtherSlots) {
      res.status(409).json({ error: '조정한 시간이 다른 빈 타임과 겹칩니다' });
      return;
    }

    await prisma.$transaction(async (tx) => {
      await applySlotShiftPlans({
        organizationId: orgId,
        coachId,
        date: body.date,
        tx,
        plans: [
          {
            original: targetSlot,
            newStartTime: body.newStartTime,
            newEndTime: body.newEndTime,
          },
        ],
      });
    });

    res.status(201).json({ message: 'Slot moved' });
  } catch (err) {
    if (respondValidationError(res, err)) return;
    console.error('Move slot error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/close-slot', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const body = closeSlotSchema.parse(req.body);
    const coachId = body.coachId || req.user!.userId;

    if (role === 'STAFF' && coachId !== req.user!.userId) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

    const coachInOrg = await isUserInOrganization(coachId, orgId);
    if (!coachInOrg) {
      res.status(403).json({ error: 'Coach is not part of this organization' });
      return;
    }

    const closed = await prisma.$transaction(async (tx) =>
      closeSlotWithSourceAwareness({
        organizationId: orgId,
        coachId,
        date: body.date,
        startTime: body.startTime,
        endTime: body.endTime,
        tx,
      }),
    );

    if (!closed) {
      res.status(404).json({ error: '삭제할 타임을 찾지 못했습니다' });
      return;
    }

    res.status(201).json({ message: 'Slot closed' });
  } catch (err) {
    if (respondValidationError(res, err)) return;
    console.error('Close slot error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/shift-day', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

    const body = shiftDayScheduleSchema.parse(req.body);
    const coachId = body.coachId || req.user!.userId;

    if (role === 'STAFF' && coachId !== req.user!.userId) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

    const coachInOrg = await isUserInOrganization(coachId, orgId);
    if (!coachInOrg) {
      res.status(403).json({ error: 'Coach is not part of this organization' });
      return;
    }

    const currentSlots = await getAvailableSlots({
      organizationId: orgId,
      date: body.date,
      coachId,
      includePast: true,
    });
    const reservations = await prisma.reservation.findMany({
      where: {
        organizationId: orgId,
        coachId,
        date: parseDateOnly(body.date),
        status: { in: ['PENDING', 'CONFIRMED'] },
      },
      include: {
        member: { select: { memberAccountId: true } },
      },
      orderBy: { startTime: 'asc' },
    });

    const affectedSlots = currentSlots.filter(
      (slot) => slot.startTime >= body.fromStartTime,
    );
    const affectedReservations = reservations.filter(
      (reservation) => reservation.startTime >= body.fromStartTime,
    );

    if (affectedSlots.length === 0 && affectedReservations.length === 0) {
      res.status(404).json({ error: '조정할 이후 일정이 없습니다' });
      return;
    }

    const slotPlans: SlotShiftPlan[] = [];
    for (const slot of affectedSlots) {
      const newStartTime = shiftTimeWithinDay(slot.startTime, body.deltaMinutes);
      const newEndTime = shiftTimeWithinDay(slot.endTime, body.deltaMinutes);
      if (!newStartTime || !newEndTime) {
        res.status(409).json({ error: '조정한 시간이 하루 범위를 벗어납니다' });
        return;
      }
      slotPlans.push({
        original: slot,
        newStartTime,
        newEndTime,
      });
    }

    const shiftedReservations = affectedReservations.map((reservation) => {
      const newStartTime = shiftTimeWithinDay(
        reservation.startTime,
        body.deltaMinutes,
      );
      const newEndTime = shiftTimeWithinDay(
        reservation.endTime,
        body.deltaMinutes,
      );
      return {
        reservation,
        newStartTime,
        newEndTime,
      };
    });

    if (
      shiftedReservations.some(
        (item) => !item.newStartTime || !item.newEndTime,
      )
    ) {
      res.status(409).json({ error: '조정한 시간이 하루 범위를 벗어납니다' });
      return;
    }

    const unchangedRanges = [
      ...currentSlots
        .filter((slot) => slot.startTime < body.fromStartTime)
        .map((slot) => ({ startTime: slot.startTime, endTime: slot.endTime })),
      ...reservations
        .filter((reservation) => reservation.startTime < body.fromStartTime)
        .map((reservation) => ({
          startTime: reservation.startTime,
          endTime: reservation.endTime,
        })),
    ];

    const hasConflicts =
      validateShiftAgainstUnmovedRanges({
        shiftedPlans: slotPlans.map((plan) => ({
          startTime: plan.newStartTime,
          endTime: plan.newEndTime,
        })),
        unchangedRanges,
      }) ||
      validateShiftAgainstUnmovedRanges({
        shiftedPlans: shiftedReservations.map((item) => ({
          startTime: item.newStartTime!,
          endTime: item.newEndTime!,
        })),
        unchangedRanges,
      });

    if (hasConflicts) {
      res.status(409).json({ error: '앞 일정과 겹쳐서 전체 조정할 수 없습니다' });
      return;
    }

    const updatedReservations = await prisma.$transaction(async (tx) => {
      await applySlotShiftPlans({
        organizationId: orgId,
        coachId,
        date: body.date,
        plans: slotPlans,
        tx,
      });

      const results = [];
      for (const item of shiftedReservations) {
        const memoFields = decodeMemoFields(item.reservation.memo);
        const updated = await tx.reservation.update({
          where: { id: item.reservation.id },
          data: {
            startTime: item.newStartTime!,
            endTime: item.newEndTime!,
            memo: encodeMemoFields({
              quickMemo: memoFields.quickMemo,
              memo: memoFields.memo,
              delayMinutes: (memoFields.delayMinutes ?? 0) + body.deltaMinutes,
              originalStartTime:
                memoFields.originalStartTime ?? item.reservation.startTime,
              originalEndTime:
                memoFields.originalEndTime ?? item.reservation.endTime,
            }),
          },
          include: {
            member: {
              select: {
                id: true,
                name: true,
                phone: true,
                memberAccountId: true,
                memo: true,
              },
            },
            coach: { select: { id: true, name: true } },
          },
        });
        results.push(updated);
      }

      return results;
    });

    for (let index = 0; index < updatedReservations.length; index += 1) {
      const updated = updatedReservations[index];
      const existing = affectedReservations[index];
      emitReservationUpdated(
        orgId,
        serializeReservation(updated),
        existing.member.memberAccountId,
      );
      await runScheduleSideEffect('Reservation delayed notification', () =>
        handleReservationDelayedNotification({
          memberAccountId: existing.member.memberAccountId,
          organizationId: orgId,
          reservationId: updated.id,
          date: body.date,
          delayMinutes: body.deltaMinutes,
          newStartTime: updated.startTime,
        }),
      );
    }

    res.json({
      movedReservations: updatedReservations.length,
      movedSlots: slotPlans.length,
    });
  } catch (err) {
    if (respondValidationError(res, err)) return;
    console.error('Shift day schedule error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/overrides', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;
    const role = await requireOrgRole(req, res, orgId, ['OWNER', 'MANAGER', 'STAFF']);
    if (!role) return;

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
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

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
