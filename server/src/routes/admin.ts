import bcrypt from 'bcryptjs';
import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { Prisma } from '@prisma/client';
import { prisma } from '../utils/prisma';
import { isSuperAdminEmail } from '../utils/super-admin';
import { adminAuthMiddleware, signAdminToken } from '../utils/admin-auth';
import { checkAdminLimit } from '../utils/plan-limits';
import { deleteMemberAccount, deleteUserAccount } from '../features/auth/accounts';

const router = Router();

// ─── Admin Login (인증 미들웨어 이전에 위치) ─────────────
const adminLoginSchema = z.object({
  username: z.string().min(1).max(50),
  password: z.string().min(1).max(200),
});

router.post('/login', async (req: Request, res: Response) => {
  try {
    const body = adminLoginSchema.parse(req.body);
    const account = await prisma.adminAccount.findUnique({
      where: { username: body.username },
    });
    if (!account) {
      res.status(401).json({ error: 'Invalid credentials' });
      return;
    }
    const ok = await bcrypt.compare(body.password, account.password);
    if (!ok) {
      res.status(401).json({ error: 'Invalid credentials' });
      return;
    }
    const token = signAdminToken({
      adminId: account.id,
      username: account.username,
    });
    res.json({ token, admin: { id: account.id, username: account.username } });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin login error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── 이후 라우트는 모두 admin 토큰 인증 필요 ─────────────
router.use(adminAuthMiddleware);

router.get('/me', (req: Request, res: Response) => {
  res.json({ admin: req.adminAccount });
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(4).max(200),
});

router.post('/me/change-password', async (req: Request, res: Response) => {
  try {
    const body = changePasswordSchema.parse(req.body);
    const account = await prisma.adminAccount.findUnique({
      where: { id: req.adminAccount!.id },
    });
    if (!account) {
      res.status(404).json({ error: 'Admin account not found' });
      return;
    }
    const ok = await bcrypt.compare(body.currentPassword, account.password);
    if (!ok) {
      res.status(401).json({ error: 'Current password incorrect' });
      return;
    }
    const hashed = await bcrypt.hash(body.newPassword, 10);
    await prisma.adminAccount.update({
      where: { id: account.id },
      data: { password: hashed },
    });
    res.json({ success: true });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin change password error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

const searchQuerySchema = z.object({
  search: z.string().optional(),
});

const updateOrganizationSchema = z.object({
  name: z.string().min(1).max(80).optional(),
  description: z.string().max(500).nullable().optional(),
  planType: z.enum(['FREE', 'BASIC', 'PRO', 'ENTERPRISE']).optional(),
  maxAdminCount: z.number().int().min(1).max(999).optional(),
  maxMemberCount: z.number().int().min(1).max(100000).optional(),
  bookingMode: z.enum(['PRIVATE', 'PUBLIC']).optional(),
  reservationPolicy: z.enum(['AUTO_CONFIRM', 'REQUEST_APPROVAL']).optional(),
  reservationOpenDaysBefore: z.number().int().min(0).max(365).optional(),
  reservationOpenHoursBefore: z.number().int().min(0).max(23).optional(),
  reservationCancelDeadlineMinutes: z.number().int().min(0).max(10080).optional(),
});

const createOrganizationSchema = z.object({
  name: z.string().min(1).max(80),
  description: z.string().max(500).nullable().optional(),
  ownerUserId: z.string().uuid(),
  planType: z.enum(['FREE', 'BASIC', 'PRO', 'ENTERPRISE']).default('FREE'),
  maxAdminCount: z.number().int().min(1).max(999).default(2),
  maxMemberCount: z.number().int().min(1).max(100000).default(30),
  bookingMode: z.enum(['PRIVATE', 'PUBLIC']).default('PRIVATE'),
  reservationPolicy: z.enum(['AUTO_CONFIRM', 'REQUEST_APPROVAL']).default('AUTO_CONFIRM'),
  reservationOpenDaysBefore: z.number().int().min(0).max(365).default(30),
  reservationOpenHoursBefore: z.number().int().min(0).max(23).default(0),
  reservationCancelDeadlineMinutes: z.number().int().min(0).max(10080).default(120),
});

const addOrganizationMemberSchema = z.object({
  userId: z.string().uuid(),
  role: z.enum(['OWNER', 'MANAGER', 'STAFF', 'VIEWER']).default('STAFF'),
});

const updateOrganizationMemberSchema = z.object({
  role: z.enum(['OWNER', 'MANAGER', 'STAFF', 'VIEWER']),
});

const reviewJoinRequestSchema = z.object({
  action: z.enum(['APPROVE', 'REJECT']),
  role: z.enum(['MANAGER', 'STAFF', 'VIEWER']).optional(),
});

const updateUserSchema = z.object({
  name: z.string().min(1).max(80).optional(),
  email: z.string().email().optional(),
  phone: z.string().max(30).nullable().optional(),
  bookingMode: z.enum(['PRIVATE', 'PUBLIC']).optional(),
  reservationPolicy: z.enum(['AUTO_CONFIRM', 'REQUEST_APPROVAL']).optional(),
  reservationOpenDaysBefore: z.number().int().min(0).max(365).optional(),
  reservationOpenHoursBefore: z.number().int().min(0).max(23).optional(),
  reservationCancelDeadlineMinutes: z.number().int().min(0).max(10080).optional(),
});

const createUserSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6).max(100),
  name: z.string().min(1).max(80),
  phone: z.string().max(30).nullable().optional(),
});

const updateMemberAccountSchema = z.object({
  name: z.string().min(1).max(80).optional(),
  email: z.string().email().optional(),
});

const createMemberAccountSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6).max(100),
  name: z.string().min(1).max(80),
});

