import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';

class ScheduleSlotState {
  final List<Map<String, dynamic>> slots;
  final bool isLoading;
  final String? error;

  const ScheduleSlotState({
    this.slots = const [],
    this.isLoading = false,
    this.error,
  });

  ScheduleSlotState copyWith({
    List<Map<String, dynamic>>? slots,
    bool? isLoading,
    String? error,
  }) {
    return ScheduleSlotState(
      slots: slots ?? this.slots,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ScheduleSlotNotifier extends Notifier<ScheduleSlotState> {
  @override
  ScheduleSlotState build() => const ScheduleSlotState();

  Dio get _dio => ref.read(dioProvider);

  Future<void> fetchSlots({
    required DateTime date,
    bool includePast = true,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get(
        '/schedules/slots',
        queryParameters: {
          'date': DateFormat('yyyy-MM-dd').format(date),
          'includePast': includePast,
        },
      );

      final data = response.data;
      final slots = switch (data) {
        List() => data
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        Map<String, dynamic>() when data['slots'] is List => (data['slots'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        _ => <Map<String, dynamic>>[],
      };

      state = state.copyWith(
        slots: slots,
        isLoading: false,
        error: null,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        slots: const [],
        isLoading: false,
        error: e.response?.data?['error'] as String? ?? '스케줄 슬롯을 불러오지 못했습니다',
      );
    } catch (_) {
      state = state.copyWith(
        slots: const [],
        isLoading: false,
        error: '스케줄 슬롯을 불러오지 못했습니다',
      );
    }
  }
}

final scheduleSlotProvider =
    NotifierProvider<ScheduleSlotNotifier, ScheduleSlotState>(
      ScheduleSlotNotifier.new,
    );
