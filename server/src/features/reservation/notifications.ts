import { prisma } from '../../utils/prisma';
import { sendPush } from '../../utils/firebase';
import { formatDateOnly } from '../../utils/kst-date';
import { shouldSendPushForType } from '../../utils/notification-preferences';

export function buildReservationStatusMessage(
  status: string,
  date: string,
  startTime: string,
) {
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

async function getMemberNotificationTarget(memberAccountId: string) {
  return prisma.memberAccount.findUnique({
    where: { id: memberAccountId },
    select: { fcmToken: true, notificationPreferences: true },
  });
}

async function createMemberNotification(params: {
  memberAccountId: string;
  organizationId?: string;
  type:
    | 'NEW_RESERVATION'
    | 'RESERVATION_CANCELLED'
    | 'RESERVATION_STATUS_UPDATED'
    | 'RESERVATION_DELAYED';
  title: string;
  body: string;
  reservationId: string;
}) {
  await prisma.notification.create({
    data: {
      memberAccountId: params.memberAccountId,
      organizationId: params.organizationId,
      type: params.type,
      title: params.title,
      body: params.body,
      data: { reservationId: params.reservationId },
    },
  });
}

async function safelyCreateMemberNotification(params: {
  memberAccountId: string;
  organizationId?: string;
  type:
    | 'NEW_RESERVATION'
    | 'RESERVATION_CANCELLED'
    | 'RESERVATION_STATUS_UPDATED'
    | 'RESERVATION_DELAYED';
  title: string;
  body: string;
  reservationId: string;
}) {
  try {
    await createMemberNotification(params);
  } catch (err) {
    console.error('Create member notification failed:', err);
  }
}

async function sendMemberPushIfEnabled(params: {
  memberAccountId: string;
  type:
    | 'NEW_RESERVATION'
    | 'RESERVATION_CANCELLED'
    | 'RESERVATION_STATUS_UPDATED'
    | 'RESERVATION_DELAYED';
  title: string;
  body: string;
  reservationId: string;
}) {
  const memberAccount = await getMemberNotificationTarget(params.memberAccountId);
  if (
    !memberAccount?.fcmToken ||
    !shouldSendPushForType(memberAccount.notificationPreferences, params.type)
  ) {
    return;
  }

  sendPush(memberAccount.fcmToken, params.title, params.body, {
    type: params.type,
    reservationId: params.reservationId,
  });
}

async function safelySendMemberPushIfEnabled(params: {
  memberAccountId: string;
  type:
    | 'NEW_RESERVATION'
    | 'RESERVATION_CANCELLED'
    | 'RESERVATION_STATUS_UPDATED'
    | 'RESERVATION_DELAYED';
  title: string;
  body: string;
  reservationId: string;
}) {
  try {
    await sendMemberPushIfEnabled(params);
  } catch (err) {
    console.error('Send member push failed:', err);
  }
}

export async function handleReservationCreatedNotification(params: {
  memberAccountId?: string | null;
  organizationId?: string;
  reservationId: string;
  date: string;
  startTime: string;
}) {
  if (!params.memberAccountId) return;

  const title = '새 예약 등록';
  const body = `${params.date} ${params.startTime} 예약이 등록되었습니다`;

  await safelyCreateMemberNotification({
    memberAccountId: params.memberAccountId,
    organizationId: params.organizationId,
    type: 'NEW_RESERVATION',
    title,
    body,
    reservationId: params.reservationId,
  });

  await safelySendMemberPushIfEnabled({
    memberAccountId: params.memberAccountId,
    type: 'NEW_RESERVATION',
    title,
    body,
    reservationId: params.reservationId,
  });
}

export async function handleReservationCancelledNotification(params: {
  memberAccountId?: string | null;
  organizationId?: string;
  reservationId: string;
  date: Date;
  startTime: string;
}) {
  if (!params.memberAccountId) return;

  const title = '예약 취소';
  const body = `${formatDateOnly(params.date)} ${params.startTime} 예약이 취소되었습니다`;

  await safelyCreateMemberNotification({
    memberAccountId: params.memberAccountId,
    organizationId: params.organizationId,
    type: 'RESERVATION_CANCELLED',
    title,
    body,
    reservationId: params.reservationId,
  });

  await safelySendMemberPushIfEnabled({
    memberAccountId: params.memberAccountId,
    type: 'RESERVATION_CANCELLED',
    title,
    body,
    reservationId: params.reservationId,
  });
}

export async function handleReservationStatusUpdatedNotification(params: {
  memberAccountId?: string | null;
  organizationId?: string;
  reservationId: string;
  date: Date;
  startTime: string;
  status: 'PENDING' | 'CONFIRMED' | 'CANCELLED' | 'NO_SHOW';
  previousStatus: string;
}) {
  if (!params.memberAccountId || params.status === params.previousStatus) return;

  const dateStr = formatDateOnly(params.date);
  let title = '예약 상태 변경';
  let body = `${dateStr} ${params.startTime} 예약 상태가 변경되었습니다`;

  if (params.status === 'CONFIRMED') {
    title = '예약 확정';
    body = `${dateStr} ${params.startTime} 예약이 확정되었습니다`;
  } else if (params.status === 'CANCELLED') {
    if (params.previousStatus === 'PENDING') {
      title = '예약 신청 거절';
      body = `${dateStr} ${params.startTime} 예약 신청이 거절되었습니다`;
    } else {
      title = '예약 취소';
      body = `${dateStr} ${params.startTime} 예약이 취소되었습니다`;
    }
  }

  await safelyCreateMemberNotification({
    memberAccountId: params.memberAccountId,
    organizationId: params.organizationId,
    type: 'RESERVATION_STATUS_UPDATED',
    title,
    body,
    reservationId: params.reservationId,
  });

  await safelySendMemberPushIfEnabled({
    memberAccountId: params.memberAccountId,
    type: 'RESERVATION_STATUS_UPDATED',
    title,
    body,
    reservationId: params.reservationId,
  });
}

export async function handleReservationDelayedNotification(params: {
  memberAccountId?: string | null;
  organizationId?: string;
  reservationId: string;
  date: string;
  delayMinutes: number;
  newStartTime: string;
}) {
  if (!params.memberAccountId) return;

  const absMinutes = Math.abs(params.delayMinutes);
  const direction = params.delayMinutes > 0 ? '미뤄져' : '앞당겨져';
  const title = '예약 시간이 변경되었습니다';
  const body = `${params.date} 예약이 ${absMinutes}분 ${direction} ${params.newStartTime}에 시작합니다`;

  await safelyCreateMemberNotification({
    memberAccountId: params.memberAccountId,
    organizationId: params.organizationId,
    type: 'RESERVATION_DELAYED',
    title,
    body,
    reservationId: params.reservationId,
  });

  await safelySendMemberPushIfEnabled({
    memberAccountId: params.memberAccountId,
    type: 'RESERVATION_DELAYED',
    title,
    body,
    reservationId: params.reservationId,
  });
}
