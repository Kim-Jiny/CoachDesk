import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/reservation.dart';
import '../../../widgets/common.dart';

class ScheduleStateCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const ScheduleStateCard({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedIconColor = iconColor ?? Colors.grey.shade400;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: resolvedIconColor),
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
              color: Colors.grey.shade600,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onAction,
            icon: const Icon(Icons.tune_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class HeaderChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const HeaderChip({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class TimelineScheduleCard extends StatelessWidget {
  final List<Reservation> reservations;
  final Map<String, dynamic>? slot;
  final bool isPast;
  final VoidCallback? onTap;

  const TimelineScheduleCard({
    super.key,
    required this.reservations,
    this.slot,
    required this.isPast,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryReservation = reservations.first;
    final color = isPast
        ? Colors.grey.shade500
        : _timelineStatusColor(_aggregateStatus(reservations));
    final reservationQuickMemo = primaryReservation.quickMemo?.trim();
    final memberQuickMemo = primaryReservation.memberQuickMemo?.trim();
    final shouldShowInlineMemberMemo =
        reservations.length == 1 &&
        memberQuickMemo != null &&
        memberQuickMemo.isNotEmpty;
    final statusSummary = _buildStatusSummary(reservations);
    final delaySummary = primaryReservation.delayMinutes > 0
        ? '${primaryReservation.delayMinutes}분 지연'
        : null;
    final displayName = reservations.length > 1
        ? '${primaryReservation.memberName ?? '예약자'} 외 +${reservations.length - 1}'
        : (primaryReservation.memberName ?? '');
    final displayEndTime =
        slot?['endTime'] as String? ?? primaryReservation.endTime;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    primaryReservation.startTime,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayEndTime,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            Container(
              width: 3,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: color.withValues(alpha: 0.1),
                        child: Text(
                          primaryReservation.memberName?[0] ?? '?',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (shouldShowInlineMemberMemo) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      memberQuickMemo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.teal.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (reservations.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  statusSummary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (delaySummary != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  delaySummary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            if (reservationQuickMemo != null &&
                                reservationQuickMemo.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
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
                            if (primaryReservation.isMemberBooked)
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
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (reservations.length > 1)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${reservations.length}명',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          StatusBadge.fromStatus(
                            _aggregateStatus(reservations),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildStatusSummary(List<Reservation> reservations) {
    final pending = reservations
        .where((reservation) => reservation.status == 'PENDING')
        .length;
    final confirmed = reservations
        .where((reservation) => reservation.status == 'CONFIRMED')
        .length;
    final completed = reservations
        .where((reservation) => reservation.status == 'COMPLETED')
        .length;
    final labels = <String>[];
    if (pending > 0) labels.add('대기 $pending');
    if (confirmed > 0) labels.add('확정 $confirmed');
    if (completed > 0) labels.add('완료 $completed');
    return labels.isEmpty ? '예약 ${reservations.length}명' : labels.join(' · ');
  }
}

class EmptySlotCard extends StatelessWidget {
  final Map<String, dynamic> slot;
  final bool isPast;
  final VoidCallback? onTap;
  final String? title;
  final String? subtitle;
  final bool hasCancelled;

  const EmptySlotCard({
    super.key,
    required this.slot,
    required this.isPast,
    this.onTap,
    this.title,
    this.subtitle,
    this.hasCancelled = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = title ?? (isPast ? '지난 빈 타임' : '예약 가능한 빈 타임');
    final resolvedSubtitle =
        subtitle ??
        (isPast
            ? '이미 지난 시간대입니다'
            : onTap != null
            ? '눌러서 예약 마감 처리'
            : '현재 예약 가능한 시간대입니다');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    slot['startTime'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    slot['endTime'] as String,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            Container(
              width: 3,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isPast ? Colors.grey.shade400 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isPast
                        ? Colors.grey.shade100
                        : hasCancelled
                        ? Colors.red.withValues(alpha: 0.04)
                        : AppTheme.primaryColor.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isPast
                          ? Colors.grey.shade300
                          : hasCancelled
                          ? Colors.red.withValues(alpha: 0.15)
                          : AppTheme.primaryColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: hasCancelled && !isPast
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        child: Icon(
                          hasCancelled
                              ? Icons.event_busy_rounded
                              : Icons.event_available_rounded,
                          color: hasCancelled && !isPast
                              ? Colors.red.shade400
                              : isPast
                              ? Colors.grey.shade500
                              : Colors.grey.shade400,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              resolvedTitle,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                resolvedSubtitle,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: !isPast && onTap != null
                                      ? Colors.red.shade400
                                      : Colors.grey.shade500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

String _aggregateStatus(List<Reservation> reservations) {
  if (reservations.any((reservation) => reservation.status == 'PENDING')) {
    return 'PENDING';
  }
  if (reservations.any((reservation) => reservation.status == 'CONFIRMED')) {
    return 'CONFIRMED';
  }
  if (reservations.any((reservation) => reservation.status == 'COMPLETED')) {
    return 'COMPLETED';
  }
  if (reservations.any((reservation) => reservation.status == 'NO_SHOW')) {
    return 'NO_SHOW';
  }
  if (reservations.any((reservation) => reservation.status == 'CANCELLED')) {
    return 'CANCELLED';
  }
  return reservations.first.status;
}
