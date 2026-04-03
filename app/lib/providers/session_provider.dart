import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/session.dart';

class SessionState {
  final List<Session> sessions;
  final bool isLoading;
  final String? error;

  const SessionState({this.sessions = const [], this.isLoading = false, this.error});

  SessionState copyWith({List<Session>? sessions, bool? isLoading, String? error}) {
    return SessionState(
      sessions: sessions ?? this.sessions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState();

  Dio get _dio => ref.read(dioProvider);

  Future<void> fetchSessions({String? memberId, String? startDate, String? endDate}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get('/sessions', queryParameters: {
        'memberId': memberId,
        'startDate': startDate,
        'endDate': endDate,
      });
      final sessions = (response.data as List)
          .map((json) => Session.fromJson(json as Map<String, dynamic>))
          .toList();
      state = state.copyWith(sessions: sessions, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data?['error'] as String? ?? 'Failed to load sessions',
      );
    }
  }

  Future<bool> updateSession(String id, Map<String, dynamic> data) async {
    try {
      await _dio.put('/sessions/$id', data: data);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);