function buildInviteCode() {
  return Math.random().toString(36).substring(2, 8).toUpperCase();
}

async function generateUniqueInviteCode() {
  for (let attempt = 0; attempt < 10; attempt += 1) {
    const inviteCode = buildInviteCode();
    const existing = await prisma.organization.findUnique({
      where: { inviteCode },
      select: { id: true },
    });
    if (!existing) {
      return inviteCode;
    }
  }
  throw new Error('Failed to generate unique invite code');
}

async function ensureOrganizationHasAnotherOwner(
  organizationId: string,
  excludingUserId: string,
) {
  const ownerCount = await prisma.orgMembership.count({
    where: {
      organizationId,
      role: 'OWNER',
      userId: { not: excludingUserId },
    },
  });
  return ownerCount > 0;
}

function mapOrganizationSummary(
  organization: Prisma.OrganizationGetPayload<{
    include: {
      _count: {
        select: {
          memberships: true;
          members: true;
          packages: true;
          reservations: true;
        };
      };
      memberships: {
        include: {
          user: {
            select: {
              id: true;
              name: true;
              email: true;
            };
          };
        };
      };
    };
  }>,
) {
  return {
    id: organization.id,
    name: organization.name,
    description: organization.description,
    inviteCode: organization.inviteCode,
    planType: organization.planType,
    maxAdminCount: organization.maxAdminCount,
    maxMemberCount: organization.maxMemberCount,
    bookingMode: organization.bookingMode,
    reservationPolicy: organization.reservationPolicy,
    reservationOpenDaysBefore: organization.reservationOpenDaysBefore,
    reservationOpenHoursBefore: organization.reservationOpenHoursBefore,
    reservationCancelDeadlineMinutes: organization.reservationCancelDeadlineMinutes,
    createdAt: organization.createdAt.toISOString(),
    updatedAt: organization.updatedAt.toISOString(),
    counts: {
      admins: organization._count.memberships,
      members: organization._count.members,
      packages: organization._count.packages,
      reservations: organization._count.reservations,
    },
    memberships: organization.memberships.map((membership) => ({
      id: membership.id,
      role: membership.role,
      createdAt: membership.createdAt.toISOString(),
      user: {
        id: membership.user.id,
        name: membership.user.name,
        email: membership.user.email,
        isSuperAdmin: isSuperAdminEmail(membership.user.email),
      },
    })),
  };
}

function mapJoinRequest(
  request: Prisma.CenterJoinRequestGetPayload<{
    include: {
      user: {
        select: {
          id: true;
          name: true;
          email: true;
        };
      };
    };
  }>,
) {
  return {
    id: request.id,
    status: request.status,
    message: request.message,
    createdAt: request.createdAt.toISOString(),
    user: {
      id: request.user.id,
      name: request.user.name,
      email: request.user.email,
      isSuperAdmin: isSuperAdminEmail(request.user.email),
    },
  };
}

