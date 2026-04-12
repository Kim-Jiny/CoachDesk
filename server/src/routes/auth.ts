import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { generateAccessToken, generateRefreshToken, verifyRefreshToken } from '../utils/jwt';
import { authMiddleware } from '../middleware/auth';
import { sendPush } from '../utils/firebase';
import { env } from '../config/env';
import { verifyAppleIdentityToken } from '../utils/apple-auth';
import {
  formatDateOnly,
} from '../utils/kst-date';
import { emitReservationCreated, emitReservationCancelled } from '../socket/emitters';
import {
  toMemberAccountPayload,
  toMemberLinks,
  toOrganizationPayload,
  toUserPayload,
} from '../features/auth/payloads';
import {
  AuthFlowError,
  deleteMemberAccount,
  deleteUserAccount,
  getUserProfile,
  loginMemberAccount,
  loginUserAccount,
  refreshAccessToken,
  registerMemberAccount,
  registerUserAccount,
  updateUserProfile,
} from '../features/auth/accounts';
import {
  fcmTokenSchema,
  getMemberNotificationPreferences,
  getUserNotificationPreferences,
  notificationPreferencesSchema,
  updateMemberFcmToken,
  updateMemberNotificationPreferences,
  updateUserFcmToken,
  updateUserNotificationPreferences,
} from '../features/auth/notification-settings';
import {
  handleSocialLoginError,
  socialLoginMemberAccount,
  socialLoginSchema,
  socialLoginUser,
} from '../features/auth/social';
import { buildReservationStatusMessage } from '../features/reservation/notifications';
import {
  getMemberMyClasses,
  getMemberPackages as getMemberAccountPackages,
  getMemberProfile,
  getMyReservations,
  getReservationNotice,
  getStudioSlots,
  MemberAccountQueryError,
} from '../features/member-account/queries';
import {
  joinStudio,
  MemberAccountMutationError,
  requestPackagePause,
  upgradeToAdmin,
} from '../features/member-account/mutations';
import {
  cancelMemberReservation,
  MemberReservationError,
  reserveMemberSlot,
} from '../features/reservation/member-reservation';
import { serializeReservation } from '../features/reservation/serializer';
import {
} from '../utils/member-package-access';
import {
  shouldSendPushForType,
} from '../utils/notification-preferences';

const router = Router();

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
    res.status(201).json(await registerUserAccount({
      ...body,
      generateAccessToken,
      generateRefreshToken,
    }));
  } catch (err) {
    if (err instanceof AuthFlowError && err.code === 'EMAIL_ALREADY_REGISTERED') {
      res.status(409).json({ error: 'Email already registered' });
      return;
    }
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
    res.json(await loginUserAccount({
      ...body,
      generateAccessToken,
      generateRefreshToken,
    }));
  } catch (err) {
    if (err instanceof AuthFlowError && err.code === 'INVALID_CREDENTIALS') {
      res.status(401).json({ error: 'Invalid email or password' });
      return;
    }
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
    res.json(await refreshAccessToken({
      refreshToken: req.body?.refreshToken,
      verifyRefreshToken,
      generateAccessToken,
    }));
  } catch {
    res.status(401).json({ error: 'Invalid refresh token' });
  }
});

