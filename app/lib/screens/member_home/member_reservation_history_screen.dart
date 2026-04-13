import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/member_booking.dart';
import '../../widgets/common.dart';

class MemberReservationHistoryScreen extends ConsumerStatefulWidget {
  const MemberReservationHistoryScreen({super.key});

  @override
  ConsumerState<MemberReservationHistoryScreen> createState() =>
      _MemberReservationHistoryScreenState();
}

class _MemberReservationHistoryScreenState
    extends ConsumerState<MemberReservationHistoryScreen> {
  final List<ReservationHistoryItem> _items = [];
  String? _nextCursor;
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '/auth/member/reservation-history',
        queryParameters: {
          'limit': '20',
          if (_nextCursor != null) 'cursor': _nextCursor,
        },
      );
      final data = response.data as Map<String, dynamic>;
      final reservations = (data['reservations'] as List)
          .map((e) =>
              ReservationHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final cursor = data['nextCursor'] as String?;

      if (mounted) {
        setState(() {
          _items.addAll(reservations);
          _nextCursor = cursor;
          _hasMore = cursor != null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _nextCursor = null;
      _hasMore = true;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('예약 히스토리')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _items.isEmpty && !_isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 140),
                  EmptyState(
                    icon: Icons.history_rounded,
                    message: '예약 기록이 없습니다',
                  ),
                ],
              )
            : _buildList(),
      ),
    );
  }

  Widget _buildList() {
    // Group by month
    final grouped = <String, List<ReservationHistoryItem>>{};
    for (final item in _items) {
      final key = DateFormat('yyyy년 M월').format(item.date);
      grouped.putIfAbsent(key, () => []).add(item);
    }

    final sections = grouped.entries.toList();

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: sections.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= sections.length) {
          if (!_isLoading) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _loadMore());
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final entry = sections[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                entry.key,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            ...entry.value.map(_buildCard),
          ],
        );
      },
    );
  }

  Widget _buildCard(ReservationHistoryItem item) {
    final statusInfo = _statusInfo(item.status);
    final isCompleted = item.status == 'COMPLETED';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('M/d (E)', 'ko').format(item.date),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusInfo.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusInfo.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusInfo.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${item.startTime} - ${item.endTime}  ${item.coachName} 코치',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 2),
          Text(
            item.organizationName,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          if (isCompleted && item.attendance != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _attendanceIcon(item.attendance!),
                  size: 14,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  _attendanceLabel(item.attendance!),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ],
          if (isCompleted &&
              item.feedback != null &&
              item.feedback!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.feedback!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static ({String label, Color color}) _statusInfo(String status) {
    return switch (status) {
      'PENDING' => (label: '대기', color: Colors.orange.shade700),
      'CONFIRMED' => (label: '확정', color: Colors.green.shade700),
      'COMPLETED' => (label: '완료', color: AppTheme.primaryColor),
      'CANCELLED' => (label: '취소', color: Colors.red.shade600),
      'NO_SHOW' => (label: '노쇼', color: Colors.grey.shade600),
      _ => (label: status, color: Colors.grey.shade600),
    };
  }

  static IconData _attendanceIcon(String attendance) {
    return switch (attendance) {
      'PRESENT' => Icons.check_circle_outline,
      'LATE' => Icons.schedule,
      'NO_SHOW' => Icons.cancel_outlined,
      'CANCELLED' => Icons.block,
      _ => Icons.help_outline,
    };
  }

  static String _attendanceLabel(String attendance) {
    return switch (attendance) {
      'PRESENT' => '출석',
      'LATE' => '지각',
      'NO_SHOW' => '노쇼',
      'CANCELLED' => '취소',
      _ => attendance,
    };
  }
}
