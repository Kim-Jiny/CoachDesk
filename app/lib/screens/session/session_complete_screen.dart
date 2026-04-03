import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/package.dart';
import '../../models/reservation.dart';
import '../../providers/package_provider.dart';
import '../../providers/reservation_provider.dart';

class SessionCompleteScreen extends ConsumerStatefulWidget {
  final Reservation reservation;
  const SessionCompleteScreen({super.key, required this.reservation});

  @override
  ConsumerState<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends ConsumerState<SessionCompleteScreen> {
  String _attendance = 'PRESENT';
  MemberPackage? _selectedPackage;
  final _memoController = TextEditingController();
  final _feedbackController = TextEditingController();
  List<MemberPackage> _memberPackages = [];
  bool _isSubmitting = false;

  bool get _canComplete {
    final parts = widget.reservation.endTime.split(':').map(int.parse).toList();
    final endDateTime = DateTime(
      widget.reservation.date.year,
      widget.reservation.date.month,
      widget.reservation.date.day,
      parts[0],
      parts[1],
    );
    return !DateTime.now().isBefore(endDateTime);
  }

  @override
  void initState() {
    super.initState();
    _loadMemberPackages();
  }

  Future<void> _loadMemberPackages() async {
    final packages = await ref.read(packageProvider.notifier)
        .getMemberPackages(widget.reservation.memberId);
    setState(() {
      _memberPackages = packages.where((p) => p.status == 'ACTIVE').toList();
      if (_memberPackages.length == 1) _selectedPackage = _memberPackages.first;
    });
  }

  @override
  void dispose() {
    _memoController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (!_canComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수업 종료 시간 이후에만 완료 처리할 수 있습니다')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final success = await ref.read(reservationProvider.notifier).completeReservation(
      widget.reservation.id,
      {
        'attendance': _attendance,
        if (_selectedPackage != null) 'memberPackageId': _selectedPackage!.id,
        if (_memoController.text.isNotEmpty) 'memo': _memoController.text,
        if (_feedbackController.text.isNotEmpty) 'feedback': _feedbackController.text,
      },
    );

    setState(() => _isSubmitting = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('세션이 완료되었습니다')),
      );
      context.pop(true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('세션 완료에 실패했습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('세션 완료')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Reservation info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('예약 정보', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text('회원: ${widget.reservation.memberName ?? ''}'),
                    Text('시간: ${widget.reservation.startTime} - ${widget.reservation.endTime}'),
                  ],
                ),
              ),
            ),
            if (!_canComplete) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.orange.withValues(alpha: 0.1),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('수업 종료 시간 이후에만 세션 완료 처리를 할 수 있습니다.'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Attendance
            Text('출석 상태', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'PRESENT', label: Text('출석'), icon: Icon(Icons.check_circle_outline)),
                ButtonSegment(value: 'LATE', label: Text('지각'), icon: Icon(Icons.schedule)),
                ButtonSegment(value: 'NO_SHOW', label: Text('노쇼'), icon: Icon(Icons.cancel_outlined)),
              ],
              selected: {_attendance},
              onSelectionChanged: (v) => setState(() => _attendance = v.first),
            ),
            const SizedBox(height: 16),

            // Package selection
            if (_memberPackages.isNotEmpty) ...[
              DropdownButtonFormField<MemberPackage>(
                decoration: const InputDecoration(
                  labelText: '차감할 패키지',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                initialValue: _selectedPackage,
                items: _memberPackages.map((mp) {
                  return DropdownMenuItem(
                    value: mp,
                    child: Text(
                      '${mp.package?.name ?? ''} (잔여: ${mp.remainingSessions}/${mp.totalSessions})',
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedPackage = v),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Card(
                color: Colors.orange.withValues(alpha: 0.1),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Expanded(child: Text('활성 패키지가 없습니다. 패키지 없이 세션을 기록합니다.')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Memo
            TextFormField(
              controller: _memoController,
              decoration: const InputDecoration(
                labelText: '세션 메모',
                prefixIcon: Icon(Icons.note_outlined),
                hintText: '운동 내용, 특이사항 등',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Feedback
            TextFormField(
              controller: _feedbackController,
              decoration: const InputDecoration(
                labelText: '회원 피드백',
                prefixIcon: Icon(Icons.feedback_outlined),
                hintText: '회원에게 전달할 피드백',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: _isSubmitting || !_canComplete ? null : _complete,
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('세션 완료'),
            ),
          ],
        ),
      ),
    );
  }
}
