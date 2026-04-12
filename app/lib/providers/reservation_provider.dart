import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/home_widget_service.dart';
import '../core/socket_service.dart';
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

class ReservationCreateResult {
  final bool success;
  final String? error;
  final String? errorCode;

  const ReservationCreateResult({
    required this.success,
    this.error,
    this.errorCode,
  });
}

class ReservationNotifier extends Notifier<ReservationState> {
  void _syncWidgets() {
    unawaited(HomeWidgetService.syncAll());
  }

  @override
  ReservationState build() {
    _setupSocketListeners();
    return const ReservationState();
  }

  Dio get _dio => ref.read(dioProvider);

  void _setupSocketListeners() {
    final socket = SocketService.instance;

    void registerListeners() {
      socket.on('reservation:created', _onReservationCreated);
      socket.on('reservation:updated', _onReservationUpdated);
      socket.on('reservation:cancelled', _onReservationCancelled);
    }

    // Register now (if connected) AND on every future connect
    registerListeners();
    socket.addConnectCallback(registerListeners);

    ref.onDispose(() {
      socket.off('reservation:created', _onReservationCreated);
      socket.off('reservation:updated', _onReservationUpdated);
      socket.off('reservation:cancelled', _onReservationCancelled);
      socket.removeConnectCallback(registerListeners);
    });
  }

  void _onReservationCreated(dynamic data) {
    if (data is! Map) return;
    try {
      final reservation = Reservation.fromJson(Map<String, dynamic>.from(data));
      // Avoid duplicates
      if (state.reservations.any((r) => r.id == reservation.id)) return;
      final reservations = [...state.reservations, reservation];
      reservations.sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.startTime.compareTo(b.startTime);
      });
      state = state.copyWith(reservations: reservations);
      _syncWidgets();
    } catch (_) {}
  }

  void _onReservationUpdated(dynamic data) {
    if (data is! Map) return;
    try {
      final updated = Reservation.fromJson(Map<String, dynamic>.from(data));
      final reservations = state.reservations.map((r) {
        return r.id == updated.id ? updated : r;
      }).toList();
      state = state.copyWith(reservations: reservations);
      _syncWidgets();
    } catch (_) {}
  }

  void _onReservationCancelled(dynamic data) {
    if (data is! Map) return;
    try {
      final cancelled = Reservation.fromJson(Map<String, dynamic>.from(data));
      final reservations = state.reservations.map((r) {
        return r.id == cancelled.id ? cancelled : r;
      }).toList();
      state = state.copyWith(reservations: reservations);
      _syncWidgets();
    } catch (_) {}
  }

  Future<void> fetchReservations({
    String? date,
    String? startDate,
    String? endDate,
    String? status,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final params = <String, dynamic>{};
      if (date != null) params['date'] = date;
      if (startDate != null) params['startDate'] = startDate;
      if (endDate != null) params['endDate'] = endDate;
      if (status != null && status.isNotEmpty) params['status'] = status;
      final response = await _dio.get('/reservations', queryParameters: params);
      final reservations = (response.data as List)
          .map((json) => Reservation.fromJson(json as Map<String, dynamic>))
          .toList();
      state = state.copyWith(reservations: reservations, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error:
            e.response?.data?['error'] as String? ??
            'Failed to load reservations',
      );
    }
  }

  Future<ReservationCreateResult> createReservation(
    Map<String, dynamic> data,
  ) async {
    try {
      await _dio.post('/reservations', data: data);
      _syncWidgets();
      return const ReservationCreateResult(success: true);
    } on DioException catch (e) {
      return ReservationCreateResult(
        success: false,
        error: e.response?.data?['error'] as String?,
        errorCode: e.response?.data?['code'] as String?,
      );
    } catch (_) {
      return const ReservationCreateResult(success: false, error: '예약에 실패했습니다');
    }
  }

  Future<bool> updateStatus(String id, String status) async {
    try {
      await _dio.patch('/reservations/$id/status', data: {'status': status});
      _syncWidgets();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> completeReservation(String id, Map<String, dynamic> data) async {
    try {
      await _dio.post('/reservations/$id/complete', data: data);
      _syncWidgets();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateMemo(
    String id, {
    required String quickMemo,
    required String memo,
  }) async {
    try {
      await _dio.patch(
        '/reservations/$id/memo',
        data: {'quickMemo': quickMemo, 'memo': memo},
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

final reservationProvider =
    NotifierProvider<ReservationNotifier, ReservationState>(
      ReservationNotifier.new,
    );
