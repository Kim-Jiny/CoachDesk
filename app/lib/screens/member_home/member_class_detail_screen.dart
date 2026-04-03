import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/member_booking.dart';
import '../../providers/member_auth_provider.dart';

class MemberClassDetailScreen extends ConsumerStatefulWidget {
  final String orgId;
  final String organizationName;

  const MemberClassDetailScreen({
    super.key,
    required this.orgId,
    required this.organizationName,
  });

  @override
  ConsumerState<MemberClassDetailScreen> createState() => _MemberClassDetailScreenState();
}

class _MemberClassDetailScreenState extends ConsumerState<MemberClassDetailScreen> {
  late DateTime _selectedDate;
  List<MemberSlot> _slots = [];
  List<MemberReservationSummary> _myReservations = [];
  bool _isLoadingSlots = false;
  bool _isLoadingReservations = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadSlots(), _loadReservations()]);
  }

  Future<void> _loadSlots() async {
    setState(() => _isLoadingSlots = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final slots = await ref.read(memberAuthProvider.notifier).fetchSlots(widget.orgId, dateStr);
    if (mounted) setState(() { _slots = slots; _isLoadingSlots = false; });
  }

  Future<void> _loadReservations() async {
    setState(() => _isLoadingReservations = true);
    final reservations = await ref.read(memberAuthProvider.notifier).fetchMyReservations();
    if (mounted) {
      setState(() {
        _myReservations = reservations
            .where((reservation) => reservation.organizationId == widget.orgId)
            .toList();
        _isLoadingReservations = false;
      });
    }
  }

  Future<void> _reserve(MemberSlot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('예약 확인'),
        content: Text(
          '${slot.coachName} 코치\n'
          '${DateFormat('M월 d일 (E)', 'ko').format(_selectedDate)}\n'
          '${slot.startTime} - ${slot.endTime}\n\n'
          '예약하시겠습니까?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('예약')),
        ],
      ),
    );
    if (confirmed != true) return;

    final status = await ref.read(memberAuthProvider.notifier).reserve(
      organizationId: widget.orgId,
      coachId: slot.coachId,
      date: DateFormat('yyyy-MM-dd').format(_selectedDate),
      startTime: slot.startTime,
      endTime: slot.endTime,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == null
                ? '예약에 실패했습니다'
                : status == 'PENDING'
                    ? '예약 신청이 접수되었습니다. 승인 후 확정됩니다.'
                    : '예약이 완료되었습니다!',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (status != null) _loadData();
    }
  }

  Future<void> _cancelReservation(MemberReservationSummary reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('예약 취소'),
        content: const Text('이 예약을 취소하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('아니오')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final success = await ref.read(memberAuthProvider.notifier)
        .cancelReservation(reservation.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '예약이 취소되었습니다' : '취소에 실패했습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (success) _loadData();
    }
  }

  MemberReservationSummary? _findExistingReservationForSlot(MemberSlot slot) {
    for (final reservation in _myReservations) {
      final status = reservation.status;
      if (reservation.organizationId != widget.orgId) continue;
      if (!_isSameDate(reservation.date, _selectedDate)) continue;
      if (reservation.coachId != slot.coachId) continue;
      if (reservation.startTime != slot.startTime) continue;
      if (status != 'PENDING' && status != 'CONFIRMED' && status != 'COMPLETED') continue;
      return reservation;
    }
    return null;
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year && left.month == right.month && left.day == right.day;
  }

  _MemberSlotUiState _buildSlotUiState(MemberSlot slot) {
    final existingReservation = _findExistingReservationForSlot(slot);
    if (existingReservation != null) {
      return switch (existingReservation.status) {
        'PENDING' => _MemberSlotUiState(
            label: '신청 완료',
            message: '승인되면 자동으로 확정돼요',
            backgroundColor: Colors.orange.withValues(alpha: 0.1),
            foregroundColor: Colors.orange.shade700,
          ),
        'COMPLETED' => _MemberSlotUiState(
            label: '수업 완료',
            message: '진행이 끝난 수업이에요',
            backgroundColor: Colors.grey.withValues(alpha: 0.12),
            foregroundColor: Colors.grey.shade700,
          ),
        _ => _MemberSlotUiState(
            label: '예약 완료',
            message: '이미 예약된 시간이에요',
            backgroundColor: AppTheme.successColor.withValues(alpha: 0.1),
            foregroundColor: AppTheme.successColor,
          ),
      };
    }

    if (!slot.available) {
      return _MemberSlotUiState(
        label: '정원 마감',
        message: '다른 시간대를 선택해보세요',
        backgroundColor: Colors.grey.shade100,
        foregroundColor: Colors.grey.shade600,
      );
    }

    return _MemberSlotUiState(
      label: '예약',
      message: '지금 예약 가능한 시간이에요',
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
      foregroundColor: AppTheme.primaryColor,
      isAction: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Gradient header
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 20,
                left: 20,
                right: 20,
              ),
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      widget.organizationName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '수업 예약',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Date selector
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 14,
                  itemBuilder: (context, index) {
                    final date = DateTime.now().add(Duration(days: index));
                    final isSelected = _selectedDate.year == date.year &&
                        _selectedDate.month == date.month &&
                        _selectedDate.day == date.day;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedDate = date);
                          _loadSlots();
                        },
                        child: Container(
                          width: 56,
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryColor : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppTheme.softShadow,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('E', 'ko').format(date),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected ? Colors.white70 : Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('M월').format(date),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected ? Colors.white70 : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Slots section title
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                '${DateFormat('M월 d일 (E)', 'ko').format(_selectedDate)} 수업',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          // Slots list
          if (_isLoadingSlots)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_slots.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _MemberEmptyStateCard(
                  icon: Icons.event_busy_rounded,
                  title: '이 날에는 열린 수업이 없어요',
                  message: '다른 날짜를 선택하면 예약 가능한 시간을 더 쉽게 찾을 수 있어요.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final slot = _slots[index];
                    final slotUiState = _buildSlotUiState(slot);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: AppTheme.softShadow,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 44,
                              decoration: BoxDecoration(
                                color: slotUiState.foregroundColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${slot.startTime} - ${slot.endTime}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${slot.coachName} 코치',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    slotUiState.message,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: slotUiState.foregroundColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (slotUiState.isAction)
                              FilledButton(
                                onPressed: () => _reserve(slot),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                ),
                                child: Text(slotUiState.label),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: slotUiState.backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  slotUiState.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: slotUiState.foregroundColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _slots.length,
                ),
              ),
            ),

          // My reservations section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                '내 예약 현황',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          if (_isLoadingReservations)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_myReservations.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _MemberEmptyStateCard(
                  icon: Icons.receipt_long_rounded,
                  title: '아직 예약한 수업이 없어요',
                  message: '원하는 시간대를 선택해서 첫 예약을 만들어보세요.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final r = _myReservations[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.15),
                          ),
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
                                Icons.event_available,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat('M월 d일 (E)', 'ko').format(r.date),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${r.startTime} - ${r.endTime}  |  ${r.coachName} 코치',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (r.status == 'CONFIRMED'
                                            ? AppTheme.successColor
                                            : r.status == 'COMPLETED'
                                                ? Colors.grey
                                                : Colors.orange)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    switch (r.status) {
                                      'CONFIRMED' => '확정',
                                      'COMPLETED' => '완료',
                                      _ => '대기',
                                    },
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: switch (r.status) {
                                        'CONFIRMED' => AppTheme.successColor,
                                        'COMPLETED' => Colors.grey.shade700,
                                        _ => Colors.orange,
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap: () => _cancelReservation(r),
                                  child: Text(
                                    '취소',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red.shade400,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Colors.red.shade400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _myReservations.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberSlotUiState {
  final String label;
  final String message;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isAction;

  const _MemberSlotUiState({
    required this.label,
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
    this.isAction = false,
  });
}

class _MemberEmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MemberEmptyStateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          Icon(icon, size: 44, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
