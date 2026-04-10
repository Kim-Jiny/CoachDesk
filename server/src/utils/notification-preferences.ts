export type NotificationPreferences = {
  reservation: boolean;
  chat: boolean;
  package: boolean;
  general: boolean;
};

export const defaultNotificationPreferences: NotificationPreferences = {
  reservation: true,
  chat: true,
  package: true,
  general: true,
};

export function parseNotificationPreferences(
  raw?: string | null,
): NotificationPreferences {
  if (!raw) {
    return { ...defaultNotificationPreferences };
  }

  try {
    const parsed = JSON.parse(raw) as Partial<NotificationPreferences>;
    return {
      reservation: parsed.reservation ?? true,
      chat: parsed.chat ?? true,
      package: parsed.package ?? true,
      general: parsed.general ?? true,
    };
  } catch {
    return { ...defaultNotificationPreferences };
  }
}

export function stringifyNotificationPreferences(
  preferences: Partial<NotificationPreferences>,
): string {
  return JSON.stringify({
    ...defaultNotificationPreferences,
    ...preferences,
  });
}

export function notificationPreferenceCategoryForType(type?: string | null) {
  switch (type) {
    case 'CHAT_MESSAGE':
      return 'chat' as const;
    case 'NEW_RESERVATION':
    case 'RESERVATION_STATUS_UPDATED':
    case 'RESERVATION_CANCELLED':
    case 'RESERVATION_DELAYED':
      return 'reservation' as const;
    case 'PACKAGE_PAUSE_APPROVED':
    case 'PACKAGE_PAUSE_REJECTED':
      return 'package' as const;
    default:
      return 'general' as const;
  }
}

export function shouldSendPushForType(
  rawPreferences: string | null | undefined,
  type?: string | null,
) {
  const preferences = parseNotificationPreferences(rawPreferences);
  const category = notificationPreferenceCategoryForType(type);
  return preferences[category];
}
