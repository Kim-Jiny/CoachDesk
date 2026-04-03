import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/reservation.dart';

class ReservationState {
  final List<Reservation> reservations;
  final bool isLoading;
  final String? error;

  const ReservationState({
    this.reservations = const [],
    this.isLoading = false,
    this.error,
  });

  ReservationState copyWith({
    List<Reservation>? reservations,
    bool? isLoading,
    String? error,
  }) {
    return ReservationState(
      reservations: reservations ?? this.reservations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ReservationNotifier extends Notifier<ReservationState> {
  @override
  ReservationState build() => const ReservationState();

  Dio get _dio => ref.read(dioProvider);

  Future<void> fetchReservations({String? date, String? startDate, String? endDate}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get('/reservations', queryParameters: {
        'date': date,
        'startDate': startDate,
        'endDate': endDate,
      });
      final reservations = (response.data as List)
          .map((json) => Reservation.fromJson(json as Map<String, dynamic>))
          .toList();
      state = state.copyWith(reservations: reservations, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data?['error'] as String? ?? 'Failed to load reservations',
      );
    }
  }

  Future<bool> createReservation(Map<String, dynamic> data) async {
    try {
      await _dio.post('/reservations', data: data);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateStatus(String id, String status) async {
    try {
      await _dio.patch('/reservations/$id/status', data: {'status': status});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> completeReservation(String id, Map<String, dynamic> data) async {
    try {
      await _dio.post('/reservations/$id/complete', data: data);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final reservationProvider =
    NotifierProvider<ReservationNotifier, ReservationState>(ReservationNotifier.new);
