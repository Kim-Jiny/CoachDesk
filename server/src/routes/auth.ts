import { Router, Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { OAuth2Client } from 'google-auth-library';
import { prisma } from '../utils/prisma';
import { generateAccessToken, generateRefreshToken, verifyRefreshToken } from '../utils/jwt';
import { authMiddleware } from '../middleware/auth';
import { sendPush } from '../utils/firebase';
import { env } from '../config/env';
import { pickPrimaryMembership } from '../utils/org-access';
import { verifyAppleIdentityToken } from '../utils/apple-auth';
import {
  formatDateOnly,
  getKstDayOfWeek,
  getKstToday,
  parseDateOnly,
} from '../utils/kst-date';
import { findFirstScheduleCompat, findFirstScheduleOverrideCompat, findScheduleOverridesCompat } from '../utils/schedule-access';
import { isTimeRangeClosed } from '../utils/slot-blocking';
import { findGeneratedSlot, getAvailableSlots } from '../utils/slot-service';
import { canCancelAt, canReserveAt } from '../utils/reservation-policy';
import { emitReservationCreated, emitReservationCancelled } from '../socket/emitters';
import { serializeReservation } from './reservation';
import {
  findMemberPackageCompat,
  listMemberPackagesCompat,
  updateMemberPackagePauseCompat,
} from '../utils/member-package-access';
import {
  parseNotificationPreferences,
  stringifyNotificationPreferences,
  shouldSendPushForType,
} from '../utils/notification-preferences';

function buildReservationStatusMessage(status: string, date: string, startTime: string) {
  if (status === 'PENDING') {
    return {
      title: '예약 신청',
      body: `회원이 ${date} ${startTime} 예약을 신청했습니다`,
    };
  }

  return {
    title: '새 예약',
    body: `회원이 ${date} ${startTime} 예약했습니다`,
  };
}

function calculatePauseDays(startDate: string, endDate: string) {
  const start = parseDateOnly(startDate);
  const end = parseDateOnly(endDate);
  const diffMs = end.getTime() - start.getTime();
  return Math.floor(diffMs / (24 * 60 * 60 * 1000)) + 1;
}

function isOverlappingTimeRange(
  leftStart: string,
  leftEnd: string,
  rightStart: string,
  rightEnd: string,
) {
  const leftStartMinutes =
    Number(leftStart.slice(0, 2)) * 60 + Number(leftStart.slice(3, 5));
  const leftEndMinutes =
    Number(leftEnd.slice(0, 2)) * 60 + Number(leftEnd.slice(3, 5));
  const rightStartMinutes =
    Number(rightStart.slice(0, 2)) * 60 + Number(rightStart.slice(3, 5));
  const rightEndMinutes =
    Number(rightEnd.slice(0, 2)) * 60 + Number(rightEnd.slice(3, 5));
  return leftStartMinutes < rightEndMinutes && leftEndMinutes > rightStartMinutes;
}

const router = Router();
const notificationPreferencesSchema = z.object({
  reservation: z.boolean(),
  chat: z.boolean(),
  package: z.boolean(),
  general: z.boolean(),
});

function toOrganizationPayload(user: {
  memberships: Array<{
    role: string;
    createdAt: Date;
    organization: { id: string; name: string; inviteCode: string };
  }>;
}) {
  const primaryMembership = pickPrimaryMembership(user.memberships);
  if (!primaryMembership) return null;

  return {
    id: primaryMembership.organization.id,
    name: primaryMembership.organization.name,
    inviteCode: primaryMembership.organization.inviteCode,
    role: primaryMembership.role,
  };
}

// ─── Register ──────────────────────────────────────────────
const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
  name: z.string().min(1),
  phone: z.string().optional(),
  organizationName: z.string().optional(),
});

