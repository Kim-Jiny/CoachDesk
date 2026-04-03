import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'constants.dart';

final dioProvider = Provider<Dio>((ref) {
  return ApiClient.createDio();
});

class ApiClient {
  ApiClient._();

  static Dio createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(_AuthInterceptor(dio));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) => debugPrint('[API] $obj'),
      ));
    }

    return dio;
  }

  static bool get isMemberMode {
    final box = Hive.box(AppConstants.authBox);
    return box.get(AppConstants.isMemberAccountKey) as bool? ?? false;
  }

  static String? getAccessToken() {
    final box = Hive.box(AppConstants.authBox);
    if (isMemberMode) {
      return box.get(AppConstants.memberAccessTokenKey) as String?;
    }
    return box.get(AppConstants.adminAccessTokenKey) as String?;
  }

  static String? getRefreshToken() {
    final box = Hive.box(AppConstants.authBox);
    if (isMemberMode) {
      return box.get(AppConstants.memberRefreshTokenKey) as String?;
    }
    return box.get(AppConstants.adminRefreshTokenKey) as String?;
  }

  static String? getAdminAccessToken() {
    final box = Hive.box(AppConstants.authBox);
    return box.get(AppConstants.adminAccessTokenKey) as String?;
  }

  static String? getMemberAccessToken() {
    final box = Hive.box(AppConstants.authBox);
    return box.get(AppConstants.memberAccessTokenKey) as String?;
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    if (isMemberMode) {
      await saveMemberTokens(accessToken: accessToken, refreshToken: refreshToken);
    } else {
      await saveAdminTokens(accessToken: accessToken, refreshToken: refreshToken);
    }
  }

  static Future<void> saveAdminTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final box = Hive.box(AppConstants.authBox);
    await box.put(AppConstants.adminAccessTokenKey, accessToken);
    await box.put(AppConstants.adminRefreshTokenKey, refreshToken);
  }

  static Future<void> saveMemberTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final box = Hive.box(AppConstants.authBox);
    await box.put(AppConstants.memberAccessTokenKey, accessToken);
    await box.put(AppConstants.memberRefreshTokenKey, refreshToken);
  }

  static Future<void> clearTokens() async {
    final box = Hive.box(AppConstants.authBox);
    if (isMemberMode) {
      await box.delete(AppConstants.memberAccessTokenKey);
      await box.delete(AppConstants.memberRefreshTokenKey);
    } else {
      await box.delete(AppConstants.adminAccessTokenKey);
      await box.delete(AppConstants.adminRefreshTokenKey);
      await box.delete(AppConstants.userIdKey);
      await box.delete(AppConstants.orgIdKey);
    }
  }

  static Future<void> clearAllTokens() async {
    final box = Hive.box(AppConstants.authBox);
    await box.delete(AppConstants.adminAccessTokenKey);
    await box.delete(AppConstants.adminRefreshTokenKey);
    await box.delete(AppConstants.memberAccessTokenKey);
    await box.delete(AppConstants.memberRefreshTokenKey);
    await box.delete(AppConstants.userIdKey);
    await box.delete(AppConstants.orgIdKey);
    await box.delete(AppConstants.isMemberAccountKey);
    await box.delete(AppConstants.memberNameKey);
  }

  static Future<void> saveUserId(String userId) async {
    final box = Hive.box(AppConstants.authBox);
    await box.put(AppConstants.userIdKey, userId);
  }

  static String? getUserId() {
    final box = Hive.box(AppConstants.authBox);
    return box.get(AppConstants.userIdKey) as String?;
  }

  static Future<void> saveOrgId(String orgId) async {
    final box = Hive.box(AppConstants.authBox);
    await box.put(AppConstants.orgIdKey, orgId);
  }

  static String? getOrgId() {
    final box = Hive.box(AppConstants.authBox);
    return box.get(AppConstants.orgIdKey) as String?;
  }
}

class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = ApiClient.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    final orgId = ApiClient.getOrgId();
    if (!ApiClient.isMemberMode && orgId != null && orgId.isNotEmpty) {
      options.headers['X-Organization-Id'] = orgId;
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;

      try {
        final refreshToken = ApiClient.getRefreshToken();
        if (refreshToken == null) {
          _isRefreshing = false;
          return handler.next(err);
        }

        final refreshDio = Dio(BaseOptions(
          baseUrl: AppConstants.apiBaseUrl,
          headers: {'Content-Type': 'application/json'},
        ));

        final response = await refreshDio.post(
          '/auth/refresh',
          data: {'refreshToken': refreshToken},
        );

        if (response.statusCode == 200) {
          final newAccessToken = response.data['accessToken'] as String;

          final box = Hive.box(AppConstants.authBox);
          final tokenKey = ApiClient.isMemberMode
              ? AppConstants.memberAccessTokenKey
              : AppConstants.adminAccessTokenKey;
          await box.put(tokenKey, newAccessToken);

          final options = err.requestOptions;
          options.headers['Authorization'] = 'Bearer $newAccessToken';

          final retryResponse = await _dio.fetch(options);
          _isRefreshing = false;
          return handler.resolve(retryResponse);
        }
      } catch (e) {
        await ApiClient.clearTokens();
      }

      _isRefreshing = false;
    }

    handler.next(err);
  }
}
