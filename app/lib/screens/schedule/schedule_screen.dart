import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/socket_service.dart';
import '../../core/theme.dart';
import '../../models/reservation.dart';
import '../../models/schedule_override.dart';
import '../../providers/reservation_provider.dart';
import '../../providers/schedule_action_provider.dart';
import '../../providers/schedule_slot_provider.dart';
import '../../providers/schedule_override_provider.dart';
import '../../widgets/common.dart';
import 'schedule_helpers.dart';
import 'widgets/schedule_dialogs.dart';
import 'widgets/schedule_timeline_widgets.dart';

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  TimelineFilter _filter = TimelineFilter.all;

  @override
  void initState() {
    super.initState();
    _registerSocketListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshAll();
    });
  }

  @override
  void dispose() {
    _unregisterSocketListeners();
    super.dispose();
  }

  void _onSocketReservationEvent(dynamic _) {
    if (!mounted) return;
    _refreshScheduleArtifacts();
  }

  void _registerSocketListeners() {
    final socket = SocketService.instance;
    socket.on('reservation:created', _onSocketReservationEvent);
    socket.on('reservation:updated', _onSocketReservationEvent);
    socket.on('reservation:cancelled', _onSocketReservationEvent);
  }

  void _unregisterSocketListeners() {
    final socket = SocketService.instance;
    socket.off('reservation:created', _onSocketReservationEvent);
    socket.off('reservation:updated', _onSocketReservationEvent);
    socket.off('reservation:cancelled', _onSocketReservationEvent);
  }

  Future<void> _refreshScheduleArtifacts() async {
    _loadOverrides();
    await _loadSlots();
  }

  Future<void> _refreshAll() async {
    _loadReservations();
    await _refreshScheduleArtifacts();
  }

  void _loadReservations() {
    final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    ref
        .read(reservationProvider.notifier)
        .fetchReservations(
          startDate: DateFormat('yyyy-MM-dd').format(start),
          endDate: DateFormat('yyyy-MM-dd').format(end),
        );
  }

  Future<void> _changeReservationStatus(
    Reservation reservation,
    String status,
  ) async {
    final success = await ref
        .read(reservationProvider.notifier)
        .updateStatus(reservation.id, status);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? status == 'CONFIRMED'
                    ? '예약이 승인되었습니다'
                    : status == 'CANCELLED'
                    ? '예약이 취소되었습니다'
                    : '예약 상태가 변경되었습니다'
              : '예약 상태 변경에 실패했습니다',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (success) {
      await _loadSlots();
    }
  }

  Future<bool> _confirmAdminCancellation(Reservation reservation) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('예약 취소'),
        content: Text(
          '${reservation.memberName ?? '회원'}님의 ${reservation.startTime} 예약을 취소할까요?\n회원에게 취소 알림이 전송됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('예약 취소'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _adjustReservationTime(Reservation reservation) async {
    final selection = await _showTimeAdjustDialog(
      startTime: reservation.startTime,
      endTime: reservation.endTime,
      followingLabel: _buildFollowingScheduleLabel(reservation.coachName),
    );
    if (selection == null || !mounted) return;
    final deltaMinutes = selection.deltaMinutes;

    if (selection.scope == TimeAdjustmentScope.following) {
      final result = await ref
          .read(scheduleActionProvider.notifier)
          .shiftDaySchedule(
            coachId: reservation.coachId,
            date: _selectedDay,
            fromStartTime: reservation.startTime,
            deltaMinutes: deltaMinutes,
          );
      if (result.success) {
        await _refreshAll();
        if (!mounted) return;
        final absMinutes = deltaMinutes.abs();
        final direction = deltaMinutes > 0 ? '미뤘습니다' : '앞당겼습니다';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이후 일정을 $absMinutes분 $direction')),
        );
        return;
      }
      if (!mounted) return;
      final message = result.error ?? '이후 일정 전체 조정에 실패했습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final warnings = buildTimeRangeAdjustmentWarnings(
      reservations: ref.read(reservationProvider).reservations,
      slots: ref.read(scheduleSlotProvider).slots,
      selectedDay: _selectedDay,
      coachId: reservation.coachId,
      startTime: reservation.startTime,
      endTime: reservation.endTime,
      deltaMinutes: deltaMinutes,
      excludeReservationId: reservation.id,
    );
    var force = false;
    if (warnings.isNotEmpty) {
      final confirmed = await _confirmTimeAdjustmentWarnings(warnings);
      if (confirmed != true || !mounted) return;
      force = true;
    }

    final result = await ref
        .read(reservationProvider.notifier)
        .adjustTime(reservation.id, delayMinutes: deltaMinutes, force: force);
    if (result.success) {
      await _refreshScheduleArtifacts();
      if (!mounted) return;
      final absMinutes = deltaMinutes.abs();
      final direction = deltaMinutes > 0 ? '미뤘습니다' : '앞당겼습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('예약을 $absMinutes분 $direction')));
      return;
    }
    if (!mounted) return;
    final message = result.error ?? '예약 시간 조정에 실패했습니다';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _adjustEmptySlotTime(Map<String, dynamic> slot) async {
    final selection = await _showTimeAdjustDialog(
      startTime: slot['startTime'] as String,
      endTime: slot['endTime'] as String,
      followingLabel: _buildFollowingScheduleLabel(
        slot['coachName'] as String?,
      ),
    );
    if (selection == null || !mounted) return;
    final deltaMinutes = selection.deltaMinutes;

    if (selection.scope == TimeAdjustmentScope.following) {
      final result = await ref
          .read(scheduleActionProvider.notifier)
          .shiftDaySchedule(
            coachId: slot['coachId'] as String,
            date: _selectedDay,
            fromStartTime: slot['startTime'] as String,
            deltaMinutes: deltaMinutes,
          );
      if (result.success) {
        await _refreshAll();
        if (!mounted) return;
        final absMinutes = deltaMinutes.abs();
        final direction = deltaMinutes > 0 ? '미뤘습니다' : '앞당겼습니다';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이후 일정을 $absMinutes분 $direction')),
        );
        return;
      }
      if (!mounted) return;
      final message = result.error ?? '이후 일정 전체 조정에 실패했습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final warnings = buildTimeRangeAdjustmentWarnings(
      reservations: ref.read(reservationProvider).reservations,
      slots: ref.read(scheduleSlotProvider).slots,
      selectedDay: _selectedDay,
      coachId: slot['coachId'] as String,
      startTime: slot['startTime'] as String,
      endTime: slot['endTime'] as String,
      deltaMinutes: deltaMinutes,
    );

    if (warnings.isNotEmpty) {
      final confirmed = await _confirmTimeAdjustmentWarnings(warnings);
      if (confirmed != true || !mounted) return;
    }

    final newStart = shiftTime(slot['startTime'] as String, deltaMinutes);
    final newEnd = shiftTime(slot['endTime'] as String, deltaMinutes);
    if (newStart == null || newEnd == null) return;

    final originalDuration = calculateMinutes(
      slot['startTime'] as String,
      slot['endTime'] as String,
    );

    final result = await ref
        .read(scheduleActionProvider.notifier)
        .moveSlot(
          coachId: slot['coachId'] as String,
          date: _selectedDay,
          currentStartTime: slot['startTime'] as String,
          currentEndTime: slot['endTime'] as String,
          newStartTime: newStart,
          newEndTime: newEnd,
          slotDuration: originalDuration,
          maxCapacity: slot['maxCapacity'] as int? ?? 1,
          isPublic: slot['isPublic'] == true,
        );
    if (result.success) {
      await _refreshScheduleArtifacts();
      if (!mounted) return;
      final absMinutes = deltaMinutes.abs();
      final direction = deltaMinutes > 0 ? '미뤘습니다' : '앞당겼습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('빈 타임을 $absMinutes분 $direction')));
      return;
    }
    if (!mounted) return;
    final message = result.error ?? '빈 타임 이동에 실패했습니다';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleSlotVisibility(Map<String, dynamic> slot) async {
    final visibilityOverrideId = slot['visibilityOverrideId'] as String?;
    final baseIsPublic = slot['baseIsPublic'] == true;

    final result = await ref
        .read(scheduleActionProvider.notifier)
        .setSlotVisibility(
          coachId: slot['coachId'] as String,
          date: _selectedDay,
          startTime: slot['startTime'] as String,
          endTime: slot['endTime'] as String,
          baseIsPublic: baseIsPublic,
          visibilityOverrideId: visibilityOverrideId,
        );
    if (result.success) {
      await _refreshScheduleArtifacts();
      if (!mounted) return;
      final changedToPublic =
          visibilityOverrideId != null && visibilityOverrideId.isNotEmpty
          ? baseIsPublic
          : !baseIsPublic;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changedToPublic ? '이 시간대를 회원에게 공개했습니다' : '이 시간대를 회원에게 비공개했습니다',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final message = result.error ?? '공개 상태 변경에 실패했습니다';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _confirmTimeAdjustmentWarnings(List<String> warnings) {
    return showTimeAdjustmentWarningsDialog(context, warnings);
  }

  String _buildFollowingScheduleLabel(String? coachName) {
    final resolvedCoachName = coachName?.trim();
    if (resolvedCoachName == null || resolvedCoachName.isEmpty) {
      return '내 이후 일정 전체 조정';
    }
    return '$resolvedCoachName 코치의 이후 일정 전체 조정';
  }

  Future<TimeAdjustmentSelection?> _showTimeAdjustDialog({
    required String startTime,
    required String endTime,
    required String followingLabel,
  }) {
    return showTimeAdjustDialog(
      context,
      startTime: startTime,
      endTime: endTime,
      followingLabel: followingLabel,
    );
  }

  Future<void> _openReservationFlow(Reservation reservation) async {
    final action = await showReservationActionSheet(context, reservation);

    if (action == 'approve') {
      await _changeReservationStatus(reservation, 'CONFIRMED');
    } else if (action == 'reject') {
      await _changeReservationStatus(reservation, 'CANCELLED');
    } else if (action == 'cancel') {
      if (!mounted) return;
      final confirmed = await _confirmAdminCancellation(reservation);
      if (!confirmed) return;
      await _changeReservationStatus(reservation, 'CANCELLED');
    } else if (action == 'member') {
      if (!mounted) return;
      await context.push('/members/${reservation.memberId}');
    } else if (action == 'adjust') {
      if (!mounted) return;
      await _adjustReservationTime(reservation);
    } else if (action == 'edit_memo') {
      if (!mounted) return;
      await _editReservationMemo(reservation);
    } else if (action == 'complete') {
      if (!mounted) return;
      final result = await context.push(
        '/reservations/complete',
        extra: reservation,
      );
      if (!mounted) return;
      if (result == true) {
        _loadReservations();
        _loadSlots();
      }
    }
  }

  Future<void> _showReservationListSheet(List<Reservation> reservations) async {
    final selectedReservation = await showReservationListSheet(
      context,
      reservations,
    );
    if (!mounted || selectedReservation == null) return;
    await _openReservationFlow(selectedReservation);
  }

  Future<void> _loadSlots() {
    return ref
        .read(scheduleSlotProvider.notifier)
        .fetchSlots(date: _selectedDay);
  }

  Future<void> _editReservationMemo(Reservation reservation) async {
    final quickMemoController = TextEditingController(
      text: reservation.quickMemo ?? '',
    );
    final detailMemoController = TextEditingController(
      text: reservation.memo ?? '',
    );

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('예약 메모 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reservation.memberQuickMemo?.trim().isNotEmpty == true) ...[
                Text(
                  '회원 메모: ${reservation.memberQuickMemo!.trim()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.teal.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: quickMemoController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '짧은 메모',
                  hintText: '스케줄 탭에 바로 보일 메모',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: detailMemoController,
                minLines: 3,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: '상세 메모',
                  hintText: '눌러서 볼 상세 메모',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (shouldSave != true || !mounted) return;

    final result = await ref
        .read(reservationProvider.notifier)
        .updateMemo(
          reservation.id,
          quickMemo: quickMemoController.text.trim(),
          memo: detailMemoController.text.trim(),
        );

    if (!mounted) return;

    if (result.success) {
      _loadReservations();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예약 메모를 저장했습니다')));
    } else {
      final message = result.error ?? '예약 메모 저장에 실패했습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _showEmptySlotActions(Map<String, dynamic> slot) async {
    final isPublic = slot['isPublic'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DateFormat('M월 d일 (E)', 'ko').format(_selectedDay)} ${slot['startTime']} - ${slot['endTime']}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${slot['coachName'] ?? ''} 코치',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.schedule_rounded,
                  color: AppTheme.primaryColor,
                ),
                title: const Text('빈 타임 이동'),
                subtitle: const Text('이 날짜의 타임으로 따로 관리합니다'),
                onTap: () => Navigator.pop(context, 'adjust'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isPublic
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.blue,
                ),
                title: Text(isPublic ? '회원에게 비공개' : '회원에게 공개'),
                subtitle: Text(
                  isPublic ? '이 시간만 회원 앱에서 숨깁니다' : '이 시간만 회원 앱에서 보이게 합니다',
                ),
                onTap: () => Navigator.pop(context, 'toggle_visibility'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.person_add_alt_rounded,
                  color: AppTheme.primaryColor,
                ),
                title: const Text('회원으로 예약 채워넣기'),
                subtitle: const Text('등록된 회원을 선택해 바로 예약을 만들어요'),
                onTap: () => Navigator.pop(context, 'reserve'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.errorColor,
                ),
                title: const Text('타임 삭제'),
                subtitle: const Text('이 날짜에서만 해당 빈 타임을 없앱니다'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'adjust') {
      await _adjustEmptySlotTime(slot);
      return;
    }

    if (action == 'reserve') {
      final result = await context.push(
        '/reservations/new',
        extra: {
          'date': DateFormat('yyyy-MM-dd').format(_selectedDay),
          'startTime': slot['startTime'],
          'endTime': slot['endTime'],
          'coachId': slot['coachId'],
        },
      );
      if (result == true) {
        _loadReservations();
        _loadSlots();
      }
      return;
    }

    if (action == 'toggle_visibility') {
      await _toggleSlotVisibility(slot);
      return;
    }

    if (action == 'delete') {
      await _deleteSlot(slot);
      return;
    }
  }

  Future<void> _deleteSlot(Map<String, dynamic> slot) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '타임 삭제',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${DateFormat('M월 d일 (E)', 'ko').format(_selectedDay)} ${slot['startTime']} - ${slot['endTime']}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Text(
                '${slot['coachName'] ?? ''} 코치의 이 날짜 타임을 삭제합니다.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                      ),
                      child: const Text('삭제'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    final result = await ref
        .read(scheduleActionProvider.notifier)
        .closeSlot(
          coachId: slot['coachId'] as String,
          date: _selectedDay,
          startTime: slot['startTime'] as String,
          endTime: slot['endTime'] as String,
        );
    if (result.success) {
      await _refreshScheduleArtifacts();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이 날짜에서 해당 타임을 삭제했습니다')));
      return;
    }
    if (!mounted) return;
    final message = result.error ?? '타임 삭제에 실패했습니다';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _loadOverrides() {
    final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    ref
        .read(scheduleOverrideProvider.notifier)
        .fetchOverrides(
          startDate: DateFormat('yyyy-MM-dd').format(start),
          endDate: DateFormat('yyyy-MM-dd').format(end),
        );
  }

  void _showOverrideSheet({bool startAddingOpen = false}) {
    if (startAddingOpen) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => _EmptySlotCreateSheet(
          selectedDay: _selectedDay,
          onCreated: () {
            _loadOverrides();
            _loadSlots();
            Navigator.pop(context);
          },
        ),
      );
      return;
    }

    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDay);
    final overrideState = ref.read(scheduleOverrideProvider);
    final dayOverrides = overrideState.overrides.where((o) {
      return DateFormat('yyyy-MM-dd').format(o.date) == selectedDateStr;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _OverrideBottomSheet(
        selectedDay: _selectedDay,
        overrides: dayOverrides,
        onChanged: () {
          _loadOverrides();
          _loadSlots();
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _showAddScheduleActionSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '스케줄 추가',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppTheme.successColor,
                ),
                title: const Text('빈 타임 생성'),
                subtitle: const Text('예약자 없이 이 날짜에 수업 가능한 타임만 만듭니다'),
                onTap: () => Navigator.pop(context, 'empty_slot'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.person_add_alt_rounded,
                  color: AppTheme.primaryColor,
                ),
                title: const Text('회원 예약 등록'),
                subtitle: const Text('회원을 선택해서 바로 예약을 만듭니다'),
                onTap: () => Navigator.pop(context, 'reservation'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'empty_slot') {
      _showOverrideSheet(startAddingOpen: true);
      return;
    }

    if (action == 'reservation') {
      final result = await context.push(
        '/reservations/new',
        extra: {'date': DateFormat('yyyy-MM-dd').format(_selectedDay)},
      );
      if (result == true) {
        _loadReservations();
        _loadSlots();
      }
    }
  }

  List<Reservation> _getEventsForDay(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    return ref.read(reservationProvider).reservations.where((r) {
      return DateFormat('yyyy-MM-dd').format(r.date) == dateStr;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final reservationState = ref.watch(reservationProvider);
    final slotState = ref.watch(scheduleSlotProvider);
    final slots = slotState.slots;
    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDay);
    final dayReservations = reservationState.reservations.where((r) {
      return DateFormat('yyyy-MM-dd').format(r.date) == selectedDateStr;
    }).toList();
    final pendingCount = dayReservations
        .where((r) => r.status == 'PENDING')
        .length;
    final confirmedCount = dayReservations
        .where((r) => r.status == 'CONFIRMED')
        .length;
    final completedCount = dayReservations
        .where((r) => r.status == 'COMPLETED')
        .length;
    final availableSlotCount = slots
        .where((slot) => slot['available'] == true)
        .length;
    final pastSlotCount = slots
        .where(
          (slot) => isPastTimeForDay(
            selectedDay: _selectedDay,
            startTime: slot['startTime'] as String,
          ),
        )
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('스케줄'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: Icon(
                _calendarFormat == CalendarFormat.week
                    ? Icons.calendar_month_rounded
                    : Icons.view_week_rounded,
                color: AppTheme.primaryColor,
                size: 22,
              ),
              onPressed: () {
                setState(() {
                  _calendarFormat = _calendarFormat == CalendarFormat.week
                      ? CalendarFormat.month
                      : CalendarFormat.week;
                });
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Calendar with improved styling
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppTheme.softShadow,
            ),
            child: TableCalendar<Reservation>(
              firstDay: DateTime(2020),
              lastDay: DateTime(2030),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              locale: 'ko_KR',
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              eventLoader: _getEventsForDay,
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _loadSlots();
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
                _loadReservations();
                _loadOverrides();
                _loadSlots();
              },
              calendarStyle: CalendarStyle(
                markerDecoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                markerSize: 6,
                markersMaxCount: 3,
                todayDecoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
                selectedDecoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: TextStyle(color: Colors.red.shade300),
                outsideDaysVisible: false,
                cellMargin: const EdgeInsets.all(4),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                leftChevronIcon: Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.grey.shade600,
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade600,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
                weekendStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade300,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Day header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('M월 d일 (E)', 'ko').format(_selectedDay),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        HeaderChip(
                          label: '전체 예약 ${dayReservations.length}건',
                          backgroundColor: AppTheme.primaryColor.withValues(
                            alpha: 0.08,
                          ),
                          foregroundColor: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 8),
                        HeaderChip(
                          label: '승인 대기 $pendingCount건',
                          backgroundColor: Colors.orange.withValues(alpha: 0.1),
                          foregroundColor: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        HeaderChip(
                          label: '확정 $confirmedCount건',
                          backgroundColor: Colors.blue.withValues(alpha: 0.08),
                          foregroundColor: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        HeaderChip(
                          label: '남은 슬롯 $availableSlotCount개',
                          backgroundColor: AppTheme.successColor.withValues(
                            alpha: 0.08,
                          ),
                          foregroundColor: AppTheme.successColor,
                        ),
                        const SizedBox(width: 8),
                        if (completedCount > 0) ...[
                          HeaderChip(
                            label: '완료 $completedCount건',
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.grey.shade700,
                          ),
                          const SizedBox(width: 8),
                        ],
                        HeaderChip(
                          label: '지난 타임 $pastSlotCount개',
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.grey.shade700,
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _showOverrideSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.warningColor.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.edit_calendar_rounded,
                                  size: 14,
                                  color: AppTheme.warningColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '스케줄 관리',
                                  style: TextStyle(
                                    color: AppTheme.warningColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: TimelineFilter.values.map((filter) {
                  final selected = _filter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(filter.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Integrated timeline: slots + reservations
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAll,
              child: (reservationState.isLoading || slotState.isLoading)
                  ? const ShimmerLoading(style: ShimmerStyle.card, itemCount: 3)
                  : Builder(
                      builder: (context) {
                        // Build merged timeline items
                        final timelineItems = <TimelineItem>[];
                        // Separate active vs inactive reservations per key
                        final activeReservationMap =
                            <String, List<Reservation>>{};
                        final cancelledCountMap = <String, int>{};
                        const inactiveStatuses = {'CANCELLED', 'NO_SHOW'};
                        for (final r in dayReservations) {
                          // 지연된 예약은 원래 슬롯(originalStartTime)에 맞춰 그룹핑해
                          // 8시 예약을 10분 미뤄도 "8시 타임" 카드로 표시되게 한다.
                          final groupStartTime =
                              r.originalStartTime ?? r.startTime;
                          final key = '${r.coachId}|$groupStartTime';
                          if (inactiveStatuses.contains(r.status)) {
                            cancelledCountMap[key] =
                                (cancelledCountMap[key] ?? 0) + 1;
                          } else {
                            activeReservationMap
                                .putIfAbsent(key, () => [])
                                .add(r);
                          }
                        }

                        final matchedKeys = <String>{};

                        // Add slots (with or without reservation)
                        for (final slot in slots) {
                          final key = '${slot['coachId']}|${slot['startTime']}';
                          final reservations = activeReservationMap[key];
                          final cancelled = cancelledCountMap[key] ?? 0;
                          if (reservations != null && reservations.isNotEmpty) {
                            matchedKeys.add(key);
                            timelineItems.add(
                              TimelineItem(
                                startTime: slot['startTime'] as String,
                                reservations: reservations,
                                slot: slot,
                                cancelledCount: cancelled,
                              ),
                            );
                          } else {
                            matchedKeys.add(key);
                            timelineItems.add(
                              TimelineItem(
                                startTime: slot['startTime'] as String,
                                slot: slot,
                                cancelledCount: cancelled,
                              ),
                            );
                          }
                        }

                        // Add active reservations not matched to any slot
                        for (final entry in activeReservationMap.entries) {
                          final key = entry.key;
                          if (!matchedKeys.contains(key)) {
                            final reservations = entry.value;
                            timelineItems.add(
                              TimelineItem(
                                startTime: reservations.first.startTime,
                                reservations: reservations,
                              ),
                            );
                          }
                        }

                        // Sort by startTime
                        timelineItems.sort(
                          (a, b) => a.startTime.compareTo(b.startTime),
                        );

                        final filteredItems = timelineItems.where((item) {
                          final isPast = isPastTimeForDay(
                            selectedDay: _selectedDay,
                            startTime: item.startTime,
                          );
                          return switch (_filter) {
                            TimelineFilter.all => true,
                            TimelineFilter.reservations => item.hasReservations,
                            TimelineFilter.open =>
                              item.slot != null &&
                                  item.slot!['available'] == true,
                            TimelineFilter.past => isPast,
                          };
                        }).toList();
                        final emptyStateTitle = switch (_filter) {
                          TimelineFilter.all => '표시할 타임라인이 없습니다',
                          TimelineFilter.reservations => '예약된 타임이 없습니다',
                          TimelineFilter.open => '남아 있는 빈 타임이 없습니다',
                          TimelineFilter.past => '지난 타임이 없습니다',
                        };
                        final emptyStateMessage = switch (_filter) {
                          TimelineFilter.all =>
                            '선택한 날짜에 표시할 일정이 없습니다.\n스케줄 설정이나 예외 일정을 확인해보세요.',
                          TimelineFilter.reservations =>
                            '이 날짜에는 예약되거나 신청된 수업이 없습니다.',
                          TimelineFilter.open =>
                            '현재 남아 있는 예약 가능 타임이 없습니다.\n다른 날짜를 보거나 정원을 확인해보세요.',
                          TimelineFilter.past => '선택한 날짜에는 지난 시간대가 없습니다.',
                        };

                        if (slotState.error != null && filteredItems.isEmpty) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                            children: [
                              ScheduleStateCard(
                                icon: Icons.cloud_off_rounded,
                                iconColor: AppTheme.errorColor,
                                title: '스케줄을 불러오지 못했습니다',
                                message: slotState.error!,
                                actionLabel: '다시 시도',
                                onAction: _refreshAll,
                              ),
                            ],
                          );
                        }

                        if (filteredItems.isEmpty) {
                          final showScheduleSettingAction =
                              _filter == TimelineFilter.all;
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                            children: [
                              ScheduleStateCard(
                                icon: Icons.event_busy_rounded,
                                title: emptyStateTitle,
                                message: emptyStateMessage,
                                actionLabel: '스케줄 관리',
                                onAction: _showOverrideSheet,
                                secondaryActionLabel: showScheduleSettingAction
                                    ? '수업시간 설정'
                                    : null,
                                secondaryActionIcon: showScheduleSettingAction
                                    ? Icons.schedule_rounded
                                    : null,
                                onSecondaryAction: showScheduleSettingAction
                                    ? () => context.push('/settings/schedules')
                                    : null,
                              ),
                            ],
                          );
                        }

                        return ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final isPast = isPastTimeForDay(
                              selectedDay: _selectedDay,
                              startTime: item.startTime,
                            );
                            if (item.hasReservations) {
                              final reservations = item.reservations!;
                              return TimelineScheduleCard(
                                reservations: reservations,
                                slot: item.slot,
                                isPast: isPast,
                                onTap: reservations.length > 1
                                    ? () => _showReservationListSheet(
                                        reservations,
                                      )
                                    : () => _openReservationFlow(
                                        reservations.first,
                                      ),
                              );
                            } else {
                              final hasCancelled = item.cancelledCount > 0;
                              String slotTitle;
                              String slotSubtitle;
                              if (hasCancelled) {
                                slotTitle = '빈 타임 · 취소 ${item.cancelledCount}건';
                                slotSubtitle = '눌러서 예약 채우기 / 이동 / 삭제';
                              } else if (item.slot!['isPublic'] == true) {
                                slotTitle = '빈 타임 · 공개';
                                slotSubtitle = '회원이 예약 가능한 시간';
                              } else {
                                slotTitle = '빈 타임 · 비공개';
                                slotSubtitle = '회원 앱에는 보이지 않는 시간';
                              }
                              return EmptySlotCard(
                                slot: item.slot!,
                                isPast: isPast,
                                title: slotTitle,
                                subtitle: slotSubtitle,
                                hasCancelled: hasCancelled,
                                onTap: isPast
                                    ? null
                                    : () => _showEmptySlotActions(item.slot!),
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'schedule_add_action_fab',
        onPressed: _showAddScheduleActionSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── Empty Slot Create Sheet ───────────────────────────────
class _EmptySlotCreateSheet extends ConsumerStatefulWidget {
  final DateTime selectedDay;
  final VoidCallback onCreated;

  const _EmptySlotCreateSheet({
    required this.selectedDay,
    required this.onCreated,
  });

  @override
  ConsumerState<_EmptySlotCreateSheet> createState() =>
      _EmptySlotCreateSheetState();
}

class _EmptySlotCreateSheetState extends ConsumerState<_EmptySlotCreateSheet> {
  final _slotDurationController = TextEditingController(text: '60');
  final _breakMinutesController = TextEditingController(text: '0');
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);
  int _slotDuration = 60;
  int _breakMinutes = 0;
  int _maxCapacity = 1;
  bool _isPublic = false;
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _slotDurationController.dispose();
    _breakMinutesController.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  TimeOfDay _timeFromMinutes(int value) {
    final clamped = value.clamp(0, 23 * 60 + 59);
    return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
  }

  void _syncEndTime() {
    final nextEnd = _minutes(_startTime) + _slotDuration;
    if (nextEnd < 24 * 60) {
      _endTime = _timeFromMinutes(nextEnd);
    }
  }

  Future<void> _pickStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (time == null) return;
    setState(() {
      _startTime = time;
      _syncEndTime();
      _errorText = null;
    });
  }

  Future<void> _pickEndTime() async {
    final time = await showTimePicker(context: context, initialTime: _endTime);
    if (time == null) return;
    setState(() {
      _endTime = time;
      _errorText = null;
    });
  }

  void _setDuration(int minutes) {
    _slotDurationController.text = minutes.toString();
    setState(() {
      _slotDuration = minutes;
      _syncEndTime();
      _errorText = null;
    });
  }

  Future<void> _createEmptySlot() async {
    final duration = int.tryParse(_slotDurationController.text.trim());
    final breakMinutes = int.tryParse(_breakMinutesController.text.trim());

    if (duration == null || duration < 15) {
      setState(() => _errorText = '수업 시간은 15분 이상으로 입력해주세요.');
      return;
    }
    if (breakMinutes == null || breakMinutes < 0) {
      setState(() => _errorText = '쉬는시간은 0분 이상으로 입력해주세요.');
      return;
    }
    if (_minutes(_startTime) >= _minutes(_endTime)) {
      setState(() => _errorText = '종료 시간이 시작 시간보다 늦어야 합니다.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
      _slotDuration = duration;
      _breakMinutes = breakMinutes;
    });

    try {
      final result = await ref
          .read(scheduleActionProvider.notifier)
          .createOpenSlot(
            date: widget.selectedDay,
            startTime: _fmt(_startTime),
            endTime: _fmt(_endTime),
            slotDuration: duration,
            breakMinutes: breakMinutes,
            maxCapacity: _maxCapacity,
            isPublic: _isPublic,
          );
      if (!result.success) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorText = result.error ?? '빈 타임 생성에 실패했습니다.';
        });
        return;
      }
      widget.onCreated();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorText = '빈 타임 생성에 실패했습니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final dateLabel = DateFormat('M월 d일 EEEE', 'ko').format(widget.selectedDay);
    final slotCount = _slotDuration <= 0
        ? 0
        : ((_minutes(_endTime) - _minutes(_startTime)) ~/
              (_slotDuration + _breakMinutes).clamp(1, 24 * 60));

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppTheme.successColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '빈 타임 생성',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateLabel,
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
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: Colors.green.shade800,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '예약자 없이 이 날짜에만 열리는 타임입니다. 기존 기본 수업시간과 별도로 관리돼요.',
                      style: TextStyle(
                        height: 1.35,
                        fontSize: 13,
                        color: Colors.green.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _TimePickCard(
                    label: '시작',
                    value: _fmt(_startTime),
                    icon: Icons.play_arrow_rounded,
                    onTap: _pickStartTime,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimePickCard(
                    label: '종료',
                    value: _fmt(_endTime),
                    icon: Icons.flag_rounded,
                    onTap: _pickEndTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in [30, 50, 60, 90])
                  ChoiceChip(
                    label: Text('$minutes분'),
                    selected: _slotDuration == minutes,
                    onSelected: (_) => _setDuration(minutes),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _slotDurationController,
                    decoration: const InputDecoration(
                      labelText: '한 타임 수업시간',
                      suffixText: '분',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed == null || parsed < 15) return;
                      setState(() {
                        _slotDuration = parsed;
                        _syncEndTime();
                        _errorText = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _breakMinutesController,
                    decoration: const InputDecoration(
                      labelText: '타임 사이 쉬는시간',
                      suffixText: '분',
                      prefixIcon: Icon(Icons.self_improvement_rounded),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed == null) return;
                      setState(() {
                        _breakMinutes = parsed;
                        _errorText = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _maxCapacity,
              decoration: const InputDecoration(
                labelText: '한 타임당 정원',
                prefixIcon: Icon(Icons.groups_2_outlined),
              ),
              items: List.generate(
                10,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('${index + 1}명'),
                ),
              ),
              onChanged: (value) => setState(() => _maxCapacity = value ?? 1),
            ),
            const SizedBox(height: 12),
            _PublicToggleCard(
              value: _isPublic,
              onChanged: (value) => setState(() => _isPublic = value),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                slotCount > 0
                    ? '예상 생성: $_slotDuration분 타임 약 $slotCount개'
                    : '선택한 시간 안에서 생성 가능한 타임이 없습니다.',
                style: TextStyle(
                  fontSize: 13,
                  color: slotCount > 0
                      ? Colors.grey.shade700
                      : AppTheme.errorColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: AppTheme.errorColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _createEmptySlot,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded),
                    label: Text(_isSaving ? '생성 중' : '빈 타임 생성'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _TimePickCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicToggleCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PublicToggleCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: value
            ? AppTheme.primaryColor.withValues(alpha: 0.08)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? AppTheme.primaryColor.withValues(alpha: 0.24)
              : Colors.grey.shade200,
        ),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          '회원 앱에 공개',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(value ? '회원이 직접 예약할 수 있게 보여줍니다' : '관리자 화면에서만 보입니다'),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

// ─── Override Bottom Sheet ─────────────────────────────────
class _OverrideBottomSheet extends ConsumerStatefulWidget {
  final DateTime selectedDay;
  final List<ScheduleOverride> overrides;
  final VoidCallback onChanged;

  const _OverrideBottomSheet({
    required this.selectedDay,
    required this.overrides,
    required this.onChanged,
  });

  @override
  ConsumerState<_OverrideBottomSheet> createState() =>
      _OverrideBottomSheetState();
}

class _OverrideBottomSheetState extends ConsumerState<_OverrideBottomSheet> {
  late bool _isAdding;
  late String _type;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  int _slotDuration = 60;
  int _breakMinutes = 0;
  int _maxCapacity = 1;
  bool _isPublic = false;
  final _slotDurationController = TextEditingController(text: '60');
  final _breakMinutesController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _isAdding = false;
    _type = 'CLOSED';
  }

  @override
  void dispose() {
    _slotDurationController.dispose();
    _breakMinutesController.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _deleteOverride(String id) async {
    final success = await ref
        .read(scheduleOverrideProvider.notifier)
        .deleteOverride(id);
    if (success) widget.onChanged();
  }

  Future<void> _createOverride() async {
    if (_type == 'OPEN') {
      final startMin = _startTime.hour * 60 + _startTime.minute;
      final endMin = _endTime.hour * 60 + _endTime.minute;
      if (startMin >= endMin) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('시작시간이 종료시간보다 빨라야 합니다')));
        return;
      }
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(widget.selectedDay);
    final data = <String, dynamic>{'date': dateStr, 'type': _type};

    if (_type == 'OPEN') {
      data['startTime'] = _fmt(_startTime);
      data['endTime'] = _fmt(_endTime);
      data['slotDuration'] = _slotDuration;
      data['breakMinutes'] = _breakMinutes;
      data['maxCapacity'] = _maxCapacity;
      data['isPublic'] = _isPublic;
    }

    final success = await ref
        .read(scheduleOverrideProvider.notifier)
        .createOverride(data);
    if (success) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${DateFormat('M월 d일 (E)', 'ko').format(widget.selectedDay)} 스케줄 관리',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Existing overrides list
          if (widget.overrides.isNotEmpty) ...[
            Text(
              '설정된 오버라이드',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.overrides.map((o) {
              final isPartialClosed =
                  o.type == 'CLOSED' &&
                  o.startTime != null &&
                  o.endTime != null;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: o.type == 'CLOSED'
                      ? AppTheme.errorColor.withValues(alpha: 0.06)
                      : AppTheme.successColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: o.type == 'CLOSED'
                        ? AppTheme.errorColor.withValues(alpha: 0.2)
                        : AppTheme.successColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      o.type == 'CLOSED'
                          ? Icons.block_rounded
                          : Icons.add_circle_outline_rounded,
                      size: 18,
                      color: o.type == 'CLOSED'
                          ? AppTheme.errorColor
                          : AppTheme.successColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.type == 'CLOSED'
                                ? (isPartialClosed ? '타임 삭제' : '휴무')
                                : '추가 오픈',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: o.type == 'CLOSED'
                                  ? AppTheme.errorColor
                                  : AppTheme.successColor,
                            ),
                          ),
                          if (o.type == 'OPEN' && o.startTime != null)
                            Text(
                              '${o.startTime} - ${o.endTime}'
                              ' (${o.slotDuration ?? 60}분'
                              '${(o.breakMinutes ?? 0) > 0 ? ', 쉬는시간 ${o.breakMinutes}분' : ''}'
                              ', 정원 ${o.maxCapacity ?? 1}명)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            )
                          else if (isPartialClosed)
                            Text(
                              '${o.startTime} - ${o.endTime} / 해당 시간만 삭제',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.grey.shade400,
                      ),
                      onPressed: () => _deleteOverride(o.id),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],

          // Add new override
          if (!_isAdding)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isAdding = true),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('빈 타임/타임 삭제 추가'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else ...[
            const Divider(),
            const SizedBox(height: 8),
            // Type selector
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _type = 'CLOSED'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _type == 'CLOSED'
                            ? AppTheme.errorColor.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _type == 'CLOSED'
                              ? AppTheme.errorColor.withValues(alpha: 0.4)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.block_rounded,
                            color: _type == 'CLOSED'
                                ? AppTheme.errorColor
                                : Colors.grey,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '타임 삭제',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _type == 'CLOSED'
                                  ? AppTheme.errorColor
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _type = 'OPEN'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _type == 'OPEN'
                            ? AppTheme.successColor.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _type == 'OPEN'
                              ? AppTheme.successColor.withValues(alpha: 0.4)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.add_circle_outline_rounded,
                            color: _type == 'OPEN'
                                ? AppTheme.successColor
                                : Colors.grey,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '빈 타임 생성',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _type == 'OPEN'
                                  ? AppTheme.successColor
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // OPEN-specific fields
            if (_type == 'OPEN') ...[
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('시작', style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        _fmt(_startTime),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (t != null) setState(() => _startTime = t);
                      },
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('종료', style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        _fmt(_endTime),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (t != null) setState(() => _endTime = t);
                      },
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _slotDurationController,
                      decoration: const InputDecoration(
                        labelText: '수업 시간 (분)',
                        isDense: true,
                        hintText: '예: 60',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed != null && parsed >= 15) {
                          _slotDuration = parsed;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _breakMinutesController,
                      decoration: const InputDecoration(
                        labelText: '쉬는시간 (분)',
                        isDense: true,
                        hintText: '예: 10',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed != null && parsed >= 0) {
                          _breakMinutes = parsed;
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _maxCapacity,
                      decoration: const InputDecoration(
                        labelText: '한 타임당 정원',
                        isDense: true,
                      ),
                      items: List.generate(
                        10,
                        (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('${i + 1}명'),
                        ),
                      ),
                      onChanged: (v) => setState(() => _maxCapacity = v ?? 1),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('회원 앱에 공개'),
                subtitle: Text(
                  _isPublic ? '회원이 예약 가능한 빈 타임으로 봅니다' : '관리자 화면에서만 보입니다',
                ),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
              ),
            ],

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _isAdding = false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _createOverride,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(_type == 'CLOSED' ? '타임 삭제' : '빈 타임 생성'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
