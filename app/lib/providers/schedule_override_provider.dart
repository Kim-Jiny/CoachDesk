import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/schedule_override.dart';

class ScheduleOverrideState {
  final List<ScheduleOverride> overrides;
  final bool isLoading;
  final String? error;

  const ScheduleOverrideState({
    this.overrides = const [],
    this.isLoading = false,
    this.error,
  });

  ScheduleOverrideState copyWith({
    List<ScheduleOverride>? overrides,
    bool? isLoading,
    String? error,
  }) {
    return ScheduleOverrideState(
      overrides: overrides ?? this.overrides,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ScheduleOverrideNotifier extends Notifier<ScheduleOverrideState> {
  @override
  ScheduleOverrideState build() => const ScheduleOverrideState();

  Dio get _dio => ref.read(dioProvider);

  Future<void> fetchOverrides({required String startDate, required String endDate}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get('/schedules/overrides', queryParameters: {
        'startDate': startDate,
        'endDate': endDate,
      });
      final overrides = (response.data as List)
          .map((json) => ScheduleOverride.fromJson(json as Map<String, dynamic>))
          .toList();
      state = state.copyWith(overrides: overrides, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data?['error'] as String? ?? 'Failed to load overrides',
      );
    }
  }

  Future<bool> createOverride(Map<String, dynamic> data) async {
    try {
      await _dio.post('/schedules/overrides', data: data);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteOverride(String id) async {
    try {
      await _dio.delete('/schedules/overrides/$id');
      return true;
    } catch (_) {
      return false;
    }
  }
}

final scheduleOverrideProvider =
    NotifierProvider<ScheduleOverrideNotifier, ScheduleOverrideState>(ScheduleOverrideNotifier.new);
