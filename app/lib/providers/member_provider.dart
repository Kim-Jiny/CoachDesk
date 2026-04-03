import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/member.dart';

class MemberListState {
  final List<Member> members;
  final bool isLoading;
  final String? error;

  const MemberListState({
    this.members = const [],
    this.isLoading = false,
    this.error,
  });

  MemberListState copyWith({
    List<Member>? members,
    bool? isLoading,
    String? error,
  }) {
    return MemberListState(
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MemberNotifier extends Notifier<MemberListState> {
  @override
  MemberListState build() => const MemberListState();

  Dio get _dio => ref.read(dioProvider);

  Future<void> fetchMembers({String? search}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get('/members', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
      });
      final members = (response.data as List)
          .map((json) => Member.fromJson(json as Map<String, dynamic>))
          .toList();
      state = state.copyWith(members: members, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data?['error'] as String? ?? 'Failed to load members',
      );
    }
  }

  Future<bool> createMember(Map<String, dynamic> data) async {
    try {
      await _dio.post('/members', data: data);
      await fetchMembers();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateMember(String id, Map<String, dynamic> data) async {
    try {
      await _dio.put('/members/$id', data: data);
      await fetchMembers();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteMember(String id) async {
    try {
      await _dio.delete('/members/$id');
      await fetchMembers();
      return true;
    } catch (_) {
      return false;
    }
  }
}

final memberProvider = NotifierProvider<MemberNotifier, MemberListState>(MemberNotifier.new);
