import { Router, Request, Response } from 'express';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { addDays, getKstMonthStart, getKstToday, parseDateOnly } from '../utils/kst-date';
import { deriveMemberPackageStatus } from '../utils/member-package-status';
import { listMemberPackagesCompat } from '../utils/member-package-access';
import { requireCurrentOrgId } from './_shared';

const router = Router();
router.use(authMiddleware);

// ─── Revenue Report ────────────────────────────────────────
router.get('/revenue', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const { startDate, endDate } = req.query;
    if (!startDate || !endDate) {
      res.status(400).json({ error: 'startDate and endDate required' });
      return;
    }

    const memberPackages = await prisma.memberPackage.findMany({
      where: {
        member: { organizationId: orgId },
        purchaseDate: {
          gte: parseDateOnly(startDate as string),
          lt: parseDateOnly(addDays(endDate as string, 1)),
        },
      },
      include: { package: true, member: { select: { name: true } } },
      orderBy: [
        { purchaseDate: 'desc' },
        { createdAt: 'desc' },
      ],
    });

    const totalRevenue = memberPackages.reduce((sum, mp) => sum + mp.paidAmount, 0);
    const byMethod = memberPackages.reduce(
      (acc, mp) => {
        acc[mp.paymentMethod] = (acc[mp.paymentMethod] || 0) + mp.paidAmount;
        return acc;
      },
      {} as Record<string, number>,
    );

    res.json({
      totalRevenue,
      byMethod,
      count: memberPackages.length,
      details: memberPackages,
    });
  } catch (err) {
    console.error('Revenue report error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Attendance Report ─────────────────────────────────────
router.get('/attendance', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const { startDate, endDate } = req.query;
    if (!startDate || !endDate) {
      res.status(400).json({ error: 'startDate and endDate required' });
      return;
    }

    const sessions = await prisma.session.findMany({
      where: {
        organizationId: orgId,
        date: {
          gte: parseDateOnly(startDate as string),
          lt: parseDateOnly(addDays(endDate as string, 1)),
        },
      },
    });

    const byAttendance = sessions.reduce(
      (acc, s) => {
        acc[s.attendance] = (acc[s.attendance] || 0) + 1;
        return acc;
      },
      {} as Record<string, number>,
    );

    res.json({
      total: sessions.length,
      byAttendance,
    });
  } catch (err) {
    console.error('Attendance report error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Dashboard Stats ───────────────────────────────────────
router.get('/dashboard', async (req: Request, res: Response) => {
  try {
    const orgId = await requireCurrentOrgId(req, res);
    if (!orgId) return;

    const todayDate = getKstToday();
    const today = parseDateOnly(todayDate);
    const tomorrow = parseDateOnly(addDays(todayDate, 1));

    const [
      members,
      todayReservations,
      pendingReservations,
      todaySessions,
    ] = await Promise.all([
      prisma.member.findMany({
        where: { organizationId: orgId },
        select: { id: true },
      }),
      prisma.reservation.findMany({
        where: { organizationId: orgId, date: { gte: today, lt: tomorrow }, status: { in: ['CONFIRMED', 'PENDING'] } },
        include: { member: { select: { name: true } }, coach: { select: { name: true } } },
        orderBy: { startTime: 'asc' },
      }),
      prisma.reservation.count({ where: { organizationId: orgId, status: 'PENDING' } }),
      prisma.session.count({ where: { organizationId: orgId, date: { gte: today, lt: tomorrow } } }),
    ]);

    const totalMembers = members.length;
    const memberPackages = await listMemberPackagesCompat({
      memberIds: members.map((member) => member.id),
      organizationId: orgId,
    });
    const packagesByMemberId = new Map<string, any[]>();
    for (const memberPackage of memberPackages) {
      const current = packagesByMemberId.get(memberPackage.memberId) ?? [];
      current.push(memberPackage);
      packagesByMemberId.set(memberPackage.memberId, current);
    }
    const activeMembers = members.filter((member) => (
      deriveMemberPackageStatus(packagesByMemberId.get(member.id) ?? []).packageStatus === 'PACKAGE_ACTIVE'
    )).length;

    const monthRevenue = await prisma.memberPackage.aggregate({
      where: {
        member: { organizationId: orgId },
        purchaseDate: { gte: parseDateOnly(getKstMonthStart(todayDate)), lt: tomorrow },
      },
      _sum: { paidAmount: true },
    });

    res.json({
      totalMembers,
      activeMembers,
      todayReservations,
      pendingReservations,
      todaySessions,
      monthRevenue: monthRevenue._sum.paidAmount || 0,
    });
  } catch (err) {
    console.error('Dashboard error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
