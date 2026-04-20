import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/fcm_service.dart';
import '../core/home_widget_service.dart';
import '../models/user.dart';
import '../models/organization.dart';

enum AuthStatus { initial, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final User? user;
  final List<Organization> centers;
  final Organization? selectedCenter;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.centers = const [],
    this.selectedCenter,
    this.isLoading = false,
    this.error,
  });

  bool get hasNoCenters => centers.isEmpty;
  bool get needsCenterSelection =>
      status == AuthStatus.authenticated && selectedCenter == null;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    List<Organization>? centers,
    Organization? selectedCenter,
    bool clearSelectedCenter = false,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      centers: centers ?? this.centers,
      selectedCenter: clearSelectedCenter
          ? null
          : (selectedCenter ?? this.selectedCenter),
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  void _syncWidgets() {
    unawaited(HomeWidgetService.syncAll());
  }

  @override
  AuthState build() => const AuthState();

  Dio get _dio => ref.read(dioProvider);

  void setUnauthenticated() {
    state = state.copyWith(status: AuthStatus.unauthenticated);
  }

  List<Organization> _parseOrganizations(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data
          .map((e) => Organization.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // Backward compatibility: single organization object
    if (data is Map<String, dynamic>) {
      return [Organization.fromJson(data)];
    }
    return [];
  }

  Organization? _autoSelectCenter(List<Organization> centers) {
    if (centers.isEmpty) return null;

    // Try to restore previously selected center
    final savedOrgId = ApiClient.getOrgId();
    if (savedOrgId != null) {
      final saved = centers.where((c) => c.id == savedOrgId).firstOrNull;
      if (saved != null) return saved;
    }

    // Auto-select if only one center
    if (centers.length == 1) return centers.first;

    return null;
  }

  Future<void> checkAuth() async {
    final token = ApiClient.getAccessToken();
    if (token == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final response = await _dio.get('/auth/profile');
      final user = User.fromJson(response.data['user']);
      final centers = _parseOrganizations(response.data['organizations']);
      final selected = _autoSelectCenter(centers);

      await ApiClient.saveUserId(user.id);
      if (selected != null) await ApiClient.saveOrgId(selected.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        centers: centers,
        selectedCenter: selected,
        clearSelectedCenter: selected == null,
      );
      try {
        await FcmService.syncNotificationPreferences(isMember: false);
      } catch (_) {}
      _syncWidgets();
    } catch (_) {
      await ApiClient.clearTokens();
      state = state.copyWith(status: AuthStatus.unauthenticated);
      _syncWidgets();
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'name': name,
          'phone': phone,
        },
      );

      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, false);

      await ApiClient.saveAdminTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final user = User.fromJson(response.data['user']);
      final centers = _parseOrganizations(response.data['organizations']);
      await ApiClient.saveUserId(user.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        centers: centers,
        clearSelectedCenter: true,
        isLoading: false,
      );

      FcmService.registerToken(isMember: false);
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg =
          e.response?.data?['error'] as String? ?? 'Registration failed';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, false);

      await ApiClient.saveAdminTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final user = User.fromJson(response.data['user']);
      final centers = _parseOrganizations(response.data['organizations']);
      final selected = _autoSelectCenter(centers);

      await ApiClient.saveUserId(user.id);
      if (selected != null) await ApiClient.saveOrgId(selected.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        centers: centers,
        selectedCenter: selected,
        isLoading: false,
      );

      FcmService.registerToken(isMember: false);
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? 'Login failed';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> socialLogin({
    required String provider,
    required String idToken,
    String? name,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final payload = <String, dynamic>{
        'idToken': idToken,
        'provider': provider,
      };
      if (name != null && name.trim().isNotEmpty) {
        payload['name'] = name.trim();
      }

      final response = await _dio.post('/auth/social', data: payload);

      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, false);

      await ApiClient.saveAdminTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final user = User.fromJson(response.data['user']);
      final centers = _parseOrganizations(response.data['organizations']);
      final selected = _autoSelectCenter(centers);

      await ApiClient.saveUserId(user.id);
      if (selected != null) await ApiClient.saveOrgId(selected.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        centers: centers,
        selectedCenter: selected,
        isLoading: false,
      );

      FcmService.registerToken(isMember: false);
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '소셜 로그인 실패';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: '소셜 로그인 실패');
      return false;
    }
  }

  /// Upgrade current member account to admin by creating User account.
  /// Center creation/joining is a separate step via onboarding.
  Future<bool> upgradeFromMember() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post('/auth/member/upgrade-to-admin');

      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, false);

      await ApiClient.saveAdminTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final user = User.fromJson(response.data['user']);
      final centers = _parseOrganizations(response.data['organizations']);
      final selected = _autoSelectCenter(centers);

      await ApiClient.saveUserId(user.id);
      if (selected != null) await ApiClient.saveOrgId(selected.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        centers: centers,
        selectedCenter: selected,
        isLoading: false,
      );

      FcmService.registerToken(isMember: false);
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '관리자 전환에 실패했습니다';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  // ─── Center Management ────────────────────────────────────

  Future<void> selectCenter(String organizationId) async {
    final center = state.centers
        .where((c) => c.id == organizationId)
        .firstOrNull;
    if (center == null) return;

    await ApiClient.saveOrgId(center.id);
    state = state.copyWith(selectedCenter: center);
    _syncWidgets();
  }

  Future<bool> createCenter({required String name, String? description}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = <String, dynamic>{'name': name};
      if (description != null) data['description'] = description;
      final response = await _dio.post('/centers', data: data);

      final newCenter = Organization.fromJson(response.data);
      final updatedCenters = [...state.centers, newCenter];

      await ApiClient.saveOrgId(newCenter.id);
      state = state.copyWith(
        centers: updatedCenters,
        selectedCenter: newCenter,
        isLoading: false,
      );
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '센터 생성에 실패했습니다';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<CenterJoinRequest?> requestJoinCenter(
    String inviteCode, {
    String? message,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = <String, dynamic>{'inviteCode': inviteCode};
      if (message != null) data['message'] = message;
      final response = await _dio.post('/centers/join-request', data: data);

      state = state.copyWith(isLoading: false);
      return CenterJoinRequest.fromJson(response.data);
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '합류 신청에 실패했습니다';
      state = state.copyWith(isLoading: false, error: msg);
      return null;
    }
  }

  Future<void> fetchCenters() async {
    // Only show loading spinner when centers are not yet loaded
    if (state.centers.isEmpty) {
      state = state.copyWith(isLoading: true, error: null);
    } else {
      state = state.copyWith(error: null);
    }
    try {
      final response = await _dio.get('/centers');
      final centersData = response.data['centers'] as List? ?? [];
      final centers = centersData
          .map((e) => Organization.fromJson(e as Map<String, dynamic>))
          .toList();

      // Preserve existing selected center if still in the updated list
      final currentSelectedId = state.selectedCenter?.id;
      final selected = currentSelectedId != null
          ? centers.where((c) => c.id == currentSelectedId).firstOrNull ??
                _autoSelectCenter(centers)
          : _autoSelectCenter(centers);
      if (selected != null) await ApiClient.saveOrgId(selected.id);

      state = state.copyWith(
        centers: centers,
        selectedCenter: selected,
        clearSelectedCenter: selected == null,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, error: '센터 목록을 불러오지 못했습니다');
    }
  }

  /// Switch from member mode to admin mode.
  /// Returns true if admin token exists and switch succeeded.
  Future<bool> switchFromMember() async {
    final adminToken = ApiClient.getAdminAccessToken();
    if (adminToken == null) return false;

    final box = Hive.box(AppConstants.authBox);
    await box.put(AppConstants.isMemberAccountKey, false);
    await checkAuth();
    _syncWidgets();
    return state.status == AuthStatus.authenticated;
  }

  Future<void> logout() async {
    await ApiClient.clearTokens();
    final box = Hive.box(AppConstants.authBox);
    await box.delete(AppConstants.isMemberAccountKey);
    state = const AuthState(status: AuthStatus.unauthenticated);
    _syncWidgets();
  }

  Future<bool> updateProfile({
    String? name,
    String? phone,
    String? reservationNoticeImageBase64,
    String? reservationNoticeImageFileName,
    String? reservationNoticeImageContentType,
    String? bookingMode,
    String? reservationPolicy,
    String? reservationNoticeText,
    String? reservationNoticeImageUrl,
    bool clearReservationNoticeText = false,
    bool clearReservationNoticeImage = false,
    int? reservationOpenDaysBefore,
    int? reservationOpenHoursBefore,
    int? reservationCancelDeadlineMinutes,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (phone != null) data['phone'] = phone;
      if (bookingMode != null) data['bookingMode'] = bookingMode;
      if (reservationPolicy != null) {
        data['reservationPolicy'] = reservationPolicy;
      }
      if (clearReservationNoticeText || reservationNoticeText != null) {
        data['reservationNoticeText'] = reservationNoticeText;
      }
      if (clearReservationNoticeImage || reservationNoticeImageUrl != null) {
        data['reservationNoticeImageUrl'] = reservationNoticeImageUrl;
      }
      if (reservationOpenDaysBefore != null) {
        data['reservationOpenDaysBefore'] = reservationOpenDaysBefore;
      }
      if (reservationOpenHoursBefore != null) {
        data['reservationOpenHoursBefore'] = reservationOpenHoursBefore;
      }
      if (reservationCancelDeadlineMinutes != null) {
        data['reservationCancelDeadlineMinutes'] =
            reservationCancelDeadlineMinutes;
      }

      if (reservationNoticeImageBase64 != null &&
          reservationNoticeImageFileName != null &&
          reservationNoticeImageContentType != null) {
        final uploadResponse = await _dio.post(
          '/auth/profile/reservation-notice-image',
          data: {
            'fileName': reservationNoticeImageFileName,
            'contentType': reservationNoticeImageContentType,
            'base64Data': reservationNoticeImageBase64,
          },
        );
        data['reservationNoticeImageUrl'] = uploadResponse.data['imageUrl'];
      }

      final response = await _dio.put('/auth/profile', data: data);
      final updatedUser = User.fromJson(response.data as Map<String, dynamic>);

      state = state.copyWith(user: updatedUser, isLoading: false);
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '프로필 수정에 실패했습니다';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<String?> deleteAccount() async {
    try {
      await _dio.delete('/auth/profile');
      await ApiClient.clearTokens();
      final box = Hive.box(AppConstants.authBox);
      await box.delete(AppConstants.isMemberAccountKey);
      state = const AuthState(status: AuthStatus.unauthenticated);
      _syncWidgets();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['error'] as String? ?? '관리자 계정 삭제에 실패했습니다';
    } catch (_) {
      return '관리자 계정 삭제에 실패했습니다';
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