// ─── Get Profile ───────────────────────────────────────────
router.get('/profile', authMiddleware, async (req: Request, res: Response) => {
  try {
    res.json(await getUserProfile(req.user!.userId));
  } catch (err) {
    if (err instanceof AuthFlowError && err.code === 'USER_NOT_FOUND') {
      res.status(404).json({ error: 'User not found' });
      return;
    }
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
    res.json(await updateUserProfile({ userId: req.user!.userId, ...body }));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Update profile error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/profile', authMiddleware, async (req: Request, res: Response) => {
  try {
    res.json(await deleteUserAccount(req.user!.userId));
  } catch (err) {
    if (err instanceof AuthFlowError) {
      if (err.code === 'USER_NOT_FOUND') {
        res.status(404).json({ error: 'User not found' });
        return;
      }
      if (err.code === 'LAST_ORG_ADMIN') {
        res.status(409).json({
          error: '조직에 남은 관리자 또는 오너가 없어 관리자 계정을 삭제할 수 없습니다',
        });
        return;
      }
    }
    console.error('Delete profile error:', err);
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
    res.status(201).json(await registerMemberAccount({
      ...body,
      generateAccessToken,
      generateRefreshToken,
    }));
  } catch (err) {
    if (err instanceof AuthFlowError && err.code === 'EMAIL_ALREADY_REGISTERED') {
      res.status(409).json({ error: 'Email already registered' });
      return;
    }
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
    res.json(await loginMemberAccount({
      ...body,
      generateAccessToken,
      generateRefreshToken,
    }));
  } catch (err) {
    if (err instanceof AuthFlowError && err.code === 'INVALID_CREDENTIALS') {
      res.status(401).json({ error: 'Invalid email or password' });
      return;
    }
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
    res.status(201).json(await joinStudio({
      memberAccountId: req.user!.userId,
      inviteCode: body.inviteCode,
    }));
  } catch (err) {
    if (err instanceof MemberAccountMutationError) {
      if (err.code === 'MEMBER_ACCOUNT_NOT_FOUND') {
        res.status(403).json({ error: 'Member account not found' });
        return;
      }
      if (err.code === 'INVALID_INVITE_CODE') {
        res.status(404).json({ error: 'Invalid invite code' });
        return;
      }
    }
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
    res.json(await getMemberMyClasses(req.user!.userId));
  } catch (err) {
    console.error('Member my-classes error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/member/studios/:orgId/reservation-notice', authMiddleware, async (req: Request, res: Response) => {
  try {
    res.json(await getReservationNotice({
      memberAccountId: req.user!.userId,
      organizationId: req.params.orgId as string,
    }));
  } catch (err) {
    if (err instanceof MemberAccountQueryError) {
      if (err.code === 'NOT_MEMBER_OF_STUDIO') {
        res.status(403).json({ error: 'Not a member of this studio' });
        return;
      }
      if (err.code === 'ORG_NOT_FOUND') {
        res.status(404).json({ error: 'Organization not found' });
        return;
      }
    }
    console.error('Member reservation notice error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member: Get Available Slots for a Studio ────────────
router.get('/member/studios/:orgId/slots', authMiddleware, async (req: Request, res: Response) => {
  try {
    res.json(await getStudioSlots({
      memberAccountId: req.user!.userId,
      organizationId: req.params.orgId as string,
      date: req.query.date as string | undefined,
    }));
  } catch (err) {
    if (err instanceof MemberAccountQueryError) {
      if (err.code === 'DATE_REQUIRED') {
        res.status(400).json({ error: 'date query parameter required' });
        return;
      }
      if (err.code === 'NOT_MEMBER_OF_STUDIO') {
        res.status(403).json({ error: 'Not a member of this studio' });
        return;
      }
      if (err.code === 'ORG_NOT_FOUND') {
        res.status(404).json({ error: 'Organization not found' });
        return;
      }
    }
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
    const { reservation, finalStatus } = await reserveMemberSlot({
      memberAccountId,
      ...body,
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
    if (err instanceof MemberReservationError) {
      if (err.code === 'NOT_MEMBER') {
        res.status(403).json({ error: 'Not a member of this studio' });
        return;
      }
      if (err.code === 'ORG_NOT_FOUND') {
        res.status(404).json({ error: 'Organization not found' });
        return;
      }
      if (err.code === 'RESERVE_WINDOW_CLOSED') {
        res.status(409).json({ error: '아직 예약 가능한 시간이 아니거나 이미 시작된 수업입니다' });
        return;
      }
      if (err.code === 'DATE_CLOSED') {
        res.status(409).json({ error: '해당 날짜는 휴무입니다' });
        return;
      }
      if (err.code === 'TIME_CLOSED') {
        res.status(409).json({ error: '관리자가 예약 마감한 시간입니다' });
        return;
      }
      if (err.code === 'INVALID_SLOT') {
        res.status(409).json({ error: '예약 가능한 실제 수업 시간만 선택할 수 있습니다' });
        return;
      }
      if (err.code === 'NO_SCHEDULE') {
        res.status(404).json({ error: 'No schedule found for this slot' });
        return;
      }
      if (err.code === 'DUPLICATE') {
        res.status(409).json({ error: '이미 예약된 시간입니다' });
        return;
      }
      if (err.code === 'FULL') {
        res.status(409).json({ error: 'This slot is fully booked' });
        return;
      }
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
    const { reservation, updatedReservation } = await cancelMemberReservation({
      memberAccountId,
      reservationId,
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
    if (err instanceof MemberReservationError) {
      if (err.code === 'RESERVATION_NOT_FOUND') {
        res.status(404).json({ error: 'Reservation not found' });
        return;
      }
      if (err.code === 'CANNOT_CANCEL') {
        res.status(400).json({ error: 'Cannot cancel this reservation' });
        return;
      }
      if (err.code === 'ORG_NOT_FOUND') {
        res.status(404).json({ error: 'Organization not found' });
        return;
      }
      if (err.code === 'CANCEL_WINDOW_CLOSED') {
        res.status(409).json({
          error: `수업 ${err.meta?.deadlineMinutes}분 전까지만 취소할 수 있습니다`,
        });
        return;
      }
    }
    console.error('Member cancel reservation error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Member: My Reservations ─────────────────────────────
router.get('/member/my-reservations', authMiddleware, async (req: Request, res: Response) => {
  try {
    res.json(await getMyReservations(req.user!.userId));
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
    res.json(await getMemberAccountPackages(req.user!.userId));
  } catch (err) {
    console.error('Member packages error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/member/packages/:id/pause-request', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = memberPackagePauseRequestSchema.parse(req.body);
    res.json(await requestPackagePause({
      memberAccountId: req.user!.userId,
      memberPackageId: req.params.id as string,
      startDate: body.startDate,
      endDate: body.endDate,
      reason: body.reason,
    }));
  } catch (err) {
    if (err instanceof MemberAccountMutationError) {
      if (err.code === 'INVALID_PAUSE_RANGE') {
        res.status(400).json({ error: '종료일은 시작일보다 빠를 수 없습니다' });
        return;
      }
      if (err.code === 'PAUSE_START_IN_PAST') {
        res.status(400).json({ error: '정지 시작일은 오늘 이후로 선택해주세요' });
        return;
      }
      if (err.code === 'PACKAGE_NOT_FOUND') {
        res.status(404).json({ error: '패키지를 찾을 수 없습니다' });
        return;
      }
      if (err.code === 'PACKAGE_NOT_AVAILABLE') {
        res.status(400).json({ error: '사용 가능한 패키지에서만 정지 신청할 수 있습니다' });
        return;
      }
      if (err.code === 'PAUSE_AFTER_EXPIRY') {
        res.status(400).json({ error: '만료 이후 기간은 정지 신청할 수 없습니다' });
        return;
      }
      if (err.code === 'PAUSE_ALREADY_PENDING') {
        res.status(400).json({ error: '이미 검토 중인 정지 신청이 있습니다' });
        return;
      }
    }
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
    res.json(await getMemberProfile(req.user!.userId));
  } catch (err) {
    if (err instanceof MemberAccountQueryError && err.code === 'MEMBER_ACCOUNT_NOT_FOUND') {
      res.status(404).json({ error: 'Member account not found' });
      return;
    }
    console.error('Member profile error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/member/profile', authMiddleware, async (req: Request, res: Response) => {
  try {
    res.json(await deleteMemberAccount(req.user!.userId));
  } catch (err) {
    if (err instanceof AuthFlowError && err.code === 'MEMBER_ACCOUNT_NOT_FOUND') {
      res.status(404).json({ error: 'Member account not found' });
      return;
    }
    console.error('Delete member profile error:', err);
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
    res.status(201).json(await upgradeToAdmin({
      memberAccountId: req.user!.userId,
      organizationName: body.organizationName,
      generateAccessToken,
      generateRefreshToken,
    }));
  } catch (err) {
    if (err instanceof MemberAccountMutationError && err.code === 'MEMBER_ACCOUNT_NOT_FOUND') {
      res.status(403).json({ error: 'Member account not found' });
      return;
    }
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Upgrade to admin error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── FCM Token Registration (User) ──────────────────────
router.put('/fcm-token', authMiddleware, async (req: Request, res: Response) => {
  try {
    const { fcmToken } = fcmTokenSchema.parse(req.body);
    await updateUserFcmToken(req.user!.userId, fcmToken);
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
    res.json(await getUserNotificationPreferences(_req.user!.userId));
  } catch (err) {
    console.error('Notification preferences fetch error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/notification-preferences', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = notificationPreferencesSchema.parse(req.body);
    res.json(await updateUserNotificationPreferences(req.user!.userId, body));
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
    await updateMemberFcmToken(req.user!.userId, fcmToken);
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
    res.json(await getMemberNotificationPreferences(req.user!.userId));
  } catch (err) {
    console.error('Member notification preferences fetch error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/member/notification-preferences', authMiddleware, async (req: Request, res: Response) => {
  try {
    const body = notificationPreferencesSchema.parse(req.body);
    res.json(await updateMemberNotificationPreferences(req.user!.userId, body));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Member notification preferences update error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/social', async (req: Request, res: Response) => {
  try {
    const body = socialLoginSchema.parse(req.body);
    res.json(await socialLoginUser({
      body,
      generateAccessToken,
      generateRefreshToken,
    }));
  } catch (err) {
    handleSocialLoginError(res, 'Social login error:', err);
  }
});

// ─── Social Login (MemberAccount) ───────────────────────
router.post('/member/social', async (req: Request, res: Response) => {
  try {
    const body = socialLoginSchema.parse(req.body);
    res.json(await socialLoginMemberAccount({
      body,
      generateAccessToken,
      generateRefreshToken,
    }));
  } catch (err) {
    handleSocialLoginError(res, 'Member social login error:', err);
  }
});

export default router;
