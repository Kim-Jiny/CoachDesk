import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../core/fcm_service.dart';
import '../core/home_widget_service.dart';
import '../models/member_booking.dart';
import '../models/package.dart';

enum MemberAuthStatus { initial, authenticated, unauthenticated }

class MemberClass {
  final String memberId;
  final String organizationId;
  final String organizationName;
  final List<MemberCoach> coaches;

  const MemberClass({
    required this.memberId,
    required this.organizationId,
    required this.organizationName,
    required this.coaches,
  });

  factory MemberClass.fromJson(Map<String, dynamic> json) {
    final org = json['organization'] as Map<String, dynamic>;
    final coachList = (json['coaches'] as List?) ?? [];
    return MemberClass(
      memberId: json['memberId'] as String,
      organizationId: org['id'] as String,
      organizationName: org['name'] as String,
      coaches: coachList
          .map((c) => MemberCoach.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MemberCoach {
  final String id;
  final String name;
  final String? profileImage;

  const MemberCoach({required this.id, required this.name, this.profileImage});

  factory MemberCoach.fromJson(Map<String, dynamic> json) {
    return MemberCoach(
      id: json['id'] as String,
      name: json['name'] as String,
      profileImage: json['profileImage'] as String?,
    );
  }
}

class MemberReservationNotice {
  final String organizationId;
  final String organizationName;
  final String? text;
  final String? imageUrl;
  final int reservationOpenDaysBefore;
  final int reservationOpenHoursBefore;
  final int reservationCancelDeadlineMinutes;

  const MemberReservationNotice({
    required this.organizationId,
    required this.organizationName,
    this.text,
    this.imageUrl,
    this.reservationOpenDaysBefore = 30,
    this.reservationOpenHoursBefore = 0,
    this.reservationCancelDeadlineMinutes = 120,
  });

  bool get hasContent =>
      (text != null && text!.trim().isNotEmpty) ||
      (imageUrl != null && imageUrl!.trim().isNotEmpty);

  factory MemberReservationNotice.fromJson(Map<String, dynamic> json) {
    return MemberReservationNotice(
      organizationId: json['organizationId'] as String,
      organizationName: json['organizationName'] as String? ?? '',
      text: json['reservationNoticeText'] as String?,
      imageUrl: json['reservationNoticeImageUrl'] as String?,
      reservationOpenDaysBefore:
          json['reservationOpenDaysBefore'] as int? ?? 30,
      reservationOpenHoursBefore:
          json['reservationOpenHoursBefore'] as int? ?? 0,
      reservationCancelDeadlineMinutes:
          json['reservationCancelDeadlineMinutes'] as int? ?? 120,
    );
  }
}

class MemberAuthState {
  final MemberAuthStatus status;
  final String? accountId;
  final String? name;
  final String? email;
  final List<MemberClass> classes;
  final bool isLoading;
  final String? error;

  const MemberAuthState({
    this.status = MemberAuthStatus.initial,
    this.accountId,
    this.name,
    this.email,
    this.classes = const [],
    this.isLoading = false,
    this.error,
  });

  MemberAuthState copyWith({
    MemberAuthStatus? status,
    String? accountId,
    String? name,
    String? email,
    List<MemberClass>? classes,
    bool? isLoading,
    String? error,
  }) {
    return MemberAuthState(
      status: status ?? this.status,
      accountId: accountId ?? this.accountId,
      name: name ?? this.name,
      email: email ?? this.email,
      classes: classes ?? this.classes,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MemberAuthNotifier extends Notifier<MemberAuthState> {
  void _syncWidgets() {
    unawaited(HomeWidgetService.syncAll());
  }

  @override
  MemberAuthState build() => const MemberAuthState();

  Dio get _dio => ref.read(dioProvider);

  void setUnauthenticated() {
    state = state.copyWith(status: MemberAuthStatus.unauthenticated);
  }

  Future<void> checkAuth() async {
    final box = Hive.box(AppConstants.authBox);
    final isMember = box.get(AppConstants.isMemberAccountKey) as bool? ?? false;
    if (!isMember) {
      state = state.copyWith(status: MemberAuthStatus.unauthenticated);
      return;
    }

    final token = ApiClient.getAccessToken();
    if (token == null) {
      state = state.copyWith(status: MemberAuthStatus.unauthenticated);
      return;
    }

    try {
      final response = await _dio.get('/auth/member/profile');
      final account = response.data['memberAccount'] as Map<String, dynamic>;

      state = state.copyWith(
        status: MemberAuthStatus.authenticated,
        accountId: account['id'] as String,
        name: account['name'] as String,
        email: account['email'] as String,
      );

      try {
        await FcmService.syncNotificationPreferences(isMember: true);
      } catch (_) {}
      await fetchMyClasses();
      _syncWidgets();
    } catch (_) {
      await ApiClient.clearTokens();
      final box = Hive.box(AppConstants.authBox);
      await box.delete(AppConstants.isMemberAccountKey);
      state = state.copyWith(status: MemberAuthStatus.unauthenticated);
      _syncWidgets();
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(
        '/auth/member/register',
        data: {'name': name, 'email': email, 'password': password},
      );

      await ApiClient.saveMemberTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final account = response.data['memberAccount'] as Map<String, dynamic>;
      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, true);
      await box.put(AppConstants.memberNameKey, account['name']);

      state = state.copyWith(
        status: MemberAuthStatus.authenticated,
        accountId: account['id'] as String,
        name: account['name'] as String,
        email: account['email'] as String,
        isLoading: false,
      );

      FcmService.registerToken(isMember: true);
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '회원가입에 실패했습니다';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(
        '/auth/member/login',
        data: {'email': email, 'password': password},
      );

      await ApiClient.saveMemberTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final account = response.data['memberAccount'] as Map<String, dynamic>;
      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, true);
      await box.put(AppConstants.memberNameKey, account['name']);

      state = state.copyWith(
        status: MemberAuthStatus.authenticated,
        accountId: account['id'] as String,
        name: account['name'] as String,
        email: account['email'] as String,
        isLoading: false,
      );

      await fetchMyClasses();
      FcmService.registerToken(isMember: true);
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '로그인에 실패했습니다';
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

      final response = await _dio.post('/auth/member/social', data: payload);

      await ApiClient.saveMemberTokens(
        accessToken: response.data['accessToken'],
        refreshToken: response.data['refreshToken'],
      );

      final account = response.data['memberAccount'] as Map<String, dynamic>;
      final box = Hive.box(AppConstants.authBox);
      await box.put(AppConstants.isMemberAccountKey, true);
      await box.put(AppConstants.memberNameKey, account['name']);

      state = state.copyWith(
        status: MemberAuthStatus.authenticated,
        accountId: account['id'] as String,
        name: account['name'] as String,
        email: account['email'] as String,
        isLoading: false,
      );

      await fetchMyClasses();
      FcmService.registerToken(isMember: true);
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

  Future<bool> joinClass(String inviteCode) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _dio.post('/auth/member/join', data: {'inviteCode': inviteCode});
      await fetchMyClasses();
      state = state.copyWith(isLoading: false, error: null);
      _syncWidgets();
      return true;
    } on DioException catch (e) {
      final msg = e.response?.data?['error'] as String? ?? '수업 참여에 실패했습니다';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<void> fetchMyClasses() async {
    try {
      final response = await _dio.get('/auth/member/my-classes');
      final list = (response.data['classes'] as List)
          .map((c) => MemberClass.fromJson(c as Map<String, dynamic>))
          .toList();
      state = state.copyWith(classes: list, error: null);
    } on DioException catch (e) {
      state = state.copyWith(
        error: e.response?.data?['error'] as String? ?? '참여 중인 수업을 불러오지 못했습니다',
      );
    } catch (_) {
      state = state.copyWith(error: '참여 중인 수업을 불러오지 못했습니다');
    }
  }

  Future<List<MemberSlot>> fetchSlots(String orgId, String date) async {
    try {
      final response = await _dio.get(
        '/auth/member/studios/$orgId/slots',
        queryParameters: {'date': date},
      );
      return (response.data as List)
          .map((json) => MemberSlot.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<MemberReservationNotice?> fetchReservationNotice(String orgId) async {
    try {
      final response = await _dio.get(
        '/auth/member/studios/$orgId/reservation-notice',
      );
      return MemberReservationNotice.fromJson(
        response.data as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> reserve({
    required String organizationId,
    required String coachId,
    required String date,
    required String startTime,
    required String endTime,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/member/reserve',
        data: {
          'organizationId': organizationId,
          'coachId': coachId,
          'date': date,
          'startTime': startTime,
          'endTime': endTime,
        },
      );
      _syncWidgets();
      return response.data['status'] as String? ?? 'CONFIRMED';
    } catch (_) {
      return null;
    }
  }

  Future<List<MemberPackage>> fetchMyPackages() async {
    try {
      final response = await _dio.get('/auth/member/packages');
      return (response.data['packages'] as List? ?? [])
          .map((json) => MemberPackage.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> requestPackagePause({
    required String memberPackageId,
    required String startDate,
    required String endDate,
    String? reason,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/member/packages/$memberPackageId/pause-request',
        data: {
          'startDate': startDate,
          'endDate': endDate,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
      return response.data['message'] as String?;
    } on DioException catch (e) {
      return e.response?.data?['error'] as String? ?? '패키지 정지 신청에 실패했습니다';
    } catch (_) {
      return '패키지 정지 신청에 실패했습니다';
    }
  }

  Future<String?> cancelReservation(String reservationId) async {
    try {
      await _dio.delete('/auth/member/reservations/$reservationId');
      _syncWidgets();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['error'] as String? ?? '취소에 실패했습니다';
    } catch (_) {
      return '취소에 실패했습니다';
    }
  }

  Future<List<MemberReservationSummary>> fetchMyReservations() async {
    try {
      final response = await _dio.get('/auth/member/my-reservations');
      return (response.data['reservations'] as List)
          .map(
            (json) =>
                MemberReservationSummary.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Switch from admin mode to member mode.
  /// Returns true if member token exists and switch succeeded.
  Future<bool> switchFromAdmin() async {
    final memberToken = ApiClient.getMemberAccessToken();
    if (memberToken == null) return false;

    final box = Hive.box(AppConstants.authBox);
    await box.put(AppConstants.isMemberAccountKey, true);
    await checkAuth();
    _syncWidgets();
    return state.status == MemberAuthStatus.authenticated;
  }

  Future<void> logout() async {
    await ApiClient.clearTokens();
    final box = Hive.box(AppConstants.authBox);
    await box.delete(AppConstants.isMemberAccountKey);
    await box.delete(AppConstants.memberNameKey);
    state = const MemberAuthState(status: MemberAuthStatus.unauthenticated);
    _syncWidgets();
  }

  Future<String?> deleteAccount() async {
    try {
      await _dio.delete('/auth/member/profile');
      await ApiClient.clearTokens();
      final box = Hive.box(AppConstants.authBox);
      await box.delete(AppConstants.isMemberAccountKey);
      await box.delete(AppConstants.memberNameKey);
      state = const MemberAuthState(status: MemberAuthStatus.unauthenticated);
      _syncWidgets();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['error'] as String? ?? '회원 탈퇴에 실패했습니다';
    } catch (_) {
      return '회원 탈퇴에 실패했습니다';
    }
  }
}

final memberAuthProvider =
    NotifierProvider<MemberAuthNotifier, MemberAuthState>(
      MemberAuthNotifier.new,
    );
