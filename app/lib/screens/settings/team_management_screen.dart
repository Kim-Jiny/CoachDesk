import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';

class TeamManagementScreen extends ConsumerStatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  ConsumerState<TeamManagementScreen> createState() =>
      _TeamManagementScreenState();
}

class _TeamManagementScreenState extends ConsumerState<TeamManagementScreen> {
  Map<String, dynamic>? _orgData;
  List<Map<String, dynamic>> _joinRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadOrg();
    await _loadJoinRequests();
  }

  Future<void> _loadOrg() async {
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/organizations/mine');
      if (mounted) {
        setState(() {
          _orgData = response.data as Map<String, dynamic>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadJoinRequests() async {
    final orgId = ref.read(authProvider).selectedCenter?.id;
    if (orgId == null) return;
    final myRole = _orgData?['myRole'] as String?;
    if (myRole != 'OWNER') return;

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/centers/$orgId/join-requests');
      final data = response.data as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _joinRequests =
              (data['requests'] as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  bool get _isOwner => _orgData?['myRole'] == 'OWNER';

  Future<void> _reviewJoinRequest(
    String requestId, {
    required String action,
    String? role,
  }) async {
    final orgId = ref.read(authProvider).selectedCenter?.id;
    if (orgId == null) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.put(
        '/centers/$orgId/join-requests/$requestId',
        data: {
          'action': action,
          if (role != null) 'role': role, // ignore: use_null_aware_elements
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'APPROVE' ? '승인되었습니다' : '거절되었습니다'),
        ),
      );
      await _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('처리에 실패했습니다')),
      );
    }
  }

  Future<void> _showApproveDialog(Map<String, dynamic> request) async {
    String selectedRole = 'STAFF';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${request['userName']} 합류 승인'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${request['userEmail']}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              if (request['message'] != null &&
                  (request['message'] as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '메시지: ${request['message']}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              const Text('역할 선택',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...['MANAGER', 'STAFF', 'VIEWER'].map((role) {
                return RadioListTile<String>(
                  value: role,
                  groupValue: selectedRole,
                  title: Text(_roleName(role)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setDialogState(() => selectedRole = v!),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('승인'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _reviewJoinRequest(
        request['id'] as String,
        action: 'APPROVE',
        role: selectedRole,
      );
    }
  }

  Future<void> _changeMemberRole(Map<String, dynamic> member) async {
    final orgId = ref.read(authProvider).selectedCenter?.id;
    if (orgId == null) return;
    final currentRole = member['role'] as String?;

    String selectedRole = currentRole ?? 'STAFF';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${member['name']} 역할 변경'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['MANAGER', 'STAFF', 'VIEWER'].map((role) {
              return RadioListTile<String>(
                value: role,
                groupValue: selectedRole,
                title: Text(_roleName(role)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setDialogState(() => selectedRole = v!),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('변경'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedRole == currentRole) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.put(
        '/centers/$orgId/members/${member['id']}/role',
        data: {'role': selectedRole},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('역할이 변경되었습니다')),
      );
      await _loadOrg();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('역할 변경에 실패했습니다')),
      );
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final orgId = ref.read(authProvider).selectedCenter?.id;
    if (orgId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('팀원 제외'),
        content: Text('${member['name']}님을 센터에서 제외하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('제외'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/centers/$orgId/members/${member['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('팀원이 제외되었습니다')),
      );
      await _loadOrg();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('팀원 제외에 실패했습니다')),
      );
    }
  }

  static String _roleName(String? role) {
    return switch (role) {
      'OWNER' => '메인관리자',
      'MANAGER' => '운영관리자',
      'STAFF' => '스태프',
      'VIEWER' => '뷰어',
      _ => role ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('팀 관리')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orgData == null
              ? const Center(child: Text('팀 정보를 불러올 수 없습니다'))
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Join Requests (OWNER only)
                      if (_isOwner && _joinRequests.isNotEmpty) ...[
                        Row(
                          children: [
                            Text(
                              '합류 신청',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_joinRequests.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._joinRequests.map(
                          (request) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: AppTheme.softShadow,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            Colors.orange.shade100,
                                        child: Text(
                                          ((request['userName'] as String?) ??
                                              '?')[0],
                                          style: TextStyle(
                                            color: Colors.orange.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              request['userName'] as String? ??
                                                  '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              request['userEmail']
                                                      as String? ??
                                                  '',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (request['message'] != null &&
                                      (request['message'] as String)
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        request['message'] as String,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () =>
                                              _reviewJoinRequest(
                                            request['id'] as String,
                                            action: 'REJECT',
                                          ),
                                          child: const Text('거절'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: () =>
                                              _showApproveDialog(request),
                                          child: const Text('승인'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Members
                      Text(
                        '팀원',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...(_orgData!['members'] as List? ?? []).map((m) {
                        final role = m['role'] as String?;
                        final roleLabel = _roleName(role);
                        final isMe = m['id'] == authState.user?.id;
                        final isOwnerRole = role == 'OWNER';
                        final canManage = _isOwner && !isMe && !isOwnerRole;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: AppTheme.softShadow,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: isMe
                                    ? AppTheme.primaryColor
                                    : Colors.grey.shade400,
                                child: Text(
                                  (m['name'] as String? ?? '?')[0],
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Text(
                                '${m['name']}${isMe ? ' (나)' : ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                m['email'] as String? ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              trailing: canManage
                                  ? PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'change_role') {
                                          _changeMemberRole(
                                              m as Map<String, dynamic>);
                                        } else if (value == 'remove') {
                                          _removeMember(
                                              m as Map<String, dynamic>);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'change_role',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.swap_horiz,
                                                  size: 18),
                                              const SizedBox(width: 8),
                                              Text('역할 변경 ($roleLabel)'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'remove',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.person_remove_outlined,
                                                size: 18,
                                                color: Colors.red,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                '팀에서 제외',
                                                style: TextStyle(
                                                    color: Colors.red),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor
                                            .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        roleLabel,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
