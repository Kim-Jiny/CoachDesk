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
                              const SizedBox(width: 8),
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
            });
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}
