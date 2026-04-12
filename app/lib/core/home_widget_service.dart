import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/member_booking.dart';
import '../models/reservation.dart';
import 'api_client.dart';
import 'constants.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static const String adminWidgetProvider = 'AdminTodayClassesWidgetProvider';
  static const String memberWidgetProvider = 'MemberTodayClassesWidgetProvider';
  static const String adminIOSWidgetKind = 'AdminTodayClassesWidget';
  static const String memberIOSWidgetKind = 'MemberTodayClassesWidget';
  static const String appGroupId = 'group.com.jiny.coachdesk';

  static const String _adminHasAccessKey = 'widget_admin_has_access';
  static const String _adminItemsKey = 'widget_admin_items';
  static const String _adminUpdatedAtKey = 'widget_admin_updated_at';

  static const String _memberHasAccessKey = 'widget_member_has_access';
  static const String _memberItemsKey = 'widget_member_items';
  static const String _memberUpdatedAtKey = 'widget_member_updated_at';

  static Future<void> initialize() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(appGroupId);
    }
  }

  static Future<void> syncAll() async {
    await Future.wait([
      syncAdminWidget(),
      syncMemberWidget(),
    ]);
  }

  static Future<void> syncAdminWidget() async {
    final adminToken = ApiClient.getAdminAccessToken();
    if (adminToken == null || adminToken.isEmpty) {
      await _saveAdminState(hasAccess: false, items: const []);
      await _updateAdminWidget();
      return;
    }

    try {
      final profileDio = _buildDio(accessToken: adminToken);
      final profileResponse = await profileDio.get('/auth/profile');
      final organization = profileResponse.data['organization'] as Map<String, dynamic>?;
      final orgId = organization?['id'] as String?;
      if (orgId == null || orgId.isEmpty) {
        await _saveAdminState(hasAccess: false, items: const []);
        await _updateAdminWidget();
        return;
      }

      await ApiClient.saveOrgId(orgId);

      final reservationsDio = _buildDio(
        accessToken: adminToken,
        organizationId: orgId,
      );
      final date = _todayString();
      final response = await reservationsDio.get(
        '/reservations',
        queryParameters: {'date': date},
      );

      final reservations = (response.data as List)
          .map((json) => Reservation.fromJson(json as Map<String, dynamic>))
          .where(_shouldShowAdminReservation)
          .toList()
        ..sort(_compareByTime);

      final items = reservations.take(4).map((reservation) {
        return <String, String>{
          'primary': '${reservation.startTime} - ${reservation.endTime}',
          'secondary': reservation.memberName ?? '이름 없는 회원',
          'status': _reservationStatusLabel(reservation.status),
        };
      }).toList();

      await _saveAdminState(hasAccess: true, items: items);
    } catch (err) {
      debugPrint('Admin widget sync failed: $err');
      await _saveAdminState(hasAccess: true, items: const []);
    }

    await _updateAdminWidget();
  }

  static Future<void> syncMemberWidget() async {
    final memberToken = ApiClient.getMemberAccessToken();
    if (memberToken == null || memberToken.isEmpty) {
      await _saveMemberState(hasAccess: false, items: const []);
      await _updateMemberWidget();
      return;
    }

    try {
      final dio = _buildDio(accessToken: memberToken);
      final response = await dio.get('/auth/member/my-reservations');
      final reservations = (response.data['reservations'] as List? ?? const [])
          .map(
            (json) => MemberReservationSummary.fromJson(
              json as Map<String, dynamic>,
            ),
          )
          .where(_shouldShowMemberReservation)
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      final items = reservations.take(4).map((reservation) {
        final orgText = reservation.organizationName.trim();
        final coachText = reservation.coachName.trim();
        final secondary = [
          if (orgText.isNotEmpty) orgText,
          if (coachText.isNotEmpty) coachText,
        ].join(' · ');

        return <String, String>{
          'primary': '${reservation.startTime} - ${reservation.endTime}',
          'secondary': secondary.isEmpty ? '오늘 예약된 수업' : secondary,
          'status': _reservationStatusLabel(reservation.status),
        };
      }).toList();

      await _saveMemberState(hasAccess: true, items: items);
    } catch (err) {
      debugPrint('Member widget sync failed: $err');
      await _saveMemberState(hasAccess: true, items: const []);
    }

    await _updateMemberWidget();
  }

  static Dio _buildDio({
    required String accessToken,
    String? organizationId,
  }) {
    return Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
          if (organizationId != null && organizationId.isNotEmpty)
            'X-Organization-Id': organizationId,
        },
      ),
    );
  }

  static Future<void> _saveAdminState({
    required bool hasAccess,
    required List<Map<String, String>> items,
  }) async {
    await HomeWidget.saveWidgetData<bool>(_adminHasAccessKey, hasAccess);
    await HomeWidget.saveWidgetData<String>(_adminItemsKey, jsonEncode(items));
    await HomeWidget.saveWidgetData<String>(
      _adminUpdatedAtKey,
      _updatedAtLabel(),
    );
  }

  static Future<void> _saveMemberState({
    required bool hasAccess,
    required List<Map<String, String>> items,
  }) async {
    await HomeWidget.saveWidgetData<bool>(_memberHasAccessKey, hasAccess);
    await HomeWidget.saveWidgetData<String>(_memberItemsKey, jsonEncode(items));
    await HomeWidget.saveWidgetData<String>(
      _memberUpdatedAtKey,
      _updatedAtLabel(),
    );
  }

  static Future<void> _updateAdminWidget() {
    return HomeWidget.updateWidget(
      androidName: adminWidgetProvider,
      iOSName: adminIOSWidgetKind,
    );
  }

  static Future<void> _updateMemberWidget() {
    return HomeWidget.updateWidget(
      androidName: memberWidgetProvider,
      iOSName: memberIOSWidgetKind,
    );
  }

  static bool _shouldShowAdminReservation(Reservation reservation) {
    return _isToday(reservation.date) &&
        (reservation.status == 'PENDING' || reservation.status == 'CONFIRMED');
  }

  static bool _shouldShowMemberReservation(MemberReservationSummary reservation) {
    return _isToday(reservation.date) &&
        (reservation.status == 'PENDING' || reservation.status == 'CONFIRMED');
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
  }

  static int _compareByTime(Reservation a, Reservation b) {
    return a.startTime.compareTo(b.startTime);
  }

  static String _todayString() {
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  static String _updatedAtLabel() {
    return DateFormat('HH:mm').format(DateTime.now());
  }

  static String _reservationStatusLabel(String status) {
    switch (status) {
      case 'PENDING':
        return '대기';
      case 'CONFIRMED':
        return '확정';
      case 'COMPLETED':
        return '완료';
      case 'CANCELLED':
        return '취소';
      case 'NO_SHOW':
        return '노쇼';
      default:
        return status;
    }
  }
}
