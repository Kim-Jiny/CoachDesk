import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class CenterSettingsScreen extends ConsumerStatefulWidget {
  const CenterSettingsScreen({super.key});

  @override
  ConsumerState<CenterSettingsScreen> createState() =>
      _CenterSettingsScreenState();
}

class _CenterSettingsScreenState extends ConsumerState<CenterSettingsScreen> {
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

  bool get _canEdit {
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
      await dio.put('/organizations/${org['id']}', data: result);
      await _loadOrg();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('센터 정보가 저장되었습니다')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('센터 정보 저장에 실패했습니다')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DismissKeyboardOnTap(child: Scaffold(
      appBar: AppBar(
        title: const Text('센터 설정'),
        actions: [
          if (_canEdit)
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
          ? const Center(child: Text('센터 정보를 불러올 수 없습니다'))
          : RefreshIndicator(
              onRefresh: _loadOrg,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Center name & description
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppTheme.softShadow,
                    ),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Invite code
                  _SectionHeader(title: '초대 코드'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.vpn_key_rounded,
                            color: AppTheme.primaryColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _orgData!['inviteCode'] as String? ?? '',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
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
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '회원이 센터에 참여할 때 사용하는 코드입니다',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 20),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: _orgData!['inviteCode'] as String,
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('초대 코드가 복사되었습니다')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    ));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade700,
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

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.orgData['name'] as String? ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.orgData['description'] as String? ?? '',
    );
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
      title: const Text('센터 정보 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '센터명'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '설명'),
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
            });
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}
