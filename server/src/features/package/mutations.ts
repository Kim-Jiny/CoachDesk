import { prisma } from '../../utils/prisma';
import { shouldSendPushForType } from '../../utils/notification-preferences';
import { addDays, formatDateOnly, parseDateOnly } from '../../utils/kst-date';
import {
  findMemberPackageCompat,
  updateMemberPackagePauseCompat,
} from '../../utils/member-package-access';
import { sendPush } from '../../utils/firebase';

function calculatePauseDays(startDate: string, endDate: string) {
  const start = parseDateOnly(startDate);
  const end = parseDateOnly(endDate);
  const diffMs = end.getTime() - start.getTime();
  return Math.floor(diffMs / (24 * 60 * 60 * 1000)) + 1;
}

function extendDate(date: Date, days: number) {
  return parseDateOnly(addDays(formatDateOnly(date), days));
}

export class PackageMutationError extends Error {
  constructor(
    public readonly code:
      | 'PACKAGE_NOT_FOUND'
      | 'MEMBER_NOT_FOUND'
      | 'MEMBER_PACKAGE_NOT_FOUND'
      | 'NO_PENDING_PAUSE_REQUEST',
  ) {
    super(code);
  }
}

export async function createPackage(params: {
  organizationId: string;
  name: string;
  totalSessions: number;
  price: number;
  validDays?: number;
  isActive?: boolean;
  isPublic?: boolean;
}) {
  return prisma.package.create({
    data: {
      organizationId: params.organizationId,
      name: params.name,
      totalSessions: params.totalSessions,
      price: params.price,
      validDays: params.validDays,
      isActive: params.isActive,
      isPublic: params.isPublic,
    },
  });
}

export async function updatePackage(params: {
  organizationId: string;
  packageId: string;
  name?: string;
  totalSessions?: number;
  price?: number;
  validDays?: number;
  isActive?: boolean;
  isPublic?: boolean;
}) {
  const existingPackage = await prisma.package.findFirst({
    where: { id: params.packageId, organizationId: params.organizationId },
    select: { id: true },
  });
  if (!existingPackage) {
    throw new PackageMutationError('PACKAGE_NOT_FOUND');
  }

  return prisma.package.update({
    where: { id: existingPackage.id },
    data: {
      name: params.name,
      totalSessions: params.totalSessions,
      price: params.price,
      validDays: params.validDays,
      isActive: params.isActive,
      isPublic: params.isPublic,
    },
  });
}

export async function assignPackageToMember(params: {
  organizationId: string;
  memberId: string;
  packageId: string;
  paidAmount: number;
  paymentMethod: 'CASH' | 'CARD' | 'TRANSFER';
}) {
  const [pkg, member] = await Promise.all([
    prisma.package.findFirst({
      where: { id: params.packageId, organizationId: params.organizationId },
    }),
    prisma.member.findFirst({
      where: { id: params.memberId, organizationId: params.organizationId },
      select: { id: true },
    }),
  ]);
  if (!pkg) {
    throw new PackageMutationError('PACKAGE_NOT_FOUND');
  }
  if (!member) {
    throw new PackageMutationError('MEMBER_NOT_FOUND');
  }

  const expiryDate = pkg.validDays
    ? new Date(Date.now() + pkg.validDays * 24 * 60 * 60 * 1000)
    : undefined;

  return prisma.memberPackage.create({
    data: {
      memberId: params.memberId,
      packageId: params.packageId,
      totalSessions: pkg.totalSessions,
      remainingSessions: pkg.totalSessions,
      paidAmount: params.paidAmount,
      paymentMethod: params.paymentMethod,
      expiryDate,
    },
    include: { package: true },
  });
}

