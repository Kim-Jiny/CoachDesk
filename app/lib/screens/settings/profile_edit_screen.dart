import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _reservationNoticeTextController;
  late final TextEditingController _reservationOpenDaysBeforeController;
  late final TextEditingController _reservationOpenHoursBeforeController;
  late final TextEditingController _reservationCancelDeadlineMinutesController;
  late String _bookingMode;
  late String _reservationPolicy;
  Uint8List? _newReservationNoticeImageBytes;
  String? _newReservationNoticeImageBase64;
  String? _newReservationNoticeImageName;
  String? _newReservationNoticeImageContentType;
  String? _existingReservationNoticeImageUrl;
  bool _removeReservationNoticeImage = false;
  bool _isPickingImage = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _reservationNoticeTextController = TextEditingController(
      text: user?.reservationNoticeText ?? '',
    );
    _reservationOpenDaysBeforeController = TextEditingController(
      text: '${user?.reservationOpenDaysBefore ?? 30}',
    );
    _reservationOpenHoursBeforeController = TextEditingController(
      text: '${user?.reservationOpenHoursBefore ?? 0}',
    );
    _reservationCancelDeadlineMinutesController = TextEditingController(
      text: '${user?.reservationCancelDeadlineMinutes ?? 120}',
    );
    _bookingMode = user?.bookingMode ?? 'PRIVATE';
    _reservationPolicy = user?.reservationPolicy ?? 'AUTO_CONFIRM';
    _existingReservationNoticeImageUrl = user?.reservationNoticeImageUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
      if (mounted) setState(() => _isPickingImage = false);
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

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이름을 입력해주세요')));
      return;
    }

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예약 설정 값을 다시 확인해주세요')));
      return;
    }

    setState(() => _isSaving = true);
    final success = await ref
        .read(authProvider.notifier)
        .updateProfile(
          name: name,
          phone: _phoneController.text.trim(),
          bookingMode: _bookingMode,
          reservationPolicy: _reservationPolicy,
          reservationNoticeText:
              _reservationNoticeTextController.text.trim().isEmpty
              ? null
              : _reservationNoticeTextController.text.trim(),
          clearReservationNoticeText: _reservationNoticeTextController.text
              .trim()
              .isEmpty,
          reservationNoticeImageUrl: _removeReservationNoticeImage
              ? null
              : _existingReservationNoticeImageUrl,
          clearReservationNoticeImage: _removeReservationNoticeImage,
          reservationNoticeImageBase64: _newReservationNoticeImageBase64,
          reservationNoticeImageFileName: _newReservationNoticeImageName,
          reservationNoticeImageContentType:
              _newReservationNoticeImageContentType,
          reservationOpenDaysBefore: reservationOpenDaysBefore,
          reservationOpenHoursBefore: reservationOpenHoursBefore,
          reservationCancelDeadlineMinutes: reservationCancelDeadlineMinutes,
        );
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('프로필이 수정되었습니다')));
      Navigator.of(context).pop();
    } else {
      final error = ref.read(authProvider).error;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error ?? '프로필 수정에 실패했습니다')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final previewImage = _newReservationNoticeImageBytes;
    final currentImageUrl = _removeReservationNoticeImage
        ? null
        : _existingReservationNoticeImageUrl;

    return DismissKeyboardOnTap(child: Scaffold(
      appBar: AppBar(
        title: const Text('프로필 수정'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('저장'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar
            Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
                child: Text(
                  (user?.name ?? '?')[0],
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                user?.email ?? '',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ),
            const SizedBox(height: 28),

            // Name field
            Text(
              '이름',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '이름을 입력하세요',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Phone field
            Text(
              '연락처',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '연락처를 입력하세요 (선택)',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 28),

            Text(
              '예약 설정',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _bookingMode,
              decoration: const InputDecoration(
                labelText: '예약 모드',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'PRIVATE', child: Text('비공개 예약')),
                DropdownMenuItem(value: 'PUBLIC', child: Text('공개 예약')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _bookingMode = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reservationPolicy,
              decoration: const InputDecoration(
                labelText: '예약 확정 방식',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'AUTO_CONFIRM', child: Text('즉시 확정')),
                DropdownMenuItem(
                  value: 'REQUEST_APPROVAL',
                  child: Text('신청 후 승인'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _reservationPolicy = value);
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
                      border: OutlineInputBorder(),
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
                      border: OutlineInputBorder(),
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
                labelText: '취소 마감',
                suffixText: '분 전',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '예약 주의사항',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _reservationNoticeTextController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: '예약 전에 꼭 확인해야 하는 안내사항을 적어주세요',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryColor),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (previewImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
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
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  currentImageUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
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
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                alignment: Alignment.center,
                child: Text(
                  '등록된 안내 이미지가 없습니다',
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
          ],
        ),
      ),
    ));
  }
}
