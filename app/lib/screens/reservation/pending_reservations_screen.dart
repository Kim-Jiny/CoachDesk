import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/reservation_provider.dart';
import '../../widgets/common.dart';

class PendingReservationsScreen extends ConsumerStatefulWidget {
  const PendingReservationsScreen({super.key});

  @override
  ConsumerState<PendingReservationsScreen> createState() =>
      _PendingReservationsScreenState();
}

class _PendingReservationsScreenState
    extends ConsumerState<PendingReservationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_loadPendingReservations);
  }

  Future<void> _loadPendingReservations() async {
    await ref
        .read(reservationProvider.notifier)
        .fetchReservations(status: 'PENDING');
  }

  Future<void> _handleAction({
    required String reservationId,
    required String memberName,
    required bool approve,
  }) async {
    final title = approve ? '예약 승인' : '예약 거절';
    final message = approve
        ? '$memberName님의 예약을 승인하시겠어요?'
        : '$memberName님의 예약을 거절하시겠어요?';
    final confirmLabel = approve ? '승인' : '거절';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor:
                  approve ? AppTheme.successColor : AppTheme.errorColor,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await ref
        .read(reservationProvider.notifier)
        .updateStatus(reservationId, approve ? 'CONFIRMED' : 'CANCELLED');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (approve ? '예약이 승인되었습니다' : '예약이 거절되었습니다')
              : '처리 중 오류가 발생했습니다',
        ),
        backgroundColor: success
            ? (approve ? AppTheme.successColor : AppTheme.errorColor)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reservationState = ref.watch(reservationProvider);
    final reservations = reservationState.reservations
        .where((reservation) => reservation.status == 'PENDING')
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('대기 예약')),
      body: reservationState.isLoading
          ? const Center(
              child: ShimmerLoading(style: ShimmerStyle.card, itemCount: 5),
            )
          : reservations.isEmpty
          ? EmptyState(
              icon: Icons.schedule_send_outlined,
              message: '대기 중인 예약이 없습니다',
              actionLabel: '새로고침',
              onAction: _loadPendingReservations,
            )
          : RefreshIndicator(
              onRefresh: _loadPendingReservations,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: reservations.length,
                itemBuilder: (context, index) {
                  final reservation = reservations[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppTheme.softShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                reservation.memberName ?? '회원',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            StatusBadge.fromStatus(reservation.status),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _PendingInfoRow(
                          icon: Icons.calendar_today_rounded,
                          label: DateFormat(
                            'yyyy년 M월 d일 (E)',
                            'ko',
                          ).format(reservation.date),
                        ),
                        const SizedBox(height: 6),
                        _PendingInfoRow(
                          icon: Icons.access_time_rounded,
                          label:
                              '${reservation.startTime} - ${reservation.endTime}',
                        ),
                        const SizedBox(height: 6),
                        _PendingInfoRow(
                          icon: Icons.person_outline_rounded,
                          label: reservation.coachName == null
                              ? '코치 미지정'
                              : '${reservation.coachName} 코치',
                        ),
                        if ((reservation.memberQuickMemo ?? '').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              reservation.memberQuickMemo!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _handleAction(
                                  reservationId: reservation.id,
                                  memberName: reservation.memberName ?? '회원',
                                  approve: false,
                                ),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                ),
                                label: const Text('거절'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.errorColor,
                                  side: BorderSide(
                                    color: AppTheme.errorColor
                                        .withValues(alpha: 0.5),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _handleAction(
                                  reservationId: reservation.id,
                                  memberName: reservation.memberName ?? '회원',
                                  approve: true,
                                ),
                                icon: const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                ),
                                label: const Text('승인'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.successColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _PendingInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PendingInfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }
}