export async function approvePauseRequest(params: {
  organizationId: string;
  memberPackageId: string;
}) {
  const memberPackage = await findMemberPackageCompat({
    id: params.memberPackageId,
    organizationId: params.organizationId,
  });
  if (!memberPackage) {
    throw new PackageMutationError('MEMBER_PACKAGE_NOT_FOUND');
  }

  if (
    memberPackage.pauseRequestStatus !== 'PENDING' ||
    !memberPackage.pauseRequestedStartDate ||
    !memberPackage.pauseRequestedEndDate
  ) {
    throw new PackageMutationError('NO_PENDING_PAUSE_REQUEST');
  }

  const startDate = formatDateOnly(new Date(memberPackage.pauseRequestedStartDate));
  const endDate = formatDateOnly(new Date(memberPackage.pauseRequestedEndDate));
  const extensionDays = calculatePauseDays(startDate, endDate);
  const nextExpiryDate = memberPackage.expiryDate
    ? extendDate(new Date(memberPackage.expiryDate), extensionDays)
    : null;

  await updateMemberPackagePauseCompat(memberPackage.id, {
    pauseStartDate: parseDateOnly(startDate),
    pauseEndDate: parseDateOnly(endDate),
    pauseRequestedStartDate: null,
    pauseRequestedEndDate: null,
    pauseRequestStatus: 'NONE',
    pauseExtensionDaysDelta: extensionDays,
    expiryDate: nextExpiryDate,
  });

  const updated = await findMemberPackageCompat({
    id: memberPackage.id,
    organizationId: params.organizationId,
  });

  const memberAccountId = memberPackage.member?.memberAccountId as
    | string
    | undefined;
  if (memberAccountId) {
    const pauseBody = `${startDate}부터 ${endDate}까지 정지 승인되었고, 만료일이 ${extensionDays}일 연장됩니다`;

    // Create notification record for member
    await prisma.notification.create({
      data: {
        memberAccountId,
        organizationId: params.organizationId,
        type: 'PACKAGE_PAUSE_APPROVED',
        title: '패키지 정지 승인',
        body: pauseBody,
        data: { memberPackageId: memberPackage.id },
      },
    });

    const memberAccount = await prisma.memberAccount.findUnique({
      where: { id: memberAccountId },
      select: { fcmToken: true, notificationPreferences: true },
    });
    if (
      memberAccount?.fcmToken &&
      shouldSendPushForType(
        memberAccount.notificationPreferences,
        'PACKAGE_PAUSE_APPROVED',
      )
    ) {
      await sendPush(
        memberAccount.fcmToken,
        '패키지 정지 승인',
        pauseBody,
        { type: 'PACKAGE_PAUSE_APPROVED', memberPackageId: memberPackage.id },
      );
    }
  }

  return {
    memberPackage: updated,
    extensionDays,
  };
}

export async function rejectPauseRequest(params: {
  organizationId: string;
  memberPackageId: string;
  note?: string;
}) {
  const memberPackage = await findMemberPackageCompat({
    id: params.memberPackageId,
    organizationId: params.organizationId,
  });
  if (!memberPackage) {
    throw new PackageMutationError('MEMBER_PACKAGE_NOT_FOUND');
  }

  if (memberPackage.pauseRequestStatus !== 'PENDING') {
    throw new PackageMutationError('NO_PENDING_PAUSE_REQUEST');
  }

  await updateMemberPackagePauseCompat(memberPackage.id, {
    pauseRequestedStartDate: null,
    pauseRequestedEndDate: null,
    pauseRequestStatus: 'NONE',
    pauseRequestReason: null,
  });

  const memberAccountId = memberPackage.member?.memberAccountId as
    | string
    | undefined;
  if (memberAccountId) {
    const rejectBody = (params.note?.trim().length ?? 0) > 0
      ? `정지 신청이 반려되었습니다: ${params.note!.trim()}`
      : '패키지 정지 신청이 반려되었습니다';

    // Create notification record for member
    await prisma.notification.create({
      data: {
        memberAccountId,
        organizationId: params.organizationId,
        type: 'PACKAGE_PAUSE_REJECTED',
        title: '패키지 정지 반려',
        body: rejectBody,
        data: { memberPackageId: memberPackage.id },
      },
    });

    const memberAccount = await prisma.memberAccount.findUnique({
      where: { id: memberAccountId },
      select: { fcmToken: true, notificationPreferences: true },
    });
    if (
      memberAccount?.fcmToken &&
      shouldSendPushForType(
        memberAccount.notificationPreferences,
        'PACKAGE_PAUSE_REJECTED',
      )
    ) {
      await sendPush(
        memberAccount.fcmToken,
        '패키지 정지 반려',
        rejectBody,
        { type: 'PACKAGE_PAUSE_REJECTED', memberPackageId: memberPackage.id },
      );
    }
  }
}
