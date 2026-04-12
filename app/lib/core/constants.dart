import 'package:flutter/foundation.dart';

class AppConstants {
  AppConstants._();

  static const String _defaultReleaseHost = 'https://coach.jiny.shop/api';
  static const String _configuredHost = String.fromEnvironment(
    'COACHDESK_API_BASE_URL',
    defaultValue: '',
  );
  static const String _configuredDebugHost = String.fromEnvironment(
    'COACHDESK_API_BASE_URL_DEBUG',
    defaultValue: '',
  );
  static const String _configuredReleaseHost = String.fromEnvironment(
    'COACHDESK_API_BASE_URL_RELEASE',
    defaultValue: _defaultReleaseHost,
  );
  static const String _debugHost = String.fromEnvironment(
    'COACHDESK_API_HOST',
    defaultValue: '',
  );
  static const String _debugServerIp = String.fromEnvironment(
    'DEBUG_SERVER_IP',
    defaultValue: '',
  );
  static const String _debugPort = String.fromEnvironment(
    'COACHDESK_API_PORT',
    defaultValue: '3010',
  );
  static const String _debugScheme = String.fromEnvironment(
    'COACHDESK_API_SCHEME',
    defaultValue: 'http',
  );

  static String get apiBaseUrl {
    if (_configuredHost.isNotEmpty) return _configuredHost;
    if (!kDebugMode) return _configuredReleaseHost;
    if (_configuredDebugHost.isNotEmpty) return _configuredDebugHost;

    final host = _debugHost.isNotEmpty
        ? _debugHost
        : (_debugServerIp.isNotEmpty ? _debugServerIp : _defaultDebugHost);
    return '$_debugScheme://$host:$_debugPort/api';
  }

  static String get _defaultDebugHost {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2';
    }
    return 'localhost';
  }

  // Hive boxes
  static const String authBox = 'auth_box';
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String adminAccessTokenKey = 'admin_access_token';
  static const String adminRefreshTokenKey = 'admin_refresh_token';
  static const String memberAccessTokenKey = 'member_access_token';
  static const String memberRefreshTokenKey = 'member_refresh_token';
  static const String userIdKey = 'user_id';
  static const String orgIdKey = 'org_id';
  static const String isMemberAccountKey = 'is_member_account';
  static const String memberNameKey = 'member_name';
  static const String reservationLastMemberIdKey = 'reservation_last_member_id';
  static const String reservationLastStartTimeKey =
      'reservation_last_start_time';
  static const String reservationLastEndTimeKey = 'reservation_last_end_time';
  static const String hideRevenueAmountKey = 'hide_revenue_amount';
  static const String adminNotificationPreferencesKey =
      'admin_notification_preferences';
  static const String memberNotificationPreferencesKey =
      'member_notification_preferences';
}
