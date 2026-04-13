import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
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
  bool _isSaving = false;

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

  bool get _canEditOrg {
    final myRole = _orgData?['myRole'] as String?;
    return myRole == 'OWNER' || myRole == 'MANAGER';
  }

  Future<void> _editOrg() async {
    final org = _orgData;
    if (org == null) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _OrgEditDialog(orgData: org),
    );
    if (result == null) return;

    setState(() => _isSaving = true);
    try {
      final dio = ref.read(dioProvider);
      final payload = Map<String, dynamic>.from(result);

      final imageBase64 =
          payload.remove('reservationNoticeImageBase64') as String?;
      final imageFileName =
          payload.remove('reservationNoticeImageFileName') as String?;
      final imageContentType =
          payload.remove('reservationNoticeImageContentType') as String?;

      if (imageBase64 != null &&
          imageFileName != null &&
          imageContentType != null) {
        final uploadResponse = await dio.post(
          '/organizations/${org['id']}/reservation-notice-image',
          data: {
            'fileName': imageFileName,
            'contentType': imageContentType,
            'base64Data': imageBase64,
          },
        );
        payload['reservationNoticeImageUrl'] = uploadResponse.data['imageUrl'];
      }

      await dio.put('/organizations/${org['id']}', data: payload);
      await _loadOrg();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('조직 정보가 저장되었습니다')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('조직 정보 저장에 실패했습니다')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

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
              const Text('역할 선택', style: TextStyle(fontWeight: FontWeight.w600)),
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
    final noticeText = (_orgData?['reservationNoticeText'] as String?)?.trim();
    final noticeImageUrl = (_orgData?['reservationNoticeImageUrl'] as String?)
        ?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('팀 관리'),
        actions: [
          if (_canEditOrg)
            TextButton.icon(
              onPressed: _isSaving ? null : _editOrg,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined, size: 18),
              label: const Text('수정'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orgData == null
          ? const Center(child: Text('조직 정보를 불러올 수 없습니다'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Org info card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _orgData!['name'] as String? ?? '',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (_orgData!['description'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _orgData!['description'] as String,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (_orgData!['bookingMode'] != null) ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.public,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '예약 모드: ${(_orgData!['bookingMode'] as String) == 'PUBLIC' ? '공개' : '비공개'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_orgData!['reservationPolicy'] != null) ...[
                            Row(
                              children: [
                                const Icon(
                                  Icons.fact_check_outlined,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '예약 처리: ${(_orgData!['reservationPolicy'] as String) == 'REQUEST_APPROVAL' ? '신청 후 승인' : '즉시 확정'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.schedule_outlined,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '예약 오픈: 수업 ${(_orgData!['reservationOpenDaysBefore'] as int? ?? 30)}일 ${(_orgData!['reservationOpenHoursBefore'] as int? ?? 0)}시간 전부터\n취소 가능: 수업 ${(_orgData!['reservationCancelDeadlineMinutes'] as int? ?? 120)}분 전까지',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if ((noticeText?.isNotEmpty ?? false) ||
                              (noticeImageUrl?.isNotEmpty ?? false)) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '예약 주의사항이 설정되어 있습니다',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (noticeText?.isNotEmpty ?? false) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          noticeText!,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                      if (noticeImageUrl?.isNotEmpty ??
                                          false) ...[
                                        const SizedBox(height: 10),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.network(
                                            noticeImageUrl!,
                                            height: 120,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (
                                                  context,
                                                  error,
                                                  stackTrace,
                                                ) => Container(
                                                  height: 120,
                                                  color: Colors.grey.shade100,
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    '이미지를 불러오지 못했습니다',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            children: [
                              const Icon(
                                Icons.vpn_key,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text('초대 코드: ${_orgData!['inviteCode']}'),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '회원전용',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 16),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: _orgData!['inviteCode'] as String,
                                    ),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('초대 코드가 복사되었습니다'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Join Requests (OWNER only)
                  if (_isOwner && _joinRequests.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text(
                          '합류 신청',
                          style: Theme.of(context).textTheme.titleMedium
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
                    ..._joinRequests.map((request) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.orange.shade100,
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
                                        request['userName'] as String? ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        request['userEmail'] as String? ?? '',
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
                                    onPressed: () => _reviewJoinRequest(
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
                    )),
                  ],

                  const SizedBox(height: 24),

                  // Members
                  Text(
                    '팀원',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...(_orgData!['members'] as List? ?? []).map((m) {
                    final role = m['role'] as String?;
                    final roleLabel = _roleName(role);
                    final isMe = m['id'] == authState.user?.id;
                    final isOwnerRole = role == 'OWNER';
                    final canManage = _isOwner && !isMe && !isOwnerRole;

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isMe
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade400,
                          child: Text(
                            (m['name'] as String? ?? '?')[0],
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text('${m['name']}${isMe ? ' (나)' : ''}'),
                        subtitle: Text(m['email'] as String? ?? ''),
                        trailing: canManage
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'change_role') {
                                    _changeMemberRole(m as Map<String, dynamic>);
                                  } else if (value == 'remove') {
                                    _removeMember(m as Map<String, dynamic>);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'change_role',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.swap_horiz, size: 18),
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
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Chip(
                                label: Text(
                                  roleLabel,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                side: BorderSide.none,
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

class _OrgEditDialog extends StatefulWidget {
  final Map<String, dynamic> orgData;

  const _OrgEditDialog({required this.orgData});

  @override
  State<_OrgEditDialog> createState() => _OrgEditDialogState();
}

class _OrgEditDialogState extends State<_OrgEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _reservationNoticeTextController;
  late final TextEditingController _reservationOpenDaysBeforeController;
  late final TextEditingController _reservationOpenHoursBeforeController;
  late final TextEditingController _reservationCancelDeadlineMinutesController;
  late String _bookingMode;
  late String _reservationPolicy;
  String? _existingReservationNoticeImageUrl;
  Uint8List? _newReservationNoticeImageBytes;
  String? _newReservationNoticeImageBase64;
  String? _newReservationNoticeImageName;
  String? _newReservationNoticeImageContentType;
  bool _removeReservationNoticeImage = false;
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.orgData['name'] as String? ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.orgData['description'] as String? ?? '',
    );
    _reservationNoticeTextController = TextEditingController(
      text: widget.orgData['reservationNoticeText'] as String? ?? '',
    );
    _reservationOpenDaysBeforeController = TextEditingController(
      text: '${widget.orgData['reservationOpenDaysBefore'] as int? ?? 30}',
    );
    _reservationOpenHoursBeforeController = TextEditingController(
      text: '${widget.orgData['reservationOpenHoursBefore'] as int? ?? 0}',
    );
    _reservationCancelDeadlineMinutesController = TextEditingController(
      text:
          '${widget.orgData['reservationCancelDeadlineMinutes'] as int? ?? 120}',
    );
    _bookingMode = widget.orgData['bookingMode'] as String? ?? 'PRIVATE';
    _reservationPolicy =
        widget.orgData['reservationPolicy'] as String? ?? 'AUTO_CONFIRM';
    _existingReservationNoticeImageUrl =
        widget.orgData['reservationNoticeImageUrl'] as String?;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _reservationNoticeTextController.dispose();
    _reservationOpenDaysBeforeController.dispose();
    _reservationOpenHoursBeforeController.dispose();
    _reservationCancelDeadlineMinutesController.dispose();
    super.dispose();
  }

  Future<void> _pickReservationNoticeImage() async {
    if (_isPickingImage) return;

    setState(() => _isPickingImage = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final mimeType = switch (file.mimeType) {
        'image/png' => 'image/png',
        'image/webp' => 'image/webp',
        _ => 'image/jpeg',
      };

      if (!mounted) return;
      setState(() {
        _newReservationNoticeImageBytes = bytes;
        _newReservationNoticeImageBase64 = base64Encode(bytes);
        _newReservationNoticeImageName = file.name;
        _newReservationNoticeImageContentType = mimeType;
        _removeReservationNoticeImage = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  void _clearReservationNoticeImage() {
    setState(() {
      _newReservationNoticeImageBytes = null;
      _newReservationNoticeImageBase64 = null;
      _newReservationNoticeImageName = null;
      _newReservationNoticeImageContentType = null;
      _removeReservationNoticeImage = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final previewImage = _newReservationNoticeImageBytes;
    final currentImageUrl = _removeReservationNoticeImage
        ? null
        : _existingReservationNoticeImageUrl;

    return AlertDialog(
      title: const Text('조직 정보 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '조직명'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '설명'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reservationNoticeTextController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '예약 주의사항',
                hintText: '예약 전에 꼭 확인해야 하는 안내사항을 적어주세요',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '예약 안내 이미지',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            if (previewImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  previewImage,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else if (currentImageUrl != null &&
                currentImageUrl.trim().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  currentImageUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
                    width: double.infinity,
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: Text(
                      '이미지를 불러오지 못했습니다',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                alignment: Alignment.center,
                child: Text(
                  '등록된 이미지가 없습니다',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isPickingImage
                        ? null
                        : _pickReservationNoticeImage,
                    icon: _isPickingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: const Text('이미지 선택'),
                  ),
                ),
                const SizedBox(width: 8),
                if (previewImage != null ||
                    (currentImageUrl != null &&
                        currentImageUrl.trim().isNotEmpty))
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _clearReservationNoticeImage,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('이미지 삭제'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _bookingMode,
              decoration: const InputDecoration(labelText: '예약 모드'),
              items: const [
                DropdownMenuItem(value: 'PRIVATE', child: Text('비공개 예약')),
                DropdownMenuItem(value: 'PUBLIC', child: Text('공개 예약')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _bookingMode = value);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reservationPolicy,
              decoration: const InputDecoration(labelText: '예약 확정 방식'),
              items: const [
                DropdownMenuItem(value: 'AUTO_CONFIRM', child: Text('즉시 확정')),
                DropdownMenuItem(
                  value: 'REQUEST_APPROVAL',
                  child: Text('신청 후 승인'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _reservationPolicy = value);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reservationOpenDaysBeforeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '예약 오픈 일수',
                      suffixText: '일',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _reservationOpenHoursBeforeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '예약 오픈 시간',
                      suffixText: '시간',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reservationCancelDeadlineMinutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '예약 취소 마감',
                suffixText: '분 전',
                hintText: '수업 시작 몇 분 전까지 취소 허용',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            final reservationOpenDaysBefore = int.tryParse(
              _reservationOpenDaysBeforeController.text.trim(),
            );
            final reservationOpenHoursBefore = int.tryParse(
              _reservationOpenHoursBeforeController.text.trim(),
            );
            final reservationCancelDeadlineMinutes = int.tryParse(
              _reservationCancelDeadlineMinutesController.text.trim(),
            );
            if (reservationOpenDaysBefore == null ||
                reservationOpenDaysBefore < 0 ||
                reservationOpenHoursBefore == null ||
                reservationOpenHoursBefore < 0 ||
                reservationOpenHoursBefore > 23 ||
                reservationCancelDeadlineMinutes == null ||
                reservationCancelDeadlineMinutes < 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('예약 가능/취소 설정 값을 다시 확인해주세요')),
              );
              return;
            }
            Navigator.pop(context, {
              'name': name,
              'description': _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              'reservationNoticeText':
                  _reservationNoticeTextController.text.trim().isEmpty
                  ? null
                  : _reservationNoticeTextController.text.trim(),
              'reservationNoticeImageUrl': _removeReservationNoticeImage
                  ? null
                  : _existingReservationNoticeImageUrl,
              if (_newReservationNoticeImageBase64 != null)
                'reservationNoticeImageBase64':
                    _newReservationNoticeImageBase64,
              if (_newReservationNoticeImageName != null)
                'reservationNoticeImageFileName':
                    _newReservationNoticeImageName,
              if (_newReservationNoticeImageContentType != null)
                'reservationNoticeImageContentType':
                    _newReservationNoticeImageContentType,
              'bookingMode': _bookingMode,
              'reservationPolicy': _reservationPolicy,
              'reservationOpenDaysBefore': reservationOpenDaysBefore,
              'reservationOpenHoursBefore': reservationOpenHoursBefore,
              'reservationCancelDeadlineMinutes':
                  reservationCancelDeadlineMinutes,
            });
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}
