import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/fcm_service.dart';
import '../../core/theme.dart';
import '../../models/member_booking.dart';
import '../../providers/member_auth_provider.dart';

String _buildReservationPolicySummary(MemberReservationNotice notice) {
  final openParts = <String>[];
  if (notice.reservationOpenDaysBefore > 0) {
    openParts.add('${notice.reservationOpenDaysBefore}일');
  }
  if (notice.reservationOpenHoursBefore > 0) {
    openParts.add('${notice.reservationOpenHoursBefore}시간');
  }

  final openText = openParts.isEmpty
      ? '수업 시작 직전부터'
      : '수업 ${openParts.join(' ')} 전부터';
  return '$openText 예약 가능 · 수업 ${notice.reservationCancelDeadlineMinutes}분 전까지 취소 가능';
}

class MemberClassDetailScreen extends ConsumerStatefulWidget {
  final String orgId;
  final String organizationName;

  const MemberClassDetailScreen({
    super.key,
    required this.orgId,
    required this.organizationName,
  });

  @override
  ConsumerState<MemberClassDetailScreen> createState() =>
      _MemberClassDetailScreenState();
}

class _MemberClassDetailScreenState
    extends ConsumerState<MemberClassDetailScreen> {
  late DateTime _selectedDate;
  List<MemberSlot> _slots = [];
  List<MemberReservationSummary> _myReservations = [];
  MemberReservationNotice? _reservationNotice;
  bool _isLoadingSlots = false;
  bool _isLoadingReservations = false;
  bool _isLoadingNotice = false;
  AppLifecycleListener? _lifecycleListener;
  String? _selectedCoachId;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _lifecycleListener = AppLifecycleListener(onResume: _handleResume);
    FcmService.addReservationSyncListener(_handleReservationSync);
    _loadData();
  }

  @override
  void dispose() {
    FcmService.removeReservationSyncListener(_handleReservationSync);
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _handleResume() {
    if (!mounted) return;
    _loadData();
  }

  void _handleReservationSync() {
    if (!mounted) return;
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadSlots(),
      _loadReservations(),
      _loadReservationNotice(coachId: _selectedCoachId),
    ]);
  }

  Future<void> _loadReservationNotice({String? coachId}) async {
    final classData = _getClassData();
    if (coachId == null && classData != null && classData.coaches.length > 1) {
      setState(() {
        _reservationNotice = null;
        _isLoadingNotice = false;
      });
      return;
    }

    setState(() => _isLoadingNotice = true);
    final notice = await ref
        .read(memberAuthProvider.notifier)
        .fetchReservationNotice(widget.orgId, coachId: coachId);
    if (mounted) {
      setState(() {
        _reservationNotice = notice;
        _isLoadingNotice = false;
      });
    }
  }

  Future<void> _loadSlots() async {
    setState(() => _isLoadingSlots = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final slots = await ref
        .read(memberAuthProvider.notifier)
        .fetchSlots(widget.orgId, dateStr, coachId: _selectedCoachId);
    if (mounted) {
      setState(() {
        _slots = slots;
        _isLoadingSlots = false;
      });
    }
  }

  Widget _buildCoachFilter() {
    final classData = _getClassData();
    if (classData == null || classData.coaches.length <= 1) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: const Text('전체'),
              selected: _selectedCoachId == null,
              onSelected: (_) {
                setState(() => _selectedCoachId = null);
                _loadSlots();
                _loadReservationNotice();
              },
            ),
            const SizedBox(width: 8),
            ...classData.coaches.map(
              (coach) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(coach.name),
                  selected: _selectedCoachId == coach.id,
                  onSelected: (_) {
                    setState(
                      () => _selectedCoachId = _selectedCoachId == coach.id
                          ? null
                          : coach.id,
                    );
                    _loadSlots();
                    _loadReservationNotice(coachId: _selectedCoachId);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  MemberClass? _getClassData() {
    final memberState = ref.read(memberAuthProvider);
    return memberState.classes
        .where((c) => c.organizationId == widget.orgId)
        .firstOrNull;
  }

  Future<void> _loadReservations() async {
    setState(() => _isLoadingReservations = true);
    final reservations = await ref
        .read(memberAuthProvider.notifier)
        .fetchMyReservations();
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
    final noticeConfirmed = await _confirmReservationNoticeIfNeeded(
      slot.coachId,
    );
    if (!noticeConfirmed) return;
    if (!mounted) return;

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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('예약'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final status = await ref
        .read(memberAuthProvider.notifier)
        .reserve(
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

  Future<bool> _confirmReservationNoticeIfNeeded(String coachId) async {
    final notice = await ref
        .read(memberAuthProvider.notifier)
        .fetchReservationNotice(widget.orgId, coachId: coachId);

    if (notice == null || !notice.hasContent) {
      return true;
    }

    if (mounted) {
      setState(() => _reservationNotice = notice);
    }
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ReservationNoticeDialog(notice: notice),
    );
    return confirmed == true;
  }

  Future<void> _cancelReservation(MemberReservationSummary reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('예약 취소'),
        content: const Text('이 예약을 취소하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니오'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('취소하기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final errorMessage = await ref
        .read(memberAuthProvider.notifier)
        .cancelReservation(reservation.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? '예약이 취소되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (errorMessage == null) _loadData();
    }
  }

  MemberReservationSummary? _findExistingReservationForSlot(MemberSlot slot) {
    for (final reservation in _myReservations) {
      final status = reservation.status;
      if (reservation.organizationId != widget.orgId) continue;
      if (!_isSameDate(reservation.date, _selectedDate)) continue;
      if (reservation.coachId != slot.coachId) continue;
      if (reservation.startTime != slot.startTime) continue;
      if (status != 'PENDING' &&
          status != 'CONFIRMED' &&
          status != 'COMPLETED') {
        continue;
      }
      return reservation;
    }
    return null;
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
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
                    final isSelected =
                        _selectedDate.year == date.year &&
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
                            color: isSelected
                                ? AppTheme.primaryColor
                                : Colors.white,
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
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('M월').format(date),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.grey.shade400,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat('M월 d일 (E)', 'ko').format(_selectedDate)} 수업',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_isLoadingNotice)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '예약 주의사항을 확인하는 중입니다.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    )
                  else if (_reservationNotice?.hasContent == true)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _reservationNotice?.coachName != null
                                  ? '${_reservationNotice!.coachName} 코치 예약 전에 주의사항 확인이 필요합니다.'
                                  : '예약 전에 주의사항 확인이 필요합니다.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_reservationNotice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _buildReservationPolicySummary(_reservationNotice!),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Coach filter
          SliverToBoxAdapter(child: _buildCoachFilter()),

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
                delegate: SliverChildBuilderDelegate((context, index) {
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                              ),
                              child: Text(slotUiState.label),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
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
                }, childCount: _slots.length),
              ),
            ),

          // My reservations section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                '내 예약 현황',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
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
                delegate: SliverChildBuilderDelegate((context, index) {
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
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.1,
                              ),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (r.status == 'CONFIRMED'
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
                }, childCount: _myReservations.length),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReservationNoticeDialog extends StatefulWidget {
  final MemberReservationNotice notice;

  const _ReservationNoticeDialog({required this.notice});

  @override
  State<_ReservationNoticeDialog> createState() =>
      _ReservationNoticeDialogState();
}

class _ReservationNoticeDialogState extends State<_ReservationNoticeDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final hasImage =
        notice.imageUrl != null && notice.imageUrl!.trim().isNotEmpty;
    final hasText = notice.text != null && notice.text!.trim().isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('예약 전 확인사항'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${notice.coachName ?? notice.organizationName} 예약 주의사항을 확인한 뒤 신청할 수 있어요.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _buildReservationPolicySummary(notice),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hasImage) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    notice.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 160,
                      color: Colors.grey.shade100,
                      alignment: Alignment.center,
                      child: Text(
                        '이미지를 불러오지 못했습니다',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                ),
              ],
              if (hasText) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    notice.text!.trim(),
                    style: const TextStyle(fontSize: 13, height: 1.55),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              CheckboxListTile(
                value: _agreed,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  '주의사항을 확인했고 안내 내용에 동의합니다',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onChanged: (value) => setState(() => _agreed = value ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: _agreed ? () => Navigator.pop(context, true) : null,
          child: const Text('확인 후 계속'),
        ),
      ],
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
