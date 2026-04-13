import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('센터 정보가 저장되었습니다')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('센터 정보 저장에 실패했습니다')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noticeText =
        (_orgData?['reservationNoticeText'] as String?)?.trim();
    final noticeImageUrl =
        (_orgData?['reservationNoticeImageUrl'] as String?)?.trim();

    return Scaffold(
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
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

                      // Reservation settings
                      _SectionHeader(title: '예약 설정'),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppTheme.softShadow,
                        ),
                        child: Column(
                          children: [
                            if (_orgData!['bookingMode'] != null)
                              _InfoRow(
                                icon: Icons.public,
                                label: '예약 모드',
                                value: (_orgData!['bookingMode'] as String) ==
                                        'PUBLIC'
                                    ? '공개'
                                    : '비공개',
                              ),
                            if (_orgData!['reservationPolicy'] != null) ...[
                              const Divider(height: 20),
                              _InfoRow(
                                icon: Icons.fact_check_outlined,
                                label: '예약 처리',
                                value: (_orgData!['reservationPolicy']
                                            as String) ==
                                        'REQUEST_APPROVAL'
                                    ? '신청 후 승인'
                                    : '즉시 확정',
                              ),
                            ],
                            const Divider(height: 20),
                            _InfoRow(
                              icon: Icons.schedule_outlined,
                              label: '예약 오픈',
                              value:
                                  '수업 ${_orgData!['reservationOpenDaysBefore'] as int? ?? 30}일 ${_orgData!['reservationOpenHoursBefore'] as int? ?? 0}시간 전부터',
                            ),
                            const Divider(height: 20),
                            _InfoRow(
                              icon: Icons.timer_off_outlined,
                              label: '취소 마감',
                              value:
                                  '수업 ${_orgData!['reservationCancelDeadlineMinutes'] as int? ?? 120}분 전까지',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Notice
                      if ((noticeText?.isNotEmpty ?? false) ||
                          (noticeImageUrl?.isNotEmpty ?? false)) ...[
                        _SectionHeader(title: '예약 주의사항'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (noticeText?.isNotEmpty ?? false)
                                Text(
                                  noticeText!,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    height: 1.5,
                                  ),
                                ),
                              if (noticeImageUrl?.isNotEmpty ?? false) ...[
                                if (noticeText?.isNotEmpty ?? false)
                                  const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    noticeImageUrl!,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      height: 120,
                                      color: Colors.grey.shade100,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '이미지를 불러오지 못했습니다',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

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
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.1),
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
                                        _orgData!['inviteCode'] as String? ??
                                            '',
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
                                          color: Colors.blue
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
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
                                  const SnackBar(
                                    content: Text('초대 코드가 복사되었습니다'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
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
                    onPressed:
                        _isPickingImage ? null : _pickReservationNoticeImage,
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
                DropdownMenuItem(
                    value: 'AUTO_CONFIRM', child: Text('즉시 확정')),
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
                const SnackBar(
                    content: Text('예약 가능/취소 설정 값을 다시 확인해주세요')),
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
