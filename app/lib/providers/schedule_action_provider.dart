import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';

class ScheduleActionResult {
  final bool success;
  final String? error;

  const ScheduleActionResult({required this.success, this.error});
}

class ScheduleActionNotifier extends Notifier<void> {
  @override
  void build() {}

  Dio get _dio => ref.read(dioProvider);

  Future<ScheduleActionResult> moveSlot({
    required String coachId,
    required DateTime date,
    required String currentStartTime,
    required String currentEndTime,
    required String newStartTime,
    required String newEndTime,
    required int slotDuration,
    required int maxCapacity,
    required bool isPublic,
  }) async {
    try {
      await _dio.post(
        '/schedules/move-slot',
        data: {
          'coachId': coachId,
          'date': DateFormat('yyyy-MM-dd').format(date),
          'currentStartTime': currentStartTime,
          'currentEndTime': currentEndTime,
          'newStartTime': newStartTime,
          'newEndTime': newEndTime,
          'slotDuration': slotDuration,
          'maxCapacity': maxCapacity,
          'isPublic': isPublic,
        },
      );
      return const ScheduleActionResult(success: true);
    } on DioException catch (e) {
      return ScheduleActionResult(
        success: false,
        error: e.response?.data?['error'] as String?,
      );
    } catch (_) {
      return const ScheduleActionResult(success: false);
    }
  }

  Future<ScheduleActionResult> setSlotVisibility({
    required String coachId,
    required DateTime date,
    required String startTime,
    required String endTime,
    required bool baseIsPublic,
    String? visibilityOverrideId,
  }) async {
    try {
      if (visibilityOverrideId != null && visibilityOverrideId.isNotEmpty) {
        await _dio.delete('/schedules/overrides/$visibilityOverrideId');
      } else {
        await _dio.post(
          '/schedules/overrides',
          data: {
            'coachId': coachId,
            'date': DateFormat('yyyy-MM-dd').format(date),
            'type': baseIsPublic ? 'HIDDEN' : 'VISIBLE',
            'startTime': startTime,
            'endTime': endTime,
          },
        );
      }
      return const ScheduleActionResult(success: true);
    } on DioException catch (e) {
      return ScheduleActionResult(
        success: false,
        error: e.response?.data?['error'] as String?,
      );
    } catch (_) {
      return const ScheduleActionResult(success: false);
    }
  }

  Future<ScheduleActionResult> closeSlot({
    required String coachId,
    required DateTime date,
    required String startTime,
    required String endTime,
  }) async {
    try {
      await _dio.post(
        '/schedules/close-slot',
        data: {
          'coachId': coachId,
          'date': DateFormat('yyyy-MM-dd').format(date),
          'startTime': startTime,
          'endTime': endTime,
        },
      );
      return const ScheduleActionResult(success: true);
    } on DioException catch (e) {
      return ScheduleActionResult(
        success: false,
        error: e.response?.data?['error'] as String?,
      );
    } catch (_) {
      return const ScheduleActionResult(success: false);
    }
  }

  Future<ScheduleActionResult> createOpenSlot({
    required DateTime date,
    required String startTime,
    required String endTime,
    required int slotDuration,
    required int breakMinutes,
    required int maxCapacity,
    required bool isPublic,
  }) async {
    try {
      await _dio.post(
        '/schedules/overrides',
        data: {
          'date': DateFormat('yyyy-MM-dd').format(date),
          'type': 'OPEN',
          'startTime': startTime,
          'endTime': endTime,
          'slotDuration': slotDuration,
          'breakMinutes': breakMinutes,
          'maxCapacity': maxCapacity,
          'isPublic': isPublic,
        },
      );
      return const ScheduleActionResult(success: true);
    } on DioException catch (e) {
      return ScheduleActionResult(
        success: false,
        error: e.response?.data?['error'] as String?,
      );
    } catch (_) {
      return const ScheduleActionResult(success: false);
    }
  }

  Future<ScheduleActionResult> shiftDaySchedule({
    required String coachId,
    required DateTime date,
    required String fromStartTime,
    required int deltaMinutes,
  }) async {
    try {
      await _dio.post(
        '/schedules/shift-day',
        data: {
          'coachId': coachId,
          'date': DateFormat('yyyy-MM-dd').format(date),
          'fromStartTime': fromStartTime,
          'deltaMinutes': deltaMinutes,
        },
      );
      return const ScheduleActionResult(success: true);
    } on DioException catch (e) {
      return ScheduleActionResult(
        success: false,
        error: e.response?.data?['error'] as String?,
      );
    } catch (_) {
      return const ScheduleActionResult(success: false);
    }
  }
}

final scheduleActionProvider = NotifierProvider<ScheduleActionNotifier, void>(
  ScheduleActionNotifier.new,
);
