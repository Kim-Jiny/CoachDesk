import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'api_client.dart';
import 'constants.dart';

class NotificationPreferences {
  final bool reservation;
  final bool chat;
  final bool package;
  final bool general;

  const NotificationPreferences({
    this.reservation = true,
    this.chat = true,
    this.package = true,
    this.general = true,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      reservation: json['reservation'] as bool? ?? true,
      chat: json['chat'] as bool? ?? true,
      package: json['package'] as bool? ?? true,
      general: json['general'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'reservation': reservation,
    'chat': chat,
    'package': package,
    'general': general,
  };

  NotificationPreferences copyWith({
    bool? reservation,
    bool? chat,
    bool? package,
    bool? general,
  }) {
    return NotificationPreferences(
      reservation: reservation ?? this.reservation,
      chat: chat ?? this.chat,
      package: package ?? this.package,
      general: general ?? this.general,
    );
  }
}

class FcmService {
  FcmService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final List<VoidCallback> _reservationSyncListeners = [];
  static const String _defaultChannelId = 'coachdesk_default';
  static const String _defaultChannelName = 'CoachDesk 알림';
  static const String _chatChannelId = 'coachdesk_chat';
  static const String _chatChannelName = 'CoachDesk 채팅 알림';

  static GlobalKey<NavigatorState>? navigatorKey;

  static Future<void> initialize() async {
    await Firebase.initializeApp();
    await _initializeLocalNotifications();

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  }

  static Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _defaultChannelId,
        _defaultChannelName,
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _chatChannelId,
        _chatChannelName,
        importance: Importance.high,
      ),
    );
  }

  static Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('FCM getToken error: $e');
      return null;
    }
  }

  static Future<void> registerToken({required bool isMember}) async {
    final token = await getToken();
    if (token == null) return;

    try {
      final dio = ApiClient.createDio();
      final endpoint = isMember ? '/auth/member/fcm-token' : '/auth/fcm-token';
      await dio.put(endpoint, data: {'fcmToken': token});
      await syncNotificationPreferences(isMember: isMember);
      debugPrint('FCM token registered');
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }

  static Future<NotificationPreferences> syncNotificationPreferences({
    required bool isMember,
  }) async {
    final dio = ApiClient.createDio();
    final endpoint = isMember
        ? '/auth/member/notification-preferences'
        : '/auth/notification-preferences';
    final response = await dio.get(endpoint);
    final preferences = NotificationPreferences.fromJson(
      response.data as Map<String, dynamic>,
    );
    await cacheNotificationPreferences(preferences, isMember: isMember);
    return preferences;
  }

  static Future<NotificationPreferences> updateNotificationPreferences({
    required bool isMember,
    required NotificationPreferences preferences,
  }) async {
    final dio = ApiClient.createDio();
    final endpoint = isMember
        ? '/auth/member/notification-preferences'
        : '/auth/notification-preferences';
    await dio.put(endpoint, data: preferences.toJson());
    await cacheNotificationPreferences(preferences, isMember: isMember);
    return preferences;
  }

  static Future<void> cacheNotificationPreferences(
    NotificationPreferences preferences, {
    required bool isMember,
  }) async {
    final box = Hive.box(AppConstants.authBox);
    final key = isMember
        ? AppConstants.memberNotificationPreferencesKey
        : AppConstants.adminNotificationPreferencesKey;
    await box.put(key, jsonEncode(preferences.toJson()));
  }

  static NotificationPreferences getCachedNotificationPreferences({
    required bool isMember,
  }) {
    final box = Hive.box(AppConstants.authBox);
    final key = isMember
        ? AppConstants.memberNotificationPreferencesKey
        : AppConstants.adminNotificationPreferencesKey;
    final raw = box.get(key) as String?;
    if (raw == null || raw.isEmpty) {
      return const NotificationPreferences();
    }
    try {
      return NotificationPreferences.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const NotificationPreferences();
    }
  }

  static void _onForegroundMessage(RemoteMessage message) {
    _notifyReservationSyncListeners(message);

    final type = message.data['type'] as String?;
    if (!_isNotificationEnabled(type)) return;

    if (type == 'CHAT_MESSAGE') {
      showForegroundChatAlert(
        title: message.notification?.title ?? '새 메시지',
        body: message.notification?.body ?? '',
      );
      return;
    }

    _showLocalNotification(message);
  }

  static void _onMessageOpenedApp(RemoteMessage message) {
    _notifyReservationSyncListeners(message);
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final title = message.notification?.title;
    final body = message.notification?.body;
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final type = message.data['type'] as String?;
    final isChat = type == 'CHAT_MESSAGE';
    await _localNotifications.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          isChat ? _chatChannelId : _defaultChannelId,
          isChat ? _chatChannelName : _defaultChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static bool _isNotificationEnabled(String? type) {
    final preferences = getCachedNotificationPreferences(
      isMember: ApiClient.isMemberMode,
    );
    return switch (type) {
      'CHAT_MESSAGE' => preferences.chat,
      'NEW_RESERVATION' ||
      'RESERVATION_STATUS_UPDATED' ||
      'RESERVATION_CANCELLED' ||
      'RESERVATION_DELAYED' => preferences.reservation,
      'PACKAGE_PAUSE_APPROVED' ||
      'PACKAGE_PAUSE_REJECTED' => preferences.package,
      _ => preferences.general,
    };
  }

  static void showForegroundChatAlert({
    required String title,
    required String body,
  }) {
    if (!getCachedNotificationPreferences(
      isMember: ApiClient.isMemberMode,
    ).chat) {
      return;
    }

    final context = navigatorKey?.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (body.isNotEmpty)
              Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static void addReservationSyncListener(VoidCallback listener) {
    _reservationSyncListeners.add(listener);
  }

  static void removeReservationSyncListener(VoidCallback listener) {
    _reservationSyncListeners.remove(listener);
  }

  static void _notifyReservationSyncListeners(RemoteMessage message) {
    final type = message.data['type'] as String?;
    const reservationEventTypes = {
      'NEW_RESERVATION',
      'RESERVATION_CANCELLED',
      'RESERVATION_STATUS_UPDATED',
      'RESERVATION_DELAYED',
    };
    if (type == null || !reservationEventTypes.contains(type)) return;
    for (final listener in List<VoidCallback>.from(_reservationSyncListeners)) {
      listener();
    }
  }
}

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}
