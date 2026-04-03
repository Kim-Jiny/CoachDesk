import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/fcm_service.dart';
import '../models/user.dart';
import '../models/organization.dart';

enum AuthStatus { initial, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final User? user;
  final Organization? organization;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.organization,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    Organization? organization,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      organization: organization ?? this.organization,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Dio get _dio => ref.read(dioProvider);

  void setUnauthenticated() {
    state = state.copyWith(status: AuthStatus.unauthenticated);
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
      final org = response.data['organization'] != null
          ? Organization.fromJson(response.data['organization'])
          : null;

      await ApiClient.saveUserId(user.id);
      if (org != null) await ApiClient.saveOrgId(org.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        organization: org,
      );
    } catch (_) {
      await ApiClient.clearTokens();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String name,
    String? phone,
    String? organizationName,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post('/auth/register', data: {
        'email': email,
        'password': password,
        'name': name,
        'phone': phone,
        'organizationName': organizationName,
      });

      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, false);

      await ApiClient.saveAdminTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final user = User.fromJson(response.data['user']);
      final org = Organization.fromJson(response.data['organization']);
      await ApiClient.saveUserId(user.id);
      await ApiClient.saveOrgId(org.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        organization: org,
        isLoading: false,
      );

      FcmService.registerToken(isMember: false);
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? 'Registration failed';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, false);

      await ApiClient.saveAdminTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final user = User.fromJson(response.data['user']);
      final org = response.data['organization'] != null
          ? Organization.fromJson(response.data['organization'])
          : null;
      await ApiClient.saveUserId(user.id);
      if (org != null) await ApiClient.saveOrgId(org.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        organization: org,
        isLoading: false,
      );

      FcmService.registerToken(isMember: false);
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
      final org = response.data['organization'] != null
          ? Organization.fromJson(response.data['organization'])
          : null;
      await ApiClient.saveUserId(user.id);
      if (org != null) await ApiClient.saveOrgId(org.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        organization: org,
        isLoading: false,
      );

      FcmService.registerToken(isMember: false);
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

  /// Upgrade current member account to admin by creating User + Organization.
  /// Called from AdminRegisterDialog with just a studio name.
  Future<bool> upgradeFromMember({required String organizationName}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post('/auth/member/upgrade-to-admin', data: {
        'organizationName': organizationName,
      });

      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, false);

      await ApiClient.saveAdminTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final user = User.fromJson(response.data['user']);
      final org = response.data['organization'] != null
          ? Organization.fromJson(response.data['organization'])
          : null;
      await ApiClient.saveUserId(user.id);
      if (org != null) await ApiClient.saveOrgId(org.id);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        organization: org,
        isLoading: false,
      );

      FcmService.registerToken(isMember: false);
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '관리자 전환에 실패했습니다';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
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
    return state.status == AuthStatus.authenticated;
  }

  Future<void> logout() async {
    await ApiClient.clearTokens();
    final box = Hive.box(AppConstants.authBox);
    await box.delete(AppConstants.isMemberAccountKey);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
