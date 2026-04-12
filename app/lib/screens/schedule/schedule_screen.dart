import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/reservation_provider.dart';
import '../../providers/schedule_override_provider.dart';
import '../../models/reservation.dart';
import '../../models/schedule_override.dart';
import '../../widgets/common.dart';
import 'widgets/schedule_timeline_widgets.dart';

Color _timelineStatusColor(String status) {
  return switch (status) {
    'CONFIRMED' => Colors.blue,
    'PENDING' => Colors.orange,
    'COMPLETED' => AppTheme.successColor,
    'CANCELLED' => AppTheme.errorColor,
    'NO_SHOW' => AppTheme.errorColor,
    _ => Colors.grey,
  };
}

String _timelineStatusLabel(String status) {
  return switch (status) {
    'CONFIRMED' => '확정',
    'PENDING' => '대기',
    'COMPLETED' => '완료',
    'CANCELLED' => '취소',
    'NO_SHOW' => '노쇼',
    _ => status,
  };
}

bool _canCompleteReservation(Reservation reservation) {
  final parts = reservation.endTime.split(':').map(int.parse).toList();
  final endDateTime = DateTime(
    reservation.date.year,
    reservation.date.month,
    reservation.date.day,
    parts[0],
    parts[1],
  );
  return !DateTime.now().isBefore(endDateTime);
}

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  List<Map<String, dynamic>> _slots = [];
  bool _slotsLoading = false;
  String? _slotLoadError;
  _TimelineFilter _filter = _TimelineFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshAll();
    });
  }

  Future<void> _refreshAll() async {
    _loadReservations();
    _loadOverrides();
    await _loadSlots();
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
      _loadReservations();
      _loadSlots();
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
    final deltaMinutes = await _showTimeAdjustDialog(reservation);
    if (deltaMinutes == null || !mounted) return;

    final warnings = _buildTimeAdjustmentWarnings(reservation, deltaMinutes);
    var force = false;
    if (warnings.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('확인이 필요한 변경이에요'),
          content: Text('${warnings.join('\n\n')}\n\n그래도 시간을 조정하시겠어요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('그래도 진행'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      force = true;
    }

    try {
      final dio = ref.read(dioProvider);
      await dio.patch(
        '/reservations/${reservation.id}/delay',
        data: {'delayMinutes': deltaMinutes, 'force': force},
      );
      await _refreshAll();
      if (!mounted) return;
      final absMinutes = deltaMinutes.abs();
      final direction = deltaMinutes > 0 ? '미뤘습니다' : '앞당겼습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('예약을 $absMinutes분 $direction')));
    } on DioException catch (e) {
      if (!mounted) return;
      final message =
          e.response?.data?['error'] as String? ?? '예약 시간 조정에 실패했습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예약 시간 조정에 실패했습니다')));
    }
  }

  List<String> _buildTimeAdjustmentWarnings(
    Reservation reservation,
    int deltaMinutes,
  ) {
    final warnings = <String>[];
    final newStart = _shiftTime(reservation.startTime, deltaMinutes);
    final newEnd = _shiftTime(reservation.endTime, deltaMinutes);
    if (newStart == null || newEnd == null) {
      return warnings;
    }

    final conflict = _findConflictingReservation(reservation, deltaMinutes);
    if (conflict != null) {
      warnings.add(
        '${conflict.startTime} - ${conflict.endTime} ${conflict.memberName ?? '다른 수업'}과 겹칩니다.',
      );
    }

    final relatedSlots = _slots.where((slot) {
      if (slot['coachId'] != reservation.coachId) return false;
      return _overlapsTime(
        newStart,
        newEnd,
        slot['startTime'] as String,
        slot['endTime'] as String,
      );
    }).toList();

    if (relatedSlots.isEmpty) {
      warnings.add('조정한 시간이 현재 가용시간 범위를 벗어납니다.');
    } else if (relatedSlots.any((slot) => slot['blocked'] == true)) {
      warnings.add('조정한 시간이 예약 마감 처리된 구간과 겹칩니다.');
    }

    return warnings;
  }

  Future<int?> _showTimeAdjustDialog(Reservation reservation) {
    final controller = TextEditingController(text: '10');
    var isDelay = true;
    String? errorText;

    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('수업 시간 조절'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 ${reservation.startTime} - ${reservation.endTime}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('앞당기기'),
                        icon: Icon(Icons.arrow_back_rounded),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('미루기'),
                        icon: Icon(Icons.arrow_forward_rounded),
                      ),
                    ],
                    selected: {isDelay},
                    onSelectionChanged: (selection) {
                      setState(() => isDelay = selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: '조절할 시간 (분)',
                      hintText: '1 - 120',
                      suffixText: '분',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final value = int.tryParse(controller.text.trim());
                    if (value == null || value <= 0 || value > 120) {
                      setState(() => errorText = '1에서 120 사이의 값을 입력해주세요');
                      return;
                    }
                    Navigator.pop(dialogContext, isDelay ? value : -value);
                  },
                  child: const Text('적용'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Reservation? _findConflictingReservation(
    Reservation reservation,
    int deltaMinutes,
  ) {
    final newStart = _shiftTime(reservation.startTime, deltaMinutes);
    final newEnd = _shiftTime(reservation.endTime, deltaMinutes);
    if (newStart == null || newEnd == null) return null;

    final reservations = ref.read(reservationProvider).reservations;
    for (final other in reservations) {
      if (other.id == reservation.id) continue;
      if (other.coachId != reservation.coachId) continue;
      if (!_isSameDay(other.date, reservation.date)) continue;
      if (other.status != 'CONFIRMED' && other.status != 'PENDING') continue;
      if (_overlapsTime(newStart, newEnd, other.startTime, other.endTime)) {
        return other;
      }
    }
    return null;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String? _shiftTime(String time, int deltaMinutes) {
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    final total = hour * 60 + minute + deltaMinutes;
    if (total < 0 || total >= 24 * 60) return null;
    final h = (total ~/ 60).toString().padLeft(2, '0');
    final m = (total % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _overlapsTime(String aStart, String aEnd, String bStart, String bEnd) {
    return aStart.compareTo(bEnd) < 0 && bStart.compareTo(aEnd) < 0;
  }

  Future<void> _openReservationFlow(Reservation reservation) async {
    final canComplete = _canCompleteReservation(reservation);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final reservationQuickMemo = reservation.quickMemo?.trim();
        final memberQuickMemo = reservation.memberQuickMemo?.trim();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _timelineStatusColor(
                        reservation.status,
                      ).withValues(alpha: 0.1),
                      child: Text(
                        reservation.memberName?[0] ?? '?',
                        style: TextStyle(
                          color: _timelineStatusColor(reservation.status),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reservation.memberName ?? '예약',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${reservation.startTime} - ${reservation.endTime}',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge.fromStatus(reservation.status),
                  ],
                ),
                const SizedBox(height: 16),
                _ReservationInfoRow(
                  label: '상태',
                  value: _timelineStatusLabel(reservation.status),
                ),
                if (reservation.coachName != null &&
                    reservation.coachName!.isNotEmpty)
                  _ReservationInfoRow(
                    label: '코치',
                    value: reservation.coachName!,
                  ),
                if (memberQuickMemo != null && memberQuickMemo.isNotEmpty)
                  _ReservationInfoRow(label: '회원 메모', value: memberQuickMemo),
                if (reservationQuickMemo != null &&
                    reservationQuickMemo.isNotEmpty)
                  _ReservationInfoRow(
                    label: '예약 메모',
                    value: reservationQuickMemo,
                  ),
                if (reservation.memo != null &&
                    reservation.memo!.trim().isNotEmpty)
                  _ReservationInfoRow(
                    label: '상세 메모',
                    value: reservation.memo!.trim(),
                  ),
                if (reservation.isMemberBooked)
                  _ReservationInfoRow(label: '예약 방식', value: '회원 예약'),
                if (reservation.status == 'CONFIRMED' && !canComplete)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '수업 종료 시간 이후에만 완료 처리할 수 있습니다',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, 'member'),
                  icon: const Icon(Icons.person_outline_rounded),
                  label: const Text('회원 상세 보기'),
                ),
                const SizedBox(height: 20),
                if (reservation.status == 'PENDING') ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle_outline,
                      color: AppTheme.successColor,
                    ),
                    title: const Text('예약 승인'),
                    onTap: () => Navigator.pop(context, 'approve'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.cancel_outlined,
                      color: AppTheme.errorColor,
                    ),
                    title: const Text('예약 거절'),
                    onTap: () => Navigator.pop(context, 'reject'),
                  ),
                ] else if (reservation.status == 'CONFIRMED') ...[
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.cancel_outlined,
                      color: AppTheme.errorColor,
                    ),
                    title: const Text('예약 취소'),
                    subtitle: const Text('회원에게 취소 알림이 전송됩니다'),
                    onTap: () => Navigator.pop(context, 'cancel'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.edit_note_rounded,
                      color: Colors.orange,
                    ),
                    title: const Text('예약 메모 추가/수정'),
                    subtitle: const Text('짧은 메모와 상세 메모를 남길 수 있어요'),
                    onTap: () => Navigator.pop(context, 'edit_memo'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.schedule_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    title: const Text('수업 시간 조절'),
                    subtitle: const Text('앞당기거나 미룰 분 수를 입력합니다'),
                    onTap: () => Navigator.pop(context, 'adjust'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.task_alt_rounded,
                      color: canComplete
                          ? AppTheme.primaryColor
                          : Colors.grey.shade400,
                    ),
                    title: Text(
                      '수업 완료 처리',
                      style: TextStyle(
                        color: canComplete ? null : Colors.grey.shade500,
                      ),
                    ),
                    subtitle: canComplete
                        ? null
                        : const Text('아직 종료 시간이 지나지 않았습니다'),
                    enabled: canComplete,
                    onTap: canComplete
                        ? () => Navigator.pop(context, 'complete')
                        : null,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final first = reservations.first;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${first.startTime} - ${first.endTime}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '예약자 ${reservations.length}명',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: reservations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final reservation = reservations[index];
                      final reservationQuickMemo = reservation.quickMemo
                          ?.trim();
                      final memberQuickMemo = reservation.memberQuickMemo
                          ?.trim();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () {
                          Navigator.pop(context);
                          _openReservationFlow(reservation);
                        },
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: _timelineStatusColor(
                            reservation.status,
                          ).withValues(alpha: 0.1),
                          child: Text(
                            reservation.memberName?[0] ?? '?',
                            style: TextStyle(
                              color: _timelineStatusColor(reservation.status),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          reservation.memberName ?? '이름 없음',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (memberQuickMemo != null &&
                                memberQuickMemo.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '회원: $memberQuickMemo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.teal.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            if (reservationQuickMemo != null &&
                                reservationQuickMemo.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '예약: $reservationQuickMemo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            if (reservation.isMemberBooked)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '회원 예약',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.deepPurple.shade300,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: StatusBadge.fromStatus(reservation.status),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadSlots() async {
    setState(() {
      _slotsLoading = true;
      _slotLoadError = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDay);
      final response = await dio.get(
        '/schedules/slots',
        queryParameters: {'date': dateStr, 'includePast': true},
      );
      setState(() {
        final data = response.data;
        if (data is List) {
          _slots = data
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        } else if (data is Map<String, dynamic> && data['slots'] is List) {
          _slots = (data['slots'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        } else {
          _slots = [];
        }
        _slotsLoading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _slots = [];
        _slotsLoading = false;
        _slotLoadError =
            e.response?.data?['error'] as String? ?? '스케줄 슬롯을 불러오지 못했습니다';
      });
    } catch (_) {
      setState(() {
        _slots = [];
        _slotsLoading = false;
        _slotLoadError = '스케줄 슬롯을 불러오지 못했습니다';
      });
    }
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

    final success = await ref
        .read(reservationProvider.notifier)
        .updateMemo(
          reservation.id,
          quickMemo: quickMemoController.text.trim(),
          memo: detailMemoController.text.trim(),
        );

    if (!mounted) return;

    if (success) {
      _loadReservations();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예약 메모를 저장했습니다')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예약 메모 저장에 실패했습니다')));
    }
  }

  Future<void> _showEmptySlotActions(Map<String, dynamic> slot) async {
    final isBlocked = slot['blocked'] == true;
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
              if (!isBlocked) ...[
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
                    Icons.block_rounded,
                    color: AppTheme.errorColor,
                  ),
                  title: const Text('예약 마감 처리'),
                  subtitle: const Text('이 시간대를 더 이상 예약할 수 없게 막아요'),
                  onTap: () => Navigator.pop(context, 'close'),
                ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.lock_open_rounded,
                    color: AppTheme.successColor,
                  ),
                  title: const Text('예약 마감 해제'),
                  subtitle: const Text('막아둔 시간대를 다시 예약 가능하게 열어요'),
                  onTap: () => Navigator.pop(context, 'reopen'),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

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

    if (action == 'close') {
      await _closeSlot(slot);
      return;
    }

    if (action == 'reopen') {
      await _reopenSlot(slot);
    }
  }

  Future<void> _toggleSlotVisibility(Map<String, dynamic> slot) async {
    final dio = ref.read(dioProvider);
    final visibilityOverrideId = slot['visibilityOverrideId'] as String?;
    final baseIsPublic = slot['baseIsPublic'] == true;

    try {
      if (visibilityOverrideId != null && visibilityOverrideId.isNotEmpty) {
        await dio.delete('/schedules/overrides/$visibilityOverrideId');
      } else {
        await dio.post(
          '/schedules/overrides',
          data: {
            'coachId': slot['coachId'],
            'date': DateFormat('yyyy-MM-dd').format(_selectedDay),
            'type': baseIsPublic ? 'HIDDEN' : 'VISIBLE',
            'startTime': slot['startTime'],
            'endTime': slot['endTime'],
          },
        );
      }
      await _refreshAll();
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
    } on DioException catch (e) {
      if (!mounted) return;
      final message =
          e.response?.data?['error'] as String? ?? '공개 상태 변경에 실패했습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('공개 상태 변경에 실패했습니다')));
    }
  }

  Future<void> _closeSlot(Map<String, dynamic> slot) async {
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
                '예약 마감 처리',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${DateFormat('M월 d일 (E)', 'ko').format(_selectedDay)} ${slot['startTime']} - ${slot['endTime']}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Text(
                '${slot['coachName'] ?? ''} 코치 시간대를 예약 불가로 막습니다.',
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
                      child: const Text('예약 마감'),
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

    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        '/schedules/overrides',
        data: {
          'coachId': slot['coachId'],
          'date': DateFormat('yyyy-MM-dd').format(_selectedDay),
          'type': 'CLOSED',
          'startTime': slot['startTime'],
          'endTime': slot['endTime'],
        },
      );
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('해당 시간대를 예약 마감 처리했습니다')));
    } on DioException catch (e) {
      if (!mounted) return;
      final message =
          e.response?.data?['error'] as String? ?? '예약 마감 처리에 실패했습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예약 마감 처리에 실패했습니다')));
    }
  }

  Future<void> _reopenSlot(Map<String, dynamic> slot) async {
    final overrideId = slot['blockedOverrideId'] as String?;
    if (overrideId == null || overrideId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('마감 해제 정보를 찾지 못했습니다')));
      return;
    }

    try {
      final dio = ref.read(dioProvider);
      await dio.delete('/schedules/overrides/$overrideId');
      await _refreshAll();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예약 마감을 해제했습니다')));
    } on DioException catch (e) {
      if (!mounted) return;
      final message =
          e.response?.data?['error'] as String? ?? '예약 마감 해제에 실패했습니다';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예약 마감 해제에 실패했습니다')));
    }
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

  void _showOverrideSheet() {
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

  List<Reservation> _getEventsForDay(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    return ref.read(reservationProvider).reservations.where((r) {
      return DateFormat('yyyy-MM-dd').format(r.date) == dateStr;
    }).toList();
  }

  bool _isPastTime(String startTime) {
    final now = DateTime.now();
    final selected = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    if (selected.isBefore(today)) return true;
    if (selected.isAfter(today)) return false;

    final parts = startTime.split(':').map(int.parse).toList();
    final slotDateTime = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      parts[0],
      parts[1],
    );
    return slotDateTime.isBefore(now);
  }

  @override
  Widget build(BuildContext context) {
    final reservationState = ref.watch(reservationProvider);
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
    final availableSlotCount = _slots
        .where((slot) => slot['available'] == true)
        .length;
    final pastSlotCount = _slots
        .where((slot) => _isPastTime(slot['startTime'] as String))
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
                children: _TimelineFilter.values.map((filter) {
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
              child: (reservationState.isLoading || _slotsLoading)
                  ? const ShimmerLoading(style: ShimmerStyle.card, itemCount: 3)
                  : Builder(
                      builder: (context) {
                        // Build merged timeline items
                        final timelineItems = <_TimelineItem>[];
                        final reservationMap = <String, List<Reservation>>{};
                        for (final r in dayReservations) {
                          final key = '${r.coachId}|${r.startTime}';
                          reservationMap.putIfAbsent(key, () => []).add(r);
                        }

                        final matchedKeys = <String>{};

                        // Add slots (with or without reservation)
                        for (final slot in _slots) {
                          final key = '${slot['coachId']}|${slot['startTime']}';
                          final reservations = reservationMap[key];
                          if (reservations != null && reservations.isNotEmpty) {
                            matchedKeys.add(key);
                            timelineItems.add(
                              _TimelineItem(
                                startTime: reservations.first.startTime,
                                reservations: reservations,
                                slot: slot,
                              ),
                            );
                          } else {
                            timelineItems.add(
                              _TimelineItem(
                                startTime: slot['startTime'] as String,
                                slot: slot,
                              ),
                            );
                          }
                        }

                        // Add reservations not matched to any slot
                        for (final entry in reservationMap.entries) {
                          final key = entry.key;
                          if (!matchedKeys.contains(key)) {
                            final reservations = entry.value;
                            timelineItems.add(
                              _TimelineItem(
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
                          final isPast = _isPastTime(item.startTime);
                          return switch (_filter) {
                            _TimelineFilter.all => true,
                            _TimelineFilter.reservations =>
                              item.hasReservations,
                            _TimelineFilter.open =>
                              item.slot != null &&
                                  item.slot!['available'] == true,
                            _TimelineFilter.past => isPast,
                          };
                        }).toList();
                        final emptyStateTitle = switch (_filter) {
                          _TimelineFilter.all => '표시할 타임라인이 없습니다',
                          _TimelineFilter.reservations => '예약된 타임이 없습니다',
                          _TimelineFilter.open => '남아 있는 빈 타임이 없습니다',
                          _TimelineFilter.past => '지난 타임이 없습니다',
                        };
                        final emptyStateMessage = switch (_filter) {
                          _TimelineFilter.all =>
                            '선택한 날짜에 표시할 일정이 없습니다.\n스케줄 설정이나 예외 일정을 확인해보세요.',
                          _TimelineFilter.reservations =>
                            '이 날짜에는 예약되거나 신청된 수업이 없습니다.',
                          _TimelineFilter.open =>
                            '현재 남아 있는 예약 가능 타임이 없습니다.\n다른 날짜를 보거나 정원을 확인해보세요.',
                          _TimelineFilter.past => '선택한 날짜에는 지난 시간대가 없습니다.',
                        };

                        if (_slotLoadError != null && filteredItems.isEmpty) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                            children: [
                              ScheduleStateCard(
                                icon: Icons.cloud_off_rounded,
                                iconColor: AppTheme.errorColor,
                                title: '스케줄을 불러오지 못했습니다',
                                message: _slotLoadError!,
                                actionLabel: '다시 시도',
                                onAction: _refreshAll,
                              ),
                            ],
                          );
                        }

                        if (filteredItems.isEmpty) {
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
                            final isPast = _isPastTime(item.startTime);
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
                              return EmptySlotCard(
                                slot: item.slot!,
                                isPast: isPast,
                                title: item.slot!['blocked'] == true
                                    ? '예약 마감된 타임'
                                    : item.slot!['isPublic'] == true
                                    ? '빈 타임 · 공개'
                                    : '빈 타임 · 비공개',
                                subtitle: item.slot!['blocked'] == true
                                    ? '눌러서 마감 해제'
                                    : item.slot!['isPublic'] == true
                                    ? '회원이 예약 가능한 시간'
                                    : '회원 앱에는 보이지 않는 시간',
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
        onPressed: () async {
          final result = await context.push(
            '/reservations/new',
            extra: {'date': DateFormat('yyyy-MM-dd').format(_selectedDay)},
          );
          if (result == true) {
            _loadReservations();
            _loadSlots();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ReservationInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReservationInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Timeline Item Model ──────────────────────────────────
class _TimelineItem {
  final String startTime;
  final List<Reservation>? reservations;
  final Map<String, dynamic>? slot;

  _TimelineItem({required this.startTime, this.reservations, this.slot});

  bool get hasReservations => reservations != null && reservations!.isNotEmpty;
}

// ─── Empty Slot Card ──────────────────────────────────────
enum _TimelineFilter {
  all('전체 타임'),
  reservations('예약된 타임'),
  open('빈 타임'),
  past('지난 타임');

  const _TimelineFilter(this.label);
  final String label;
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
  bool _isAdding = false;
  String _type = 'CLOSED';
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  int _slotDuration = 60;
  int _breakMinutes = 0;
  int _maxCapacity = 1;
  final _slotDurationController = TextEditingController(text: '60');
  final _breakMinutesController = TextEditingController(text: '0');

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
            ...widget.overrides.map(
              (o) => Container(
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
                            o.type == 'CLOSED' ? '휴무' : '추가 오픈',
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
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Add new override
          if (!_isAdding)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isAdding = true),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('오버라이드 추가'),
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
                            '휴무',
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
                            '추가 오픈',
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
                    child: Text(_type == 'CLOSED' ? '휴무 설정' : '추가 오픈'),
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
