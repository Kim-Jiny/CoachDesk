import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../providers/auth_provider.dart';

class TeamManagementScreen extends ConsumerStatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  ConsumerState<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends ConsumerState<TeamManagementScreen> {
  Map<String, dynamic>? _orgData;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadOrg();
  }

  Future<void> _loadOrg() async {
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/organizations/mine');
      setState(() {
        _orgData = response.data as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  bool get _canEditOrg {
    final myRole = _orgData?['myRole'] as String?;
    return myRole == 'OWNER' || myRole == 'ADMIN';
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
      await dio.put('/organizations/${org['id']}', data: result);
      await _loadOrg();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('조직 정보가 저장되었습니다')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('조직 정보 저장에 실패했습니다')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

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
                  onRefresh: _loadOrg,
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
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (_orgData!['description'] != null) ...[
                                const SizedBox(height: 4),
                                Text(_orgData!['description'] as String, style: TextStyle(color: Colors.grey.shade600)),
                              ],
                              const SizedBox(height: 12),
                              if (_orgData!['bookingMode'] != null) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.public, size: 16, color: Colors.grey),
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
                                    const Icon(Icons.fact_check_outlined, size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    Text(
                                      '예약 처리: ${(_orgData!['reservationPolicy'] as String) == 'REQUEST_APPROVAL' ? '신청 후 승인' : '즉시 확정'}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],
                              Row(
                                children: [
                                  const Icon(Icons.vpn_key, size: 16, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Text('초대 코드: ${_orgData!['inviteCode']}'),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 16),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: _orgData!['inviteCode'] as String));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('초대 코드가 복사되었습니다')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Members
                      Text('팀원', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...(_orgData!['members'] as List? ?? []).map((m) {
                        final roleLabel = switch (m['role'] as String?) {
                          'OWNER' => '소유자',
                          'ADMIN' => '관리자',
                          'COACH' => '코치',
                          _ => m['role'] ?? '',
                        };
                        final isMe = m['id'] == authState.user?.id;
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
                            trailing: Chip(
                              label: Text(roleLabel, style: const TextStyle(fontSize: 11)),
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
  late String _bookingMode;
  late String _reservationPolicy;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.orgData['name'] as String? ?? '');
    _descriptionController = TextEditingController(text: widget.orgData['description'] as String? ?? '');
    _bookingMode = widget.orgData['bookingMode'] as String? ?? 'PRIVATE';
    _reservationPolicy = widget.orgData['reservationPolicy'] as String? ?? 'AUTO_CONFIRM';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                DropdownMenuItem(value: 'REQUEST_APPROVAL', child: Text('신청 후 승인')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _reservationPolicy = value);
                }
              },
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
            Navigator.pop(context, {
              'name': name,
              'description': _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              'bookingMode': _bookingMode,
              'reservationPolicy': _reservationPolicy,
            });
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}