function mapUserSummary(
  user: Prisma.UserGetPayload<{
    include: {
      memberships: {
        include: {
          organization: {
            select: {
              id: true;
              name: true;
            };
          };
        };
      };
    };
  }>,
) {
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    phone: user.phone,
    profileImage: user.profileImage,
    bookingMode: user.bookingMode,
    reservationPolicy: user.reservationPolicy,
    reservationOpenDaysBefore: user.reservationOpenDaysBefore,
    reservationOpenHoursBefore: user.reservationOpenHoursBefore,
    reservationCancelDeadlineMinutes: user.reservationCancelDeadlineMinutes,
    isSuperAdmin: isSuperAdminEmail(user.email),
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
    memberships: user.memberships.map((membership) => ({
      id: membership.id,
      role: membership.role,
      createdAt: membership.createdAt.toISOString(),
      organization: {
        id: membership.organization.id,
        name: membership.organization.name,
      },
    })),
  };
}

function mapMemberAccountSummary(
  account: Prisma.MemberAccountGetPayload<{
    include: {
      members: {
        include: {
          organization: {
            select: {
              id: true;
              name: true;
            };
          };
        };
      };
    };
  }>,
) {
  return {
    id: account.id,
    email: account.email,
    name: account.name,
    createdAt: account.createdAt.toISOString(),
    updatedAt: account.updatedAt.toISOString(),
    linkedMembers: account.members.map((member) => ({
      id: member.id,
      name: member.name,
      status: member.status,
      organization: {
        id: member.organization.id,
        name: member.organization.name,
      },
    })),
  };
}

