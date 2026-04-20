import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/reservation.dart';

Color timelineStatusColor(String status) {
  return switch (status) {
    'CONFIRMED' => Colors.blue,
    'PENDING' => Colors.orange,
    'COMPLETED' => AppTheme.successColor,
    'CANCELLED' => AppTheme.errorColor,
    'NO_SHOW' => AppTheme.errorColor,
    _ => Colors.grey,
  };
}

String timelineStatusLabel(String status) {
  return switch (status) {
    'CONFIRMED' => '확정',
    'PENDING' => '대기',
    'COMPLETED' => '완료',
    'CANCELLED' => '취소',
    'NO_SHOW' => '노쇼',
    _ => status,
  };
}

bool canCompleteReservation(Reservation reservation) {
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

bool isSameCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool isPastTimeForDay({
  required DateTime selectedDay,
  required String startTime,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final selected = DateTime(
    selectedDay.year,
    selectedDay.month,
    selectedDay.day,
  );
  final today = DateTime(current.year, current.month, current.day);
  if (selected.isBefore(today)) return true;
  if (selected.isAfter(today)) return false;

  final parts = startTime.split(':').map(int.parse).toList();
  final slotDateTime = DateTime(
    selectedDay.year,
    selectedDay.month,
    selectedDay.day,
    parts[0],
    parts[1],
  );
  return slotDateTime.isBefore(current);
}

String? shiftTime(String time, int deltaMinutes) {
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

bool overlapsTime(String aStart, String aEnd, String bStart, String bEnd) {
  return aStart.compareTo(bEnd) < 0 && bStart.compareTo(aEnd) < 0;
}

int calculateMinutes(String startTime, String endTime) {
  final startParts = startTime.split(':').map(int.parse).toList();
  final endParts = endTime.split(':').map(int.parse).toList();
  return (endParts[0] * 60 + endParts[1]) -
      (startParts[0] * 60 + startParts[1]);
}

List<Reservation> findConflictingReservations({
  required List<Reservation> reservations,
  required DateTime selectedDay,
  required String coachId,
  required String startTime,
  required String endTime,
  String? excludeReservationId,
}) {
  final conflicts = <Reservation>[];
  for (final other in reservations) {
    if (excludeReservationId != null && other.id == excludeReservationId) {
      continue;
    }
    if (other.coachId != coachId) continue;
    if (!isSameCalendarDay(other.date, selectedDay)) continue;
    if (other.status != 'CONFIRMED' && other.status != 'PENDING') continue;
    if (overlapsTime(startTime, endTime, other.startTime, other.endTime)) {
      conflicts.add(other);
    }
  }
  return conflicts;
}

List<String> buildTimeRangeAdjustmentWarnings({
  required List<Reservation> reservations,
  required List<Map<String, dynamic>> slots,
  required DateTime selectedDay,
  required String coachId,
  required String startTime,
  required String endTime,
  required int deltaMinutes,
  String? excludeReservationId,
}) {
  final warnings = <String>[];
  final newStart = shiftTime(startTime, deltaMinutes);
  final newEnd = shiftTime(endTime, deltaMinutes);
  if (newStart == null || newEnd == null) {
    return warnings;
  }

  final conflicts = findConflictingReservations(
    reservations: reservations,
    selectedDay: selectedDay,
    coachId: coachId,
    startTime: newStart,
    endTime: newEnd,
    excludeReservationId: excludeReservationId,
  );
  if (conflicts.isNotEmpty) {
    final primaryConflict = conflicts.first;
    final title = primaryConflict.memberName?.trim().isNotEmpty == true
        ? primaryConflict.memberName!
        : '다른 수업';
    final suffix = conflicts.length > 1 ? ' 외 ${conflicts.length - 1}건' : '';
    warnings.add(
      '${primaryConflict.startTime} - ${primaryConflict.endTime} $title$suffix 수업과 겹칩니다.',
    );
  }

  final relatedSlots = slots.where((slot) {
    if (slot['coachId'] != coachId) return false;
    return overlapsTime(
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

class TimelineItem {
  final String startTime;
  final List<Reservation>? reservations;
  final Map<String, dynamic>? slot;
  final int cancelledCount;

  TimelineItem({
    required this.startTime,
    this.reservations,
    this.slot,
    this.cancelledCount = 0,
  });

  bool get hasReservations => reservations != null && reservations!.isNotEmpty;
}

enum TimelineFilter {
  all('전체 타임'),
  reservations('예약된 타임'),
  open('빈 타임'),
  past('지난 타임');

  const TimelineFilter(this.label);
  final String label;
}
