import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/package_provider.dart';

/// 관리자가 회원 패키지의 만료일·회차를 조정할 때 사용하는 바텀시트.
/// 반환값이 true면 조정 성공, false/null이면 취소 혹은 실패.
Future<bool?> showPackageAdjustSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String memberPackageId,
  required int remainingSessions,
  required int totalSessions,
  required DateTime? expiryDate,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: _PackageAdjustSheet(
        ref: ref,
        memberPackageId: memberPackageId,
        remainingSessions: remainingSessions,
        totalSessions: totalSessions,
        expiryDate: expiryDate,
      ),
    ),
  );
}

enum _AdjustChoice {
  extendExpiry,
  shortenExpiry,
  addSessions,
  deductSessions,
}

String _typeString(_AdjustChoice choice) => switch (choice) {
      _AdjustChoice.extendExpiry => 'EXTEND_EXPIRY',
      _AdjustChoice.shortenExpiry => 'SHORTEN_EXPIRY',
      _AdjustChoice.addSessions => 'ADD_SESSIONS',
      _AdjustChoice.deductSessions => 'DEDUCT_SESSIONS',
    };

class _PackageAdjustSheet extends StatefulWidget {
  final WidgetRef ref;
  final String memberPackageId;
  final int remainingSessions;
  final int totalSessions;
  final DateTime? expiryDate;

  const _PackageAdjustSheet({
    required this.ref,
    required this.memberPackageId,
    required this.remainingSessions,
    required this.totalSessions,
    required this.expiryDate,
  });

  @override
  State<_PackageAdjustSheet> createState() => _PackageAdjustSheetState();
}

class _PackageAdjustSheetState extends State<_PackageAdjustSheet> {
  _AdjustChoice? _choice;
  final _sessionController = TextEditingController();
  final _reasonController = TextEditingController();
  DateTime? _pickedDate;
  bool _submitting = false;

  @override
  void dispose() {
    _sessionController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final base = _pickedDate ?? widget.expiryDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 2),
      lastDate: DateTime(base.year + 5),
    );
    if (picked != null) {
      setState(() => _pickedDate = picked);
    }
  }

  bool get _isSession =>
      _choice == _AdjustChoice.addSessions ||
      _choice == _AdjustChoice.deductSessions;

  bool get _needsConfirm =>
      _choice == _AdjustChoice.shortenExpiry ||
      _choice == _AdjustChoice.deductSessions;

  String? _validate() {
    if (_choice == null) return '조정 유형을 선택해주세요';
    if (_isSession) {
      final delta = int.tryParse(_sessionController.text.trim());
      if (delta == null || delta <= 0) return '1 이상의 숫자를 입력해주세요';
      if (_choice == _AdjustChoice.deductSessions &&
          delta > widget.remainingSessions) {
        return '잔여 ${widget.remainingSessions}회보다 많이 차감할 수 없습니다';
      }
    } else {
      if (_pickedDate == null) return '새 만료일을 선택해주세요';
      final current = widget.expiryDate;
      if (current != null) {
        final picked = DateTime(
          _pickedDate!.year,
          _pickedDate!.month,
          _pickedDate!.day,
        );
        final curr = DateTime(current.year, current.month, current.day);
        if (_choice == _AdjustChoice.extendExpiry && !picked.isAfter(curr)) {
          return '연장은 현재 만료일보다 뒤 날짜여야 합니다';
        }
        if (_choice == _AdjustChoice.shortenExpiry && !picked.isBefore(curr)) {
          return '단축은 현재 만료일보다 앞 날짜여야 합니다';
        }
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    if (_needsConfirm) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('한번 더 확인해주세요'),
          content: Text(
            _choice == _AdjustChoice.shortenExpiry
                ? '만료일을 ${DateFormat('yyyy.MM.dd').format(_pickedDate!)} 로 단축합니다. 진행할까요?'
                : '회차를 ${_sessionController.text.trim()}회 차감합니다. 진행할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade400,
              ),
              child: const Text('진행'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _submitting = true);
    final result = await widget.ref
        .read(packageProvider.notifier)
        .adjustMemberPackage(
          memberPackageId: widget.memberPackageId,
          type: _typeString(_choice!),
          sessionDelta: _isSession
              ? int.parse(_sessionController.text.trim())
              : null,
          newExpiryDate: !_isSession
              ? DateFormat('yyyy-MM-dd').format(_pickedDate!)
              : null,
          reason: _reasonController.text.trim().isEmpty
              ? null
              : _reasonController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result.success) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? '조정에 실패했습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentExpiry = widget.expiryDate == null
        ? '무제한'
        : DateFormat('yyyy.MM.dd').format(widget.expiryDate!);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '패키지 조정',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '현재 잔여 ${widget.remainingSessions}/${widget.totalSessions}회 · 만료일 $currentExpiry',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _AdjustChoice.values.map((choice) {
                final label = switch (choice) {
                  _AdjustChoice.extendExpiry => '만료일 연장',
                  _AdjustChoice.shortenExpiry => '만료일 단축',
                  _AdjustChoice.addSessions => '회차 추가',
                  _AdjustChoice.deductSessions => '회차 차감',
                };
                final selected = _choice == choice;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() {
                    _choice = choice;
                    _pickedDate = null;
                    _sessionController.clear();
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_isSession)
              TextField(
                controller: _sessionController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _choice == _AdjustChoice.addSessions
                      ? '추가할 회차 수'
                      : '차감할 회차 수',
                  border: const OutlineInputBorder(),
                ),
              )
            else if (_choice != null)
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event_rounded),
                label: Text(
                  _pickedDate == null
                      ? '새 만료일 선택'
                      : DateFormat('yyyy.MM.dd').format(_pickedDate!),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '사유 (선택)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('적용'),
            ),
          ],
        ),
      ),
    );
  }
}
