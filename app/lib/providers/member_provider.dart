import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/member.dart';

class MemberListState {
  final List<Member> members;
  final List<MemberGroup> groups;
  final bool isLoading;
  final String? error;

  const MemberListState({
    this.members = const [],
    this.groups = const [],
    this.isLoading = false,
    this.error,
  });

  MemberListState copyWith({
    List<Member>? members,
    List<MemberGroup>? groups,
    bool? isLoading,
    String? error,
  }) {
    return MemberListState(
      members: members ?? this.members,
      groups: groups ?? this.groups,
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
      final responses = await Future.wait([
        _dio.get(
          '/members',
          queryParameters: {
            if (search != null && search.isNotEmpty) 'search': search,
          },
        ),
        _dio.get('/members/groups'),
      ]);
      final members = (responses[0].data as List)
          .map((json) => Member.fromJson(json as Map<String, dynamic>))
          .toList();
      final groups = (responses[1].data as List)
          .map((json) => MemberGroup.fromJson(json as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        members: members,
        groups: groups,
        isLoading: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error:
            e.response?.data?['error'] as String? ?? 'Failed to load members',
      );
    }
  }

  Future<bool> createGroup(String name) async {
    try {
      await _dio.post('/members/groups', data: {'name': name});
      await fetchMembers();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> moveMemberToGroup(String memberId, String? memberGroupId) async {
    try {
      await _dio.patch(
        '/members/$memberId/group',
        data: {'memberGroupId': memberGroupId},
      );
      await fetchMembers();
      return true;
    } catch (_) {
      return false;
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

final memberProvider = NotifierProvider<MemberNotifier, MemberListState>(
  MemberNotifier.new,
);