router.get('/dashboard', async (_req: Request, res: Response) => {
  try {
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const since = new Date(todayStart);
    since.setDate(since.getDate() - 6); // 오늘 포함 최근 7일
    const tomorrowStart = new Date(todayStart);
    tomorrowStart.setDate(tomorrowStart.getDate() + 1);

    const [
      organizationCount,
      userCount,
      memberCount,
      memberAccountCount,
      pendingJoinRequestCount,
      todayUserCount,
      todayMemberAccountCount,
      todayReservationCount,
      reservationsLast7Raw,
      recentUsers,
      recentMemberAccounts,
      latestUsers,
      latestMemberAccounts,
      latestOrganizations,
    ] = await Promise.all([
      prisma.organization.count(),
      prisma.user.count(),
      prisma.member.count(),
      prisma.memberAccount.count(),
      prisma.centerJoinRequest.count({ where: { status: 'PENDING' } }),
      prisma.user.count({ where: { createdAt: { gte: todayStart } } }),
      prisma.memberAccount.count({ where: { createdAt: { gte: todayStart } } }),
      prisma.reservation.count({
        where: { date: { gte: todayStart, lt: tomorrowStart } },
      }),
      prisma.reservation.findMany({
        where: { date: { gte: since } },
        select: { date: true },
      }),
      prisma.user.findMany({
        where: { createdAt: { gte: since } },
        select: { createdAt: true },
      }),
      prisma.memberAccount.findMany({
        where: { createdAt: { gte: since } },
        select: { createdAt: true },
      }),
      prisma.user.findMany({
        orderBy: { createdAt: 'desc' },
        take: 5,
        select: {
          id: true,
          name: true,
          email: true,
          createdAt: true,
        },
      }),
      prisma.memberAccount.findMany({
        orderBy: { createdAt: 'desc' },
        take: 5,
        select: {
          id: true,
          name: true,
          email: true,
          createdAt: true,
        },
      }),
      prisma.organization.findMany({
        orderBy: { createdAt: 'desc' },
        take: 5,
        select: {
          id: true,
          name: true,
          planType: true,
          createdAt: true,
          _count: { select: { memberships: true, members: true } },
        },
      }),
    ]);

    const dayKey = (d: Date) => {
      const y = d.getFullYear();
      const m = String(d.getMonth() + 1).padStart(2, '0');
      const day = String(d.getDate()).padStart(2, '0');
      return `${y}-${m}-${day}`;
    };
    const makeBuckets = () => {
      const buckets = new Map<string, number>();
      for (let i = 0; i < 7; i++) {
        const d = new Date(since);
        d.setDate(since.getDate() + i);
        buckets.set(dayKey(d), 0);
      }
      return buckets;
    };
    const signupBuckets = makeBuckets();
    for (const row of [...recentUsers, ...recentMemberAccounts]) {
      const key = dayKey(row.createdAt);
      if (signupBuckets.has(key)) {
        signupBuckets.set(key, (signupBuckets.get(key) ?? 0) + 1);
      }
    }
    const reservationBuckets = makeBuckets();
    for (const row of reservationsLast7Raw) {
      const key = dayKey(row.date);
      if (reservationBuckets.has(key)) {
        reservationBuckets.set(key, (reservationBuckets.get(key) ?? 0) + 1);
      }
    }

    res.json({
      organizationCount,
      userCount,
      memberCount,
      memberAccountCount,
      pendingJoinRequestCount,
      todaySignupCount: todayUserCount + todayMemberAccountCount,
      todayUserCount,
      todayMemberAccountCount,
      todayReservationCount,
      signupsLast7Days: Array.from(signupBuckets.entries()).map(
        ([date, count]) => ({ date, count }),
      ),
      reservationsLast7Days: Array.from(reservationBuckets.entries()).map(
        ([date, count]) => ({ date, count }),
      ),
      latestUsers: latestUsers.map((u) => ({
        id: u.id,
        name: u.name,
        email: u.email,
        createdAt: u.createdAt.toISOString(),
      })),
      latestMemberAccounts: latestMemberAccounts.map((m) => ({
        id: m.id,
        name: m.name,
        email: m.email,
        createdAt: m.createdAt.toISOString(),
      })),
      latestOrganizations: latestOrganizations.map((o) => ({
        id: o.id,
        name: o.name,
        planType: o.planType,
        adminCount: o._count.memberships,
        memberCount: o._count.members,
        createdAt: o.createdAt.toISOString(),
      })),
    });
  } catch (err) {
    console.error('Admin dashboard error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/reports/overview', async (_req: Request, res: Response) => {
  try {
    const [
      organizations,
      users,
      reservations,
      sessions,
      memberPackages,
      pendingJoinRequests,
    ] = await Promise.all([
      prisma.organization.findMany({
        include: {
          memberships: {
            select: {
              role: true,
              userId: true,
              user: { select: { name: true } },
            },
          },
          members: {
            where: { status: 'ACTIVE' },
            select: { id: true },
          },
        },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.user.findMany({
        include: {
          memberships: {
            include: {
              organization: { select: { id: true, name: true } },
            },
          },
        },
        orderBy: { createdAt: 'desc' },
      }),
      prisma.reservation.findMany({
        select: {
          organizationId: true,
          coachId: true,
          status: true,
        },
      }),
      prisma.session.findMany({
        select: {
          organizationId: true,
          coachId: true,
          attendance: true,
        },
      }),
      prisma.memberPackage.findMany({
        select: {
          id: true,
          memberId: true,
          paidAmount: true,
          purchaseDate: true,
          member: { select: { organizationId: true } },
          package: { select: { coachId: true } },
        },
      }),
      prisma.centerJoinRequest.findMany({
        where: { status: 'PENDING' },
        select: { organizationId: true },
      }),
    ]);

    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    const centerSummaries = organizations.map((organization) => {
      const orgReservations = reservations.filter(
        (reservation) => reservation.organizationId === organization.id,
      );
      const orgSessions = sessions.filter(
        (session) => session.organizationId === organization.id,
      );
      const orgPackages = memberPackages.filter(
        (memberPackage) =>
          memberPackage.member.organizationId === organization.id,
      );
      const pendingRequests = pendingJoinRequests.filter(
        (request) => request.organizationId === organization.id,
      );

      return {
        id: organization.id,
        name: organization.name,
        planType: organization.planType,
        inviteCode: organization.inviteCode,
        memberCount: organization.members.length,
        adminCount: organization.memberships.length,
        ownerCount: organization.memberships.filter((item) => item.role === 'OWNER').length,
        managerCount: organization.memberships.filter((item) => item.role === 'MANAGER').length,
        staffCount: organization.memberships.filter((item) => item.role === 'STAFF').length,
        viewerCount: organization.memberships.filter((item) => item.role === 'VIEWER').length,
        totalReservations: orgReservations.length,
        pendingReservations: orgReservations.filter((item) => item.status === 'PENDING').length,
        completedSessions: orgSessions.length,
        totalRevenue: orgPackages.reduce((sum, item) => sum + item.paidAmount, 0),
        monthRevenue: orgPackages
            .filter((item) => item.purchaseDate >= monthStart)
            .reduce((sum, item) => sum + item.paidAmount, 0),
        soldPackageCount: orgPackages.length,
        pendingJoinRequestCount: pendingRequests.length,
      };
    });

    const userSummaries = users.map((user) => {
      const userReservations = reservations.filter(
        (reservation) => reservation.coachId === user.id,
      );
      const userSessions = sessions.filter((session) => session.coachId === user.id);
      const userPackages = memberPackages.filter(
        (memberPackage) => memberPackage.package.coachId === user.id,
      );

      return {
        id: user.id,
        name: user.name,
        email: user.email,
        isSuperAdmin: isSuperAdminEmail(user.email),
        centerCount: user.memberships.length,
        centers: user.memberships.map((membership) => ({
          id: membership.organization.id,
          name: membership.organization.name,
          role: membership.role,
        })),
        totalReservations: userReservations.length,
        pendingReservations: userReservations.filter((item) => item.status === 'PENDING').length,
        totalSessions: userSessions.length,
        noShowSessions: userSessions.filter((item) => item.attendance === 'NO_SHOW').length,
        lateSessions: userSessions.filter((item) => item.attendance === 'LATE').length,
        adminPackageSalesCount: userPackages.length,
        adminPackageRevenue: userPackages.reduce((sum, item) => sum + item.paidAmount, 0),
        monthAdminPackageRevenue: userPackages
            .filter((item) => item.purchaseDate >= monthStart)
            .reduce((sum, item) => sum + item.paidAmount, 0),
      };
    });

    res.json({
      generatedAt: now.toISOString(),
      centers: centerSummaries,
      users: userSummaries,
    });
  } catch (err) {
    console.error('Admin reports overview error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/organizations', async (req: Request, res: Response) => {
  try {
    const body = createOrganizationSchema.parse(req.body);

    const owner = await prisma.user.findUnique({
      where: { id: body.ownerUserId },
      select: { id: true },
    });
    if (!owner) {
      res.status(404).json({ error: 'Owner user not found' });
      return;
    }

    const inviteCode = await generateUniqueInviteCode();
    const created = await prisma.$transaction(async (tx) => {
      const organization = await tx.organization.create({
        data: {
          name: body.name,
          description: body.description ?? null,
          inviteCode,
          planType: body.planType,
          maxAdminCount: body.maxAdminCount,
          maxMemberCount: body.maxMemberCount,
          bookingMode: body.bookingMode,
          reservationPolicy: body.reservationPolicy,
          reservationOpenDaysBefore: body.reservationOpenDaysBefore,
          reservationOpenHoursBefore: body.reservationOpenHoursBefore,
          reservationCancelDeadlineMinutes: body.reservationCancelDeadlineMinutes,
        },
      });

      await tx.orgMembership.create({
        data: {
          userId: body.ownerUserId,
          organizationId: organization.id,
          role: 'OWNER',
        },
      });

      return tx.organization.findUniqueOrThrow({
        where: { id: organization.id },
        include: {
          _count: {
            select: {
              memberships: true,
              members: true,
              packages: true,
              reservations: true,
            },
          },
          memberships: {
            include: {
              user: { select: { id: true, name: true, email: true } },
            },
            orderBy: { createdAt: 'asc' },
          },
        },
      });
    });

    res.status(201).json(mapOrganizationSummary(created));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin create organization error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/organizations/:id', async (req: Request, res: Response) => {
  try {
    const organizationId = req.params.id as string;
    const organization = await prisma.organization.findUnique({
      where: { id: organizationId },
      select: { id: true, name: true },
    });
    if (!organization) {
      res.status(404).json({ error: 'Organization not found' });
      return;
    }

    await prisma.organization.delete({ where: { id: organizationId } });
    res.json({ message: `${organization.name} deleted` });
  } catch (err) {
    console.error('Admin delete organization error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/organizations', async (req: Request, res: Response) => {
  try {
    const query = searchQuerySchema.parse(req.query);
    const search = query.search?.trim();
    const where: Prisma.OrganizationWhereInput = search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { description: { contains: search, mode: 'insensitive' } },
            { inviteCode: { contains: search, mode: 'insensitive' } },
          ],
        }
      : {};

    const organizations = await prisma.organization.findMany({
      where,
      include: {
        _count: {
          select: {
            memberships: true,
            members: true,
            packages: true,
            reservations: true,
          },
        },
        memberships: {
          include: {
            user: {
              select: { id: true, name: true, email: true },
            },
          },
          orderBy: { createdAt: 'asc' },
        },
      },
      orderBy: [{ createdAt: 'desc' }],
    });

    res.json({
      organizations: organizations.map(mapOrganizationSummary),
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin list organizations error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/organizations/:id', async (req: Request, res: Response) => {
  try {
    const organization = await prisma.organization.findUnique({
      where: { id: req.params.id as string },
      include: {
        _count: {
          select: {
            memberships: true,
            members: true,
            packages: true,
            reservations: true,
          },
        },
        memberships: {
          include: {
            user: {
              select: { id: true, name: true, email: true },
            },
          },
          orderBy: [{ role: 'asc' }, { createdAt: 'asc' }],
        },
      },
    });

    if (!organization) {
      res.status(404).json({ error: 'Organization not found' });
      return;
    }

    res.json(mapOrganizationSummary(organization));
  } catch (err) {
    console.error('Admin organization detail error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/organizations/:id', async (req: Request, res: Response) => {
  try {
    const body = updateOrganizationSchema.parse(req.body);
    const updated = await prisma.organization.update({
      where: { id: req.params.id as string },
      data: body,
      include: {
        _count: {
          select: {
            memberships: true,
            members: true,
            packages: true,
            reservations: true,
          },
        },
        memberships: {
          include: {
            user: {
              select: { id: true, name: true, email: true },
            },
          },
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    res.json(mapOrganizationSummary(updated));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin update organization error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/organizations/:id/join-requests', async (req: Request, res: Response) => {
  try {
    const requests = await prisma.centerJoinRequest.findMany({
      where: {
        organizationId: req.params.id as string,
        status: 'PENDING',
      },
      include: {
        user: { select: { id: true, name: true, email: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    res.json({ requests: requests.map(mapJoinRequest) });
  } catch (err) {
    console.error('Admin organization join requests error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/organizations/:id/join-requests/:requestId', async (req: Request, res: Response) => {
  try {
    const body = reviewJoinRequestSchema.parse(req.body);
    const organizationId = req.params.id as string;
    const requestId = req.params.requestId as string;

    const request = await prisma.centerJoinRequest.findFirst({
      where: { id: requestId, organizationId, status: 'PENDING' },
    });
    if (!request) {
      res.status(404).json({ error: 'Join request not found' });
      return;
    }

    if (body.action === 'APPROVE') {
      const withinLimit = await checkAdminLimit(organizationId);
      if (!withinLimit) {
        res.status(409).json({ error: 'Center has reached maximum admin count' });
        return;
      }

      await prisma.$transaction(async (tx) => {
        await tx.centerJoinRequest.update({
          where: { id: requestId },
          data: { status: 'APPROVED', reviewedBy: null, reviewedAt: new Date() },
        });
        await tx.orgMembership.upsert({
          where: {
            userId_organizationId: {
              userId: request.userId,
              organizationId,
            },
          },
          create: {
            userId: request.userId,
            organizationId,
            role: body.role ?? 'STAFF',
          },
          update: { role: body.role ?? 'STAFF' },
        });
      });
    } else {
      await prisma.centerJoinRequest.update({
        where: { id: requestId },
        data: { status: 'REJECTED', reviewedBy: null, reviewedAt: new Date() },
      });
    }

    res.json({ message: body.action === 'APPROVE' ? 'Approved' : 'Rejected' });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin review join request error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/organizations/:id/members', async (req: Request, res: Response) => {
  try {
    const body = addOrganizationMemberSchema.parse(req.body);
    const organizationId = req.params.id as string;

    const organization = await prisma.organization.findUnique({
      where: { id: organizationId },
      select: { id: true },
    });
    if (!organization) {
      res.status(404).json({ error: 'Organization not found' });
      return;
    }

    const user = await prisma.user.findUnique({
      where: { id: body.userId },
      select: { id: true },
    });
    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const existing = await prisma.orgMembership.findUnique({
      where: {
        userId_organizationId: {
          userId: body.userId,
          organizationId,
        },
      },
    });
    if (existing) {
      res.status(409).json({ error: 'User is already a member of this center' });
      return;
    }

    const withinLimit = await checkAdminLimit(organizationId);
    if (!withinLimit) {
      res.status(409).json({ error: 'Center has reached maximum admin count' });
      return;
    }

    await prisma.orgMembership.create({
      data: {
        userId: body.userId,
        organizationId,
        role: body.role,
      },
    });

    const refreshed = await prisma.organization.findUniqueOrThrow({
      where: { id: organizationId },
      include: {
        _count: {
          select: {
            memberships: true,
            members: true,
            packages: true,
            reservations: true,
          },
        },
        memberships: {
          include: {
            user: { select: { id: true, name: true, email: true } },
          },
          orderBy: [{ role: 'asc' }, { createdAt: 'asc' }],
        },
      },
    });

    res.status(201).json(mapOrganizationSummary(refreshed));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin add organization member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/organizations/:id/members/:userId', async (req: Request, res: Response) => {
  try {
    const body = updateOrganizationMemberSchema.parse(req.body);
    const organizationId = req.params.id as string;
    const userId = req.params.userId as string;

    const membership = await prisma.orgMembership.findUnique({
      where: {
        userId_organizationId: {
          userId,
          organizationId,
        },
      },
    });
    if (!membership) {
      res.status(404).json({ error: 'Membership not found' });
      return;
    }

    if (membership.role === 'OWNER' && body.role != 'OWNER') {
      const hasAnotherOwner = await ensureOrganizationHasAnotherOwner(
        organizationId,
        userId,
      );
      if (!hasAnotherOwner) {
        res.status(409).json({ error: 'Center must keep at least one owner' });
        return;
      }
    }

    await prisma.orgMembership.update({
      where: { id: membership.id },
      data: { role: body.role },
    });

    const refreshed = await prisma.organization.findUniqueOrThrow({
      where: { id: organizationId },
      include: {
        _count: {
          select: {
            memberships: true,
            members: true,
            packages: true,
            reservations: true,
          },
        },
        memberships: {
          include: {
            user: { select: { id: true, name: true, email: true } },
          },
          orderBy: [{ role: 'asc' }, { createdAt: 'asc' }],
        },
      },
    });

    res.json(mapOrganizationSummary(refreshed));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin update organization member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/organizations/:id/members/:userId', async (req: Request, res: Response) => {
  try {
    const organizationId = req.params.id as string;
    const userId = req.params.userId as string;

    const membership = await prisma.orgMembership.findUnique({
      where: {
        userId_organizationId: {
          userId,
          organizationId,
        },
      },
    });
    if (!membership) {
      res.status(404).json({ error: 'Membership not found' });
      return;
    }

    if (membership.role === 'OWNER') {
      const hasAnotherOwner = await ensureOrganizationHasAnotherOwner(
        organizationId,
        userId,
      );
      if (!hasAnotherOwner) {
        res.status(409).json({ error: 'Center must keep at least one owner' });
        return;
      }
    }

    await prisma.orgMembership.delete({ where: { id: membership.id } });

    const refreshed = await prisma.organization.findUniqueOrThrow({
      where: { id: organizationId },
      include: {
        _count: {
          select: {
            memberships: true,
            members: true,
            packages: true,
            reservations: true,
          },
        },
        memberships: {
          include: {
            user: { select: { id: true, name: true, email: true } },
          },
          orderBy: [{ role: 'asc' }, { createdAt: 'asc' }],
        },
      },
    });

    res.json(mapOrganizationSummary(refreshed));
  } catch (err) {
    console.error('Admin remove organization member error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/users', async (req: Request, res: Response) => {
  try {
    const body = createUserSchema.parse(req.body);
    const existing = await prisma.user.findUnique({
      where: { email: body.email },
      select: { id: true },
    });
    if (existing) {
      res.status(409).json({ error: 'Email already registered' });
      return;
    }

    const hashedPassword = await bcrypt.hash(body.password, 12);
    const created = await prisma.user.create({
      data: {
        email: body.email,
        password: hashedPassword,
        name: body.name,
        phone: body.phone ?? null,
      },
      include: {
        memberships: {
          include: {
            organization: { select: { id: true, name: true } },
          },
        },
      },
    });

    res.status(201).json(mapUserSummary(created));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin create user error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/users', async (req: Request, res: Response) => {
  try {
    const query = searchQuerySchema.parse(req.query);
    const search = query.search?.trim();
    const where: Prisma.UserWhereInput = search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { email: { contains: search, mode: 'insensitive' } },
            { phone: { contains: search } },
          ],
        }
      : {};

    const users = await prisma.user.findMany({
      where,
      include: {
        memberships: {
          include: {
            organization: {
              select: { id: true, name: true },
            },
          },
          orderBy: { createdAt: 'asc' },
        },
      },
      orderBy: [{ createdAt: 'desc' }],
    });

    res.json({
      users: users.map(mapUserSummary),
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin list users error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/users/:id', async (req: Request, res: Response) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.params.id as string },
      include: {
        memberships: {
          include: {
            organization: {
              select: { id: true, name: true },
            },
          },
          orderBy: [{ role: 'asc' }, { createdAt: 'asc' }],
        },
      },
    });

    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    res.json(mapUserSummary(user));
  } catch (err) {
    console.error('Admin user detail error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/users/:id', async (req: Request, res: Response) => {
  try {
    const body = updateUserSchema.parse(req.body);
    if (body.email) {
      const existing = await prisma.user.findUnique({
        where: { email: body.email },
        select: { id: true },
      });
      if (existing && existing.id !== (req.params.id as string)) {
        res.status(409).json({ error: 'Email already registered' });
        return;
      }
    }

    const updated = await prisma.user.update({
      where: { id: req.params.id as string },
      data: body,
      include: {
        memberships: {
          include: {
            organization: {
              select: { id: true, name: true },
            },
          },
          orderBy: { createdAt: 'asc' },
        },
      },
    });

    res.json(mapUserSummary(updated));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin update user error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/users/:id', async (req: Request, res: Response) => {
  try {
    const userId = req.params.id as string;

    const result = await deleteUserAccount(userId);
    res.json(result);
  } catch (err) {
    if (err instanceof Error && err.message === 'LAST_ORG_ADMIN') {
      res.status(409).json({
        error: '조직에 남은 관리자 또는 오너가 없어 관리자 계정을 삭제할 수 없습니다',
      });
      return;
    }
    console.error('Admin delete user error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/member-accounts', async (req: Request, res: Response) => {
  try {
    const body = createMemberAccountSchema.parse(req.body);
    const existing = await prisma.memberAccount.findUnique({
      where: { email: body.email },
      select: { id: true },
    });
    if (existing) {
      res.status(409).json({ error: 'Email already registered' });
      return;
    }

    const hashedPassword = await bcrypt.hash(body.password, 12);
    const created = await prisma.memberAccount.create({
      data: {
        email: body.email,
        password: hashedPassword,
        name: body.name,
      },
      include: {
        members: {
          include: {
            organization: { select: { id: true, name: true } },
          },
        },
      },
    });

    res.status(201).json(mapMemberAccountSummary(created));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin create member account error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/member-accounts', async (req: Request, res: Response) => {
  try {
    const query = searchQuerySchema.parse(req.query);
    const search = query.search?.trim();
    const where: Prisma.MemberAccountWhereInput = search
      ? {
          OR: [
            { name: { contains: search, mode: 'insensitive' } },
            { email: { contains: search, mode: 'insensitive' } },
          ],
        }
      : {};

    const accounts = await prisma.memberAccount.findMany({
      where,
      include: {
        members: {
          include: {
            organization: { select: { id: true, name: true } },
          },
          orderBy: { createdAt: 'asc' },
        },
      },
      orderBy: [{ createdAt: 'desc' }],
    });

    res.json({
      memberAccounts: accounts.map(mapMemberAccountSummary),
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin list member accounts error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/member-accounts/:id', async (req: Request, res: Response) => {
  try {
    const account = await prisma.memberAccount.findUnique({
      where: { id: req.params.id as string },
      include: {
        members: {
          include: {
            organization: { select: { id: true, name: true } },
          },
          orderBy: [{ organizationId: 'asc' }, { name: 'asc' }],
        },
      },
    });

    if (!account) {
      res.status(404).json({ error: 'Member account not found' });
      return;
    }

    res.json(mapMemberAccountSummary(account));
  } catch (err) {
    console.error('Admin member account detail error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/member-accounts/:id', async (req: Request, res: Response) => {
  try {
    const body = updateMemberAccountSchema.parse(req.body);
    if (body.email) {
      const existing = await prisma.memberAccount.findUnique({
        where: { email: body.email },
        select: { id: true },
      });
      if (existing && existing.id !== (req.params.id as string)) {
        res.status(409).json({ error: 'Email already registered' });
        return;
      }
    }

    const updated = await prisma.memberAccount.update({
      where: { id: req.params.id as string },
      data: body,
      include: {
        members: {
          include: {
            organization: { select: { id: true, name: true } },
          },
          orderBy: [{ organizationId: 'asc' }, { name: 'asc' }],
        },
      },
    });

    res.json(mapMemberAccountSummary(updated));
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Admin update member account error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/member-accounts/:id', async (req: Request, res: Response) => {
  try {
    const result = await deleteMemberAccount(req.params.id as string);
    res.json(result);
  } catch (err) {
    console.error('Admin delete member account error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
