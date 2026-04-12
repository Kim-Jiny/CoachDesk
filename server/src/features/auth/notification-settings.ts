import { z } from 'zod';
import { prisma } from '../../utils/prisma';
import {
  parseNotificationPreferences,
  stringifyNotificationPreferences,
} from '../../utils/notification-preferences';

export const notificationPreferencesSchema = z.object({
  reservation: z.boolean(),
  chat: z.boolean(),
  package: z.boolean(),
  general: z.boolean(),
});

export const fcmTokenSchema = z.object({
  fcmToken: z.string().min(1),
});

export async function updateUserFcmToken(userId: string, fcmToken: string) {
  await prisma.user.update({
    where: { id: userId },
    data: { fcmToken },
  });
}

export async function getUserNotificationPreferences(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { notificationPreferences: true },
  });
  return parseNotificationPreferences(user?.notificationPreferences);
}

export async function updateUserNotificationPreferences(
  userId: string,
  preferences: z.infer<typeof notificationPreferencesSchema>,
) {
  await prisma.user.update({
    where: { id: userId },
    data: {
      notificationPreferences: stringifyNotificationPreferences(preferences),
    },
  });
  return preferences;
}

export async function updateMemberFcmToken(
  memberAccountId: string,
  fcmToken: string,
) {
  await prisma.memberAccount.update({
    where: { id: memberAccountId },
    data: { fcmToken },
  });
}

export async function getMemberNotificationPreferences(memberAccountId: string) {
  const memberAccount = await prisma.memberAccount.findUnique({
    where: { id: memberAccountId },
    select: { notificationPreferences: true },
  });
  return parseNotificationPreferences(memberAccount?.notificationPreferences);
}

export async function updateMemberNotificationPreferences(
  memberAccountId: string,
  preferences: z.infer<typeof notificationPreferencesSchema>,
) {
  await prisma.memberAccount.update({
    where: { id: memberAccountId },
    data: {
      notificationPreferences: stringifyNotificationPreferences(preferences),
    },
  });
  return preferences;
}