router.post('/register', async (req: Request, res: Response) => {
  try {
    const body = registerSchema.parse(req.body);

    const existing = await prisma.user.findUnique({ where: { email: body.email } });
    if (existing) {
      res.status(409).json({ error: 'Email already registered' });
      return;
    }

    const hashedPassword = await bcrypt.hash(body.password, 12);
    const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();

    const result = await prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          email: body.email,
          password: hashedPassword,
          name: body.name,
          phone: body.phone,
        },
      });

      const org = await tx.organization.create({
        data: {
          name: body.organizationName || `${body.name}'s Studio`,
          inviteCode,
        },
      });

      await tx.orgMembership.create({
        data: {
          userId: user.id,
          organizationId: org.id,
          role: 'OWNER',
        },
      });

      return { user, org };
    });

    const tokenPayload = { userId: result.user.id, email: result.user.email };
    const accessToken = generateAccessToken(tokenPayload);
    const refreshToken = generateRefreshToken(tokenPayload);

    res.status(201).json({
      accessToken,
      refreshToken,
      user: {
        id: result.user.id,
        email: result.user.email,
        name: result.user.name,
        phone: result.user.phone,
        profileImage: result.user.profileImage,
      },
      organization: {
        id: result.org.id,
        name: result.org.name,
        inviteCode: result.org.inviteCode,
      },
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Register error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Login ─────────────────────────────────────────────────
const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

router.post('/login', async (req: Request, res: Response) => {
  try {
    const body = loginSchema.parse(req.body);

    const user = await prisma.user.findUnique({
      where: { email: body.email },
      include: {
        memberships: {
          orderBy: { createdAt: 'asc' },
          include: { organization: true },
        },
      },
    });

    if (!user || !(await bcrypt.compare(body.password, user.password))) {
      res.status(401).json({ error: 'Invalid email or password' });
      return;
    }

    const tokenPayload = { userId: user.id, email: user.email };
    const accessToken = generateAccessToken(tokenPayload);
    const refreshToken = generateRefreshToken(tokenPayload);

    res.json({
      accessToken,
      refreshToken,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phone: user.phone,
        profileImage: user.profileImage,
      },
      organization: toOrganizationPayload(user),
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Refresh Token ─────────────────────────────────────────
router.post('/refresh', async (req: Request, res: Response) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) {
      res.status(400).json({ error: 'Refresh token required' });
      return;
    }

    const payload = verifyRefreshToken(refreshToken);

    // Try User first, then MemberAccount
    const user = await prisma.user.findUnique({ where: { id: payload.userId } });
    if (user) {
      const accessToken = generateAccessToken({ userId: user.id, email: user.email });
      res.json({ accessToken });
      return;
    }

    const memberAccount = await prisma.memberAccount.findUnique({ where: { id: payload.userId } });
    if (memberAccount) {
      const accessToken = generateAccessToken({ userId: memberAccount.id, email: memberAccount.email });
      res.json({ accessToken });
      return;
    }

    res.status(401).json({ error: 'User not found' });
  } catch {
    res.status(401).json({ error: 'Invalid refresh token' });
  }
});

// ─── Get Profile ───────────────────────────────────────────
router.get('/profile', authMiddleware, async (req: Request, res: Response) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user!.userId },
      include: {
        memberships: {
          orderBy: { createdAt: 'asc' },
          include: { organization: true },
        },
      },
    });

    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    res.json({
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        phone: user.phone,
        profileImage: user.profileImage,
      },
      organization: toOrganizationPayload(user),
    });
  } catch (err) {
    console.error('Profile error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Update Profile ────────────────────────────────────────
const updateProfileSchema = z.object({
  name: z.string().min(1).optional(),
  phone: z.string().optional(),
  profileImage: z.string().optional(),
});

router.put('/profile', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = updateProfileSchema.parse(req.body);

    const user = await prisma.user.update({
      where: { id: req.user!.userId },
      data: body,
    });

    res.json({
      id: user.id,
      email: user.email,
      name: user.name,
      phone: user.phone,
      profileImage: user.profileImage,
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update profile error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member Account Register (회원 가입) ─────────────────
const memberRegisterSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
  name: z.string().min(1),
});

router.post('/member/register', async (req: Request, res: Response) => {
  try {
    const body = memberRegisterSchema.parse(req.body);

    const existing = await prisma.memberAccount.findUnique({ where: { email: body.email } });
    if (existing) {
      res.status(409).json({ error: 'Email already registered' });
      return;
    }

    const hashedPassword = await bcrypt.hash(body.password, 12);
    const account = await prisma.memberAccount.create({
      data: {
        email: body.email,
        password: hashedPassword,
        name: body.name,
      },
    });

    const tokenPayload = { userId: account.id, email: account.email };
    const accessToken = generateAccessToken(tokenPayload);
    const refreshToken = generateRefreshToken(tokenPayload);

    res.status(201).json({
      accessToken,
      refreshToken,
      memberAccount: { id: account.id, email: account.email, name: account.name },
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Member register error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member Account Login (회원 로그인) ─────────────────────
const memberLoginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

router.post('/member/login', async (req: Request, res: Response) => {
  try {
    const body = memberLoginSchema.parse(req.body);

    const account = await prisma.memberAccount.findUnique({
      where: { email: body.email },
      include: { members: true },
    });

    if (!account || !(await bcrypt.compare(body.password, account.password))) {
      res.status(401).json({ error: 'Invalid email or password' });
      return;
    }

    const tokenPayload = { userId: account.id, email: account.email };
    const accessToken = generateAccessToken(tokenPayload);
    const refreshToken = generateRefreshToken(tokenPayload);

    res.json({
      accessToken,
      refreshToken,
      memberAccount: {
        id: account.id,
        email: account.email,
        name: account.name,
      },
      members: account.members.map((m) => ({
        id: m.id,
        organizationId: m.organizationId,
        name: m.name,
      })),
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Member login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member Join via Invite Code ──────────────────────────
const memberJoinSchema = z.object({
  inviteCode: z.string().min(1),
});

router.post('/member/join', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = memberJoinSchema.parse(req.body);
    const memberAccountId = req.user!.userId;

    // Verify this is a member account
    const account = await prisma.memberAccount.findUnique({ where: { id: memberAccountId } });
    if (!account) {
      res.status(403).json({ error: 'Member account not found' });
      return;
    }

    const inviteCode = body.inviteCode.trim().toUpperCase();

    // Find organization by invite code
    const org = await prisma.organization.findUnique({ where: { inviteCode } });
    if (!org) {
      res.status(404).json({ error: 'Invalid invite code' });
      return;
    }

    // Check if already joined
    const existing = await prisma.member.findFirst({
      where: { organizationId: org.id, memberAccountId },
    });
    if (existing) {
      if (existing.status === 'ACTIVE') {
        res.json({
          alreadyJoined: true,
          member: {
            id: existing.id,
            organizationId: existing.organizationId,
            name: existing.name,
            status: existing.status,
          },
          organization: {
            id: org.id,
            name: org.name,
          },
        });
        return;
      }

      const reactivatedMember = await prisma.member.update({
        where: { id: existing.id },
        data: {
          status: 'ACTIVE',
          name: existing.name || account.name,
        },
      });

      res.json({
        reactivated: true,
        member: {
          id: reactivatedMember.id,
          organizationId: reactivatedMember.organizationId,
          name: reactivatedMember.name,
          status: reactivatedMember.status,
        },
        organization: {
          id: org.id,
          name: org.name,
        },
      });
      return;
    }

    // Create member record linked to this account
    const member = await prisma.member.create({
      data: {
        organizationId: org.id,
        memberAccountId,
        name: account.name,
      },
    });

    res.status(201).json({
      member: {
        id: member.id,
        organizationId: member.organizationId,
        name: member.name,
      },
      organization: {
        id: org.id,
        name: org.name,
      },
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Member join error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member My Classes ────────────────────────────────────
router.get('/member/my-classes', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberAccountId = req.user!.userId;

    const members = await prisma.member.findMany({
      where: { memberAccountId, status: 'ACTIVE' },
      select: {
        id: true,
        organizationId: true,
        organization: {
          select: {
            id: true,
            name: true,
          },
        },
      },
    });

    if (members.length === 0) {
      res.json({ classes: [] });
      return;
    }

    const organizationIds = [...new Set(members.map((member) => member.organizationId))];

    const memberships = await prisma.orgMembership.findMany({
      where: {
        organizationId: { in: organizationIds },
        role: 'COACH',
      },
      select: {
        organizationId: true,
        user: {
          select: {
            id: true,
            name: true,
            profileImage: true,
          },
        },
      },
      orderBy: { createdAt: 'asc' },
    });

    const coachesByOrganization = memberships.reduce<Record<string, { id: string; name: string; profileImage: string | null }[]>>(
      (acc, membership) => {
        if (!acc[membership.organizationId]) {
          acc[membership.organizationId] = [];
        }
        acc[membership.organizationId].push({
          id: membership.user.id,
          name: membership.user.name,
          profileImage: membership.user.profileImage,
        });
        return acc;
      },
      {},
    );

    const classes = members.map((m) => ({
      memberId: m.id,
      organization: {
        id: m.organization.id,
        name: m.organization.name,
      },
      coaches: coachesByOrganization[m.organizationId] ?? [],
    }));

    res.json({ classes });
  } catch (err) {
    console.error('Member my-classes error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/member/studios/:orgId/reservation-notice', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberAccountId = req.user!.userId;
    const orgId = req.params.orgId as string;

    const member = await prisma.member.findFirst({
      where: { organizationId: orgId, memberAccountId, status: 'ACTIVE' },
    });
    if (!member) {
      res.status(403).json({ error: 'Not a member of this studio' });
      return;
    }

    const organization = await prisma.organization.findUnique({
      where: { id: orgId },
      select: {
        id: true,
        name: true,
        reservationNoticeText: true,
        reservationNoticeImageUrl: true,
        reservationOpenDaysBefore: true,
        reservationOpenHoursBefore: true,
        reservationCancelDeadlineMinutes: true,
      },
    });

    if (!organization) {
      res.status(404).json({ error: 'Organization not found' });
      return;
    }

    res.json({
      organizationId: organization.id,
      organizationName: organization.name,
      reservationNoticeText: organization.reservationNoticeText,
      reservationNoticeImageUrl: organization.reservationNoticeImageUrl,
      reservationOpenDaysBefore: organization.reservationOpenDaysBefore,
      reservationOpenHoursBefore: organization.reservationOpenHoursBefore,
      reservationCancelDeadlineMinutes: organization.reservationCancelDeadlineMinutes,
    });
  } catch (err) {
    console.error('Member reservation notice error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member: Get Available Slots for a Studio ────────────
router.get('/member/studios/:orgId/slots', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberAccountId = req.user!.userId;
    const orgId = req.params.orgId as string;
    const date = req.query.date as string | undefined;
    if (!date) { res.status(400).json({ error: 'date query parameter required' }); return; }

    // Verify membership
    const member = await prisma.member.findFirst({
      where: { organizationId: orgId, memberAccountId, status: 'ACTIVE' },
    });
    if (!member) { res.status(403).json({ error: 'Not a member of this studio' }); return; }

    const [slots, organization] = await Promise.all([
      getAvailableSlots({
        organizationId: orgId,
        date,
        includeCoachNames: true,
      }),
      prisma.organization.findUnique({
        where: { id: orgId },
        select: {
          reservationOpenDaysBefore: true,
          reservationOpenHoursBefore: true,
        },
      }),
    ]);

    if (!organization) {
      res.status(404).json({ error: 'Organization not found' });
      return;
    }

    res.json(
      slots
          .filter((slot) => slot.isPublic)
          .filter((slot) =>
            canReserveAt(date, slot.startTime, {
              reservationOpenDaysBefore: organization.reservationOpenDaysBefore,
              reservationOpenHoursBefore: organization.reservationOpenHoursBefore,
              reservationCancelDeadlineMinutes: 0,
            }),
          ),
    );
  } catch (err) {
    console.error('Member get slots error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member: Reserve a Slot ──────────────────────────────
const memberReserveSchema = z.object({
  organizationId: z.string().uuid(),
  coachId: z.string().uuid(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  startTime: z.string().regex(/^\d{2}:\d{2}$/),
  endTime: z.string().regex(/^\d{2}:\d{2}$/),
});

router.post('/member/reserve', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberAccountId = req.user!.userId;
    const body = memberReserveSchema.parse(req.body);

    // Find member record for this org
    const [member, organization] = await Promise.all([
      prisma.member.findFirst({
        where: { organizationId: body.organizationId, memberAccountId, status: 'ACTIVE' },
      }),
      prisma.organization.findUnique({
        where: { id: body.organizationId },
        select: {
          reservationPolicy: true,
          reservationOpenDaysBefore: true,
          reservationOpenHoursBefore: true,
        },
      }),
    ]);
    if (!member) { res.status(403).json({ error: 'Not a member of this studio' }); return; }
    if (!organization) { res.status(404).json({ error: 'Organization not found' }); return; }

    if (!canReserveAt(body.date, body.startTime, {
      reservationOpenDaysBefore: organization.reservationOpenDaysBefore,
      reservationOpenHoursBefore: organization.reservationOpenHoursBefore,
      reservationCancelDeadlineMinutes: 0,
    })) {
      res.status(409).json({ error: '아직 예약 가능한 시간이 아니거나 이미 시작된 수업입니다' });
      return;
    }

    const targetDate = parseDateOnly(body.date);
    const dayOfWeek = getKstDayOfWeek(body.date);

    // Check overrides for this date & coach
    const override = await findFirstScheduleOverrideCompat({
      organizationId: body.organizationId,
      coachId: body.coachId,
      date: targetDate,
    });

    if (override?.type === 'CLOSED') {
      res.status(409).json({ error: '해당 날짜는 휴무입니다' });
      return;
    }

    const closedOverrides = await findScheduleOverridesCompat({
      organizationId: body.organizationId,
      coachId: body.coachId,
      date: targetDate,
    });
    const blockedByOverride = closedOverrides.some((candidate) =>
      isTimeRangeClosed(candidate, body.startTime, body.endTime),
    );
    if (blockedByOverride) {
      res.status(409).json({ error: '관리자가 예약 마감한 시간입니다' });
      return;
    }

    const matchedSlot = await findGeneratedSlot({
      organizationId: body.organizationId,
      date: body.date,
      coachId: body.coachId,
      startTime: body.startTime,
      endTime: body.endTime,
      includePast: false,
    });
    if (!matchedSlot) {
      res.status(409).json({ error: '예약 가능한 실제 수업 시간만 선택할 수 있습니다' });
      return;
    }

    // Determine maxCapacity from override or weekly schedule
    let maxCapacity: number | null = null;

    if (override?.type === 'OPEN') {
      maxCapacity = override.maxCapacity || 1;
    } else {
      const schedule = await findFirstScheduleCompat({
        organizationId: body.organizationId,
        coachId: body.coachId,
        dayOfWeek,
        isActive: true,
      });
      if (!schedule) { res.status(404).json({ error: 'No schedule found for this slot' }); return; }
      maxCapacity = schedule.maxCapacity;
    }

    const finalStatus = organization.reservationPolicy === 'REQUEST_APPROVAL' ? 'PENDING' : 'CONFIRMED';

    // Use transaction for capacity check + duplicate check + create
    const reservation = await prisma.$transaction(async (tx) => {
      // Check duplicate: same member, same slot
      const duplicate = await tx.reservation.findFirst({
        where: {
          memberId: member.id,
          coachId: body.coachId,
          date: targetDate,
          startTime: body.startTime,
          status: { notIn: ['CANCELLED'] },
        },
      });
      if (duplicate) throw new Error('DUPLICATE');

      // Check capacity
      const overlappingReservations = await tx.reservation.findMany({
        where: {
          organizationId: body.organizationId,
          coachId: body.coachId,
          date: targetDate,
          status: { in: ['PENDING', 'CONFIRMED'] },
        },
        select: { startTime: true, endTime: true },
      });
      const bookedOverlaps = overlappingReservations.filter((reservation) =>
        isOverlappingTimeRange(
          body.startTime,
          body.endTime,
          reservation.startTime,
          reservation.endTime,
        ),
      ).length;
      if (bookedOverlaps >= maxCapacity!) throw new Error('FULL');

      return tx.reservation.create({
        data: {
          organizationId: body.organizationId,
          coachId: body.coachId,
          memberId: member.id,
          date: targetDate,
          startTime: body.startTime,
          endTime: body.endTime,
          status: finalStatus,
        },
        include: {
          member: { select: { id: true, name: true, phone: true, memo: true } },
          coach: { select: { id: true, name: true } },
        },
      });
    });

    // Socket.IO real-time emit
    emitReservationCreated(body.organizationId, serializeReservation(reservation), memberAccountId);

    const coachMessage = buildReservationStatusMessage(finalStatus, body.date, body.startTime);

    // Push notification to coach
    const coach = await prisma.user.findUnique({
      where: { id: body.coachId },
      select: { fcmToken: true, id: true, notificationPreferences: true },
    });
    if (
      coach?.fcmToken &&
      shouldSendPushForType(coach.notificationPreferences, 'NEW_RESERVATION')
    ) {
      const memberAccount = await prisma.memberAccount.findUnique({ where: { id: memberAccountId }, select: { name: true } });
      sendPush(
        coach.fcmToken,
        coachMessage.title,
        `${memberAccount?.name ?? '회원'}님이 ${body.date} ${body.startTime} ${finalStatus === 'PENDING' ? '예약을 신청했습니다' : '예약했습니다'}`,
        { type: 'NEW_RESERVATION', reservationId: reservation.id },
      );
    }

    // Create notification record
    await prisma.notification.create({
      data: {
        userId: body.coachId,
        organizationId: body.organizationId,
        type: 'NEW_RESERVATION',
        title: coachMessage.title,
        body: coachMessage.body,
        data: { reservationId: reservation.id },
      },
    });

    res.status(201).json(serializeReservation(reservation));
  } catch (err) {
    if (err instanceof Error && err.message === 'DUPLICATE') {
      res.status(409).json({ error: '이미 예약된 시간입니다' });
      return;
    }
    if (err instanceof Error && err.message === 'FULL') {
      res.status(409).json({ error: 'This slot is fully booked' });
      return;
    }
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Member reserve error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member: Cancel Reservation ──────────────────────────
router.delete('/member/reservations/:id', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberAccountId = req.user!.userId;
    const reservationId = req.params.id as string;

    const reservation = await prisma.reservation.findUnique({
      where: { id: reservationId },
      include: { member: { select: { memberAccountId: true } } },
    });

    if (!reservation || reservation.member?.memberAccountId !== memberAccountId) {
      res.status(404).json({ error: 'Reservation not found' });
      return;
    }

    if (!['PENDING', 'CONFIRMED'].includes(reservation.status)) {
      res.status(400).json({ error: 'Cannot cancel this reservation' });
      return;
    }

    const organization = await prisma.organization.findUnique({
      where: { id: reservation.organizationId },
      select: { reservationCancelDeadlineMinutes: true },
    });
    if (!organization) {
      res.status(404).json({ error: 'Organization not found' });
      return;
    }

    if (!canCancelAt(
      formatDateOnly(reservation.date),
      reservation.startTime,
      {
        reservationOpenDaysBefore: 0,
        reservationOpenHoursBefore: 0,
        reservationCancelDeadlineMinutes: organization.reservationCancelDeadlineMinutes,
      },
    )) {
      res.status(409).json({
        error: `수업 ${organization.reservationCancelDeadlineMinutes}분 전까지만 취소할 수 있습니다`,
      });
      return;
    }

    const updatedReservation = await prisma.reservation.update({
      where: { id: reservationId },
      data: { status: 'CANCELLED' },
      include: {
        member: { select: { id: true, name: true, phone: true, memo: true } },
        coach: { select: { id: true, name: true } },
      },
    });

    // Socket.IO real-time emit
    emitReservationCancelled(
      reservation.organizationId,
      serializeReservation(updatedReservation),
      reservation.coachId,
      memberAccountId,
    );

    // Push notification to coach
    const coach = await prisma.user.findUnique({
      where: { id: reservation.coachId },
      select: { fcmToken: true, notificationPreferences: true },
    });
    if (
      coach?.fcmToken &&
      shouldSendPushForType(
        coach.notificationPreferences,
        'RESERVATION_CANCELLED',
      )
    ) {
      const memberAccount = await prisma.memberAccount.findUnique({ where: { id: memberAccountId }, select: { name: true } });
      const dateStr = formatDateOnly(reservation.date);
      sendPush(
        coach.fcmToken,
        '예약 취소',
        `${memberAccount?.name ?? '회원'}님이 ${dateStr} ${reservation.startTime} 예약을 취소했습니다`,
        { type: 'RESERVATION_CANCELLED', reservationId },
      );
    }

    // Create notification record
    await prisma.notification.create({
      data: {
        userId: reservation.coachId,
        organizationId: reservation.organizationId,
        type: 'RESERVATION_CANCELLED',
        title: '예약 취소',
        body: `회원이 ${formatDateOnly(reservation.date)} ${reservation.startTime} 예약을 취소했습니다`,
        data: { reservationId },
      },
    });

    res.json({ message: 'Reservation cancelled' });
  } catch (err) {
    console.error('Member cancel reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member: My Reservations ─────────────────────────────
router.get('/member/my-reservations', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberAccountId = req.user!.userId;

    const members = await prisma.member.findMany({
      where: { memberAccountId, status: 'ACTIVE' },
      select: { id: true, organizationId: true, organization: { select: { name: true } } },
    });

    if (members.length === 0) { res.json({ reservations: [] }); return; }

    const today = parseDateOnly(getKstToday());

    const reservations = await prisma.reservation.findMany({
      where: {
        memberId: { in: members.map((m) => m.id) },
        status: { in: ['PENDING', 'CONFIRMED', 'COMPLETED'] },
        date: { gte: today },
      },
      include: {
        coach: { select: { id: true, name: true } },
        organization: { select: { id: true, name: true } },
      },
      orderBy: [{ date: 'asc' }, { startTime: 'asc' }],
    });

    res.json({
      reservations: reservations.map((r) => ({
        id: r.id,
        organizationId: r.organizationId,
        organizationName: r.organization.name,
        coachId: r.coachId,
        coachName: r.coach.name,
        date: formatDateOnly(r.date),
        startTime: r.startTime,
        endTime: r.endTime,
        status: r.status,
      })),
    });
  } catch (err) {
    console.error('Member my-reservations error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const memberPackagePauseRequestSchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  reason: z.string().max(300).optional(),
});

router.get('/member/packages', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberAccountId = req.user!.userId;

    const members = await prisma.member.findMany({
      where: { memberAccountId, status: 'ACTIVE' },
      select: { id: true, organizationId: true },
    });

    if (members.length === 0) {
      res.json({ packages: [] });
      return;
    }

    const memberPackages = await listMemberPackagesCompat({
      memberIds: members.map((member) => member.id),
    });

    res.json({ packages: memberPackages });
  } catch (err) {
    console.error('Member packages error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/member/packages/:id/pause-request', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = memberPackagePauseRequestSchema.parse(req.body);
    const memberAccountId = req.user!.userId;

    if (body.endDate < body.startDate) {
      res.status(400).json({ error: '종료일은 시작일보다 빠를 수 없습니다' });
      return;
    }

    const today = getKstToday();
    if (body.startDate < today) {
      res.status(400).json({ error: '정지 시작일은 오늘 이후로 선택해주세요' });
      return;
    }

    const memberPackage = await findMemberPackageCompat({ id: req.params.id as string });
    if (!memberPackage || memberPackage.member?.memberAccountId !== memberAccountId) {
      res.status(404).json({ error: '패키지를 찾을 수 없습니다' });
      return;
    }

    if (memberPackage.status !== 'ACTIVE' || memberPackage.remainingSessions <= 0) {
      res.status(400).json({ error: '사용 가능한 패키지에서만 정지 신청할 수 있습니다' });
      return;
    }

    if (memberPackage.expiryDate && body.startDate > formatDateOnly(new Date(memberPackage.expiryDate))) {
      res.status(400).json({ error: '만료 이후 기간은 정지 신청할 수 없습니다' });
      return;
    }

    if (memberPackage.pauseRequestStatus === 'PENDING') {
      res.status(400).json({ error: '이미 검토 중인 정지 신청이 있습니다' });
      return;
    }

    const packageName = memberPackage.package?.name ?? '패키지';
    const extensionDays = calculatePauseDays(body.startDate, body.endDate);

    await updateMemberPackagePauseCompat(memberPackage.id, {
      pauseRequestedStartDate: parseDateOnly(body.startDate),
      pauseRequestedEndDate: parseDateOnly(body.endDate),
      pauseRequestStatus: 'PENDING',
      pauseRequestReason: body.reason?.trim() || null,
    });

    const adminUsers = await prisma.orgMembership.findMany({
      where: {
        organizationId: memberPackage.member?.organizationId,
        role: { in: ['OWNER', 'ADMIN'] },
        user: { fcmToken: { not: null } },
      },
      select: {
        user: { select: { fcmToken: true } },
      },
    });

    await Promise.all(adminUsers.map(async ({ user }) => {
      if (!user.fcmToken) return;
      await sendPush(
        user.fcmToken,
        '패키지 정지 신청',
        `${memberPackage.member?.name ?? '회원'}님이 ${packageName} 정지를 신청했습니다`,
        { memberPackageId: memberPackage.id },
      );
    }));

    res.json({
      message: `정지 신청이 접수되었습니다. 승인되면 만료일이 ${extensionDays}일 연장됩니다`,
      extensionDays,
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Member package pause request error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member Profile ───────────────────────────────────────
router.get('/member/profile', authMiddleware, async (req: Request, res: Response) => {
  try {
    const account = await prisma.memberAccount.findUnique({
      where: { id: req.user!.userId },
    });

    if (!account) {
      res.status(404).json({ error: 'Member account not found' });
      return;
    }

    res.json({
      memberAccount: {
        id: account.id,
        email: account.email,
        name: account.name,
      },
    });
  } catch (err) {
    console.error('Member profile error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member → Admin Upgrade (회원→관리자 전환) ───────────
const upgradeToAdminSchema = z.object({
  organizationName: z.string().min(1),
});

router.post('/member/upgrade-to-admin', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = upgradeToAdminSchema.parse(req.body);
    const memberAccountId = req.user!.userId;

    // Verify caller is a MemberAccount
    const account = await prisma.memberAccount.findUnique({ where: { id: memberAccountId } });
    if (!account) {
      res.status(403).json({ error: 'Member account not found' });
      return;
    }

    // Check if a User with same email already exists
    let user = await prisma.user.findUnique({
      where: { email: account.email },
      include: { memberships: { include: { organization: true }, orderBy: { createdAt: 'asc' } } },
    });

    if (user) {
      // User already exists — just return tokens
      const tokenPayload = { userId: user.id, email: user.email };
      const accessToken = generateAccessToken(tokenPayload);
      const refreshToken = generateRefreshToken(tokenPayload);
      res.json({
        accessToken,
        refreshToken,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          phone: user.phone,
          profileImage: user.profileImage,
        },
        organization: toOrganizationPayload(user),
      });
      return;
    }

    // Create new User + Organization
    const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();

    const result = await prisma.$transaction(async (tx) => {
      const newUser = await tx.user.create({
        data: {
          email: account.email,
          password: account.password, // reuse hashed password
          name: account.name,
          googleId: (account as any).googleId || undefined,
          appleId: (account as any).appleId || undefined,
        },
      });

      const org = await tx.organization.create({
        data: { name: body.organizationName, inviteCode },
      });

      await tx.orgMembership.create({
        data: { userId: newUser.id, organizationId: org.id, role: 'OWNER' },
      });

      return { user: newUser, org };
    });

    const tokenPayload = { userId: result.user.id, email: result.user.email };
    const accessToken = generateAccessToken(tokenPayload);
    const refreshToken = generateRefreshToken(tokenPayload);

    res.status(201).json({
      accessToken,
      refreshToken,
      user: {
        id: result.user.id,
        email: result.user.email,
        name: result.user.name,
        phone: result.user.phone,
        profileImage: result.user.profileImage,
      },
      organization: {
        id: result.org.id,
        name: result.org.name,
        inviteCode: result.org.inviteCode,
      },
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Upgrade to admin error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── FCM Token Registration (User) ──────────────────────
const fcmTokenSchema = z.object({ fcmToken: z.string().min(1) });

router.put('/fcm-token', authMiddleware, async (req: Request, res: Response) => {
  try {
    const { fcmToken } = fcmTokenSchema.parse(req.body);
    await prisma.user.update({
      where: { id: req.user!.userId },
      data: { fcmToken },
    });
    res.json({ message: 'FCM token updated' });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('FCM token update error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/notification-preferences', authMiddleware, async (_req: Request, res: Response) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: _req.user!.userId },
      select: { notificationPreferences: true },
    });
    res.json(parseNotificationPreferences(user?.notificationPreferences));
  } catch (err) {
    console.error('Notification preferences fetch error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/notification-preferences', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = notificationPreferencesSchema.parse(req.body);
    await prisma.user.update({
      where: { id: req.user!.userId },
      data: {
        notificationPreferences: stringifyNotificationPreferences(body),
      },
    });
    res.json(body);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Notification preferences update error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── FCM Token Registration (MemberAccount) ─────────────
router.put('/member/fcm-token', authMiddleware, async (req: Request, res: Response) => {
  try {
    const { fcmToken } = fcmTokenSchema.parse(req.body);
    await prisma.memberAccount.update({
      where: { id: req.user!.userId },
      data: { fcmToken },
    });
    res.json({ message: 'FCM token updated' });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Member FCM token update error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/member/notification-preferences', authMiddleware, async (req: Request, res: Response) => {
  try {
    const memberAccount = await prisma.memberAccount.findUnique({
      where: { id: req.user!.userId },
      select: { notificationPreferences: true },
    });
    res.json(parseNotificationPreferences(memberAccount?.notificationPreferences));
  } catch (err) {
    console.error('Member notification preferences fetch error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/member/notification-preferences', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = notificationPreferencesSchema.parse(req.body);
    await prisma.memberAccount.update({
      where: { id: req.user!.userId },
      data: {
        notificationPreferences: stringifyNotificationPreferences(body),
      },
    });
    res.json(body);
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Member notification preferences update error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Social Login (User — Admin/Coach) ──────────────────
const socialLoginSchema = z.object({
  idToken: z.string().min(1),
  provider: z.enum(['google', 'apple']),
  name: z.string().nullish().transform((value) => value || undefined),
});

const googleClient = new OAuth2Client();
const googleAudiences = [env.GOOGLE_CLIENT_ID, env.GOOGLE_ANDROID_CLIENT_ID, env.GOOGLE_IOS_CLIENT_ID].filter(Boolean);

function buildAppleFallbackEmail(sub: string): string {
  const normalizedSub = sub.toLowerCase().replace(/[^a-z0-9._-]/g, '');
  return `apple-${normalizedSub}@users.coachdesk.local`;
}

function handleSocialLoginError(res: Response, label: string, err: unknown) {
  if (err instanceof z.ZodError) {
    res.status(400).json({ error: 'Validation error', details: err.errors });
    return;
  }

  if (err instanceof Error) {
    console.error(label, err);

    const message = err.message;
    if (
      /apple|jwt|token|audience|issuer|public key|signature|invalid|timed out|failed to reach/i.test(message)
    ) {
      res.status(400).json({ error: message });
      return;
    }

    if (/unique constraint|duplicate key/i.test(message)) {
      res.status(409).json({ error: '이미 연결된 계정입니다' });
      return;
    }

    if (env.NODE_ENV !== 'production') {
      res.status(500).json({ error: message });
      return;
    }
  } else {
    console.error(label, err);
  }

  res.status(500).json({ error: 'Internal server error' });
}

router.post('/social', async (req: Request, res: Response) => {
  try {
    const body = socialLoginSchema.parse(req.body);
    let email: string;
    let socialId: string;
    let displayName: string | undefined = body.name;

    if (body.provider === 'google') {
      const ticket = await googleClient.verifyIdToken({
        idToken: body.idToken,
        audience: googleAudiences,
      });
      const payload = ticket.getPayload();
      if (!payload || !payload.email) {
        res.status(400).json({ error: 'Invalid Google token' });
        return;
      }
      email = payload.email;
      socialId = payload.sub;
      displayName = displayName || payload.name || email.split('@')[0];
    } else {
      const payload = await verifyAppleIdentityToken(body.idToken);
      socialId = payload.sub;
      email = payload.email ?? buildAppleFallbackEmail(payload.sub);
      displayName = displayName || payload.email?.split('@')[0];
    }

    const socialField = body.provider === 'google' ? 'googleId' : 'appleId';

    // Find by socialId or email
    let user = await prisma.user.findFirst({
      where: email
        ? { OR: [{ [socialField]: socialId }, { email }] }
        : { [socialField]: socialId },
      include: { memberships: { include: { organization: true }, orderBy: { createdAt: 'asc' } } },
    });

    if (user) {
      // Link social if not yet linked
      if (!user[socialField]) {
        user = await prisma.user.update({
          where: { id: user.id },
          data: { [socialField]: socialId },
          include: { memberships: { include: { organization: true }, orderBy: { createdAt: 'asc' } } },
        });
      }
    } else {
      // Create new user + organization
      const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();
      const result = await prisma.$transaction(async (tx) => {
        const newUser = await tx.user.create({
          data: {
            email,
            password: await bcrypt.hash(Math.random().toString(36), 12),
            name: displayName || email.split('@')[0],
            [socialField]: socialId,
          },
        });
        const org = await tx.organization.create({
          data: { name: `${displayName || email.split('@')[0]}'s Studio`, inviteCode },
        });
        await tx.orgMembership.create({
          data: { userId: newUser.id, organizationId: org.id, role: 'OWNER' },
        });
        return { user: newUser, org };
      });

      user = await prisma.user.findUnique({
        where: { id: result.user.id },
        include: { memberships: { include: { organization: true }, orderBy: { createdAt: 'asc' } } },
      }) as any;
    }

    const tokenPayload = { userId: user!.id, email: user!.email };
    const accessToken = generateAccessToken(tokenPayload);
    const refreshToken = generateRefreshToken(tokenPayload);
    res.json({
      accessToken,
      refreshToken,
      user: {
        id: user!.id,
        email: user!.email,
        name: user!.name,
        phone: user!.phone,
        profileImage: user!.profileImage,
      },
      organization: toOrganizationPayload(user!),
    });
  } catch (err) {
    handleSocialLoginError(res, 'Social login error:', err);
  }
});

// ─── Social Login (MemberAccount) ───────────────────────
router.post('/member/social', async (req: Request, res: Response) => {
  try {
    const body = socialLoginSchema.parse(req.body);
    let email: string;
    let socialId: string;
    let displayName: string | undefined = body.name;

    if (body.provider === 'google') {
      const ticket = await googleClient.verifyIdToken({
        idToken: body.idToken,
        audience: googleAudiences,
      });
      const payload = ticket.getPayload();
      if (!payload || !payload.email) {
        res.status(400).json({ error: 'Invalid Google token' });
        return;
      }
      email = payload.email;
      socialId = payload.sub;
      displayName = displayName || payload.name || email.split('@')[0];
    } else {
      const payload = await verifyAppleIdentityToken(body.idToken);
      socialId = payload.sub;
      email = payload.email ?? buildAppleFallbackEmail(payload.sub);
      displayName = displayName || payload.email?.split('@')[0];
    }

    const socialField = body.provider === 'google' ? 'googleId' : 'appleId';

    let account = await prisma.memberAccount.findFirst({
      where: email
        ? { OR: [{ [socialField]: socialId }, { email }] }
        : { [socialField]: socialId },
      include: { members: true },
    });

    if (account) {
      if (!account[socialField]) {
        account = await prisma.memberAccount.update({
          where: { id: account.id },
          data: { [socialField]: socialId },
          include: { members: true },
        });
      }
    } else {
      account = await prisma.memberAccount.create({
        data: {
          email,
          password: await bcrypt.hash(Math.random().toString(36), 12),
          name: displayName || email.split('@')[0],
          [socialField]: socialId,
        },
        include: { members: true },
      });
    }

    const tokenPayload = { userId: account.id, email: account.email };
    const accessToken = generateAccessToken(tokenPayload);
    const refreshToken = generateRefreshToken(tokenPayload);

    res.json({
      accessToken,
      refreshToken,
      memberAccount: { id: account.id, email: account.email, name: account.name },
      members: account.members.map((m) => ({
        id: m.id,
        organizationId: m.organizationId,
        name: m.name,
      })),
    });
  } catch (err) {
    handleSocialLoginError(res, 'Member social login error:', err);
  }
});

export default router;
