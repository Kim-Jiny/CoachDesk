import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../providers/session_provider.dart';
import '../../widgets/common.dart';

class SessionListScreen extends ConsumerStatefulWidget {
  final String? memberId;
  const SessionListScreen({super.key, this.memberId});

  @override
  ConsumerState<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends ConsumerState<SessionListScreen> {
  String _attendanceFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sessionProvider.notifier).fetchSessions(
      memberId: widget.memberId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionProvider);
    final filteredSessions = sessionState.sessions.where((session) {
      return _attendanceFilter == 'ALL' || session.attendance == _attendanceFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('세션 기록')),
      body: sessionState.isLoading
          ? const ShimmerLoading(style: ShimmerStyle.list)
          : sessionState.sessions.isEmpty
              ? const EmptyState(
                  icon: Icons.history_rounded,
                  message: '세션 기록이 없습니다',
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _AttendanceChip(
                              label: '전체',
                              selected: _attendanceFilter == 'ALL',
                              onTap: () => setState(() => _attendanceFilter = 'ALL'),
                            ),
                            const SizedBox(width: 8),
                            _AttendanceChip(
                              label: '출석',
                              selected: _attendanceFilter == 'PRESENT',
                              onTap: () => setState(() => _attendanceFilter = 'PRESENT'),
                            ),
                            const SizedBox(width: 8),
                            _AttendanceChip(
                              label: '지각',
                              selected: _attendanceFilter == 'LATE',
                              onTap: () => setState(() => _attendanceFilter = 'LATE'),
                            ),
                            const SizedBox(width: 8),
                            _AttendanceChip(
                              label: '노쇼',
                              selected: _attendanceFilter == 'NO_SHOW',
                              onTap: () => setState(() => _attendanceFilter = 'NO_SHOW'),
                            ),
                            const SizedBox(width: 8),
                            _AttendanceChip(
                              label: '취소',
                              selected: _attendanceFilter == 'CANCELLED',
                              onTap: () => setState(() => _attendanceFilter = 'CANCELLED'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: filteredSessions.isEmpty
                          ? EmptyState(
                              icon: Icons.filter_alt_off_rounded,
                              message: '선택한 상태의 세션이 없습니다',
                              actionLabel: '필터 초기화',
                              onAction: () => setState(() => _attendanceFilter = 'ALL'),
                            )
                          : RefreshIndicator(
                              onRefresh: () => ref.read(sessionProvider.notifier).fetchSessions(
                                memberId: widget.memberId,
                              ),
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: filteredSessions.length,
                                itemBuilder: (context, index) {
                                  final session = filteredSessions[index];
                                  return Card(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _attendanceColor(session.attendance),
                                        child: Icon(
                                          _attendanceIcon(session.attendance),
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(session.memberName ?? ''),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${DateFormat('M/d (E)', 'ko').format(session.date)}'
                                            '${session.startTime != null ? ' ${session.startTime}' : ''}',
                                          ),
                                          if (session.memo != null && session.memo!.isNotEmpty)
                                            Text(
                                              session.memo!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                            ),
                                        ],
                                      ),
                                      trailing: Text(
                                        _attendanceLabel(session.attendance),
                                        style: TextStyle(
                                          color: _attendanceColor(session.attendance),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      isThreeLine: session.memo != null && session.memo!.isNotEmpty,
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                )
    );
  }

  Color _attendanceColor(String attendance) {
    switch (attendance) {
      case 'PRESENT': return Colors.green;
      case 'LATE': return Colors.orange;
      case 'NO_SHOW': return Colors.red;
      case 'CANCELLED': return Colors.grey;
      default: return Colors.grey;
    }
  }

  IconData _attendanceIcon(String attendance) {
    switch (attendance) {
      case 'PRESENT': return Icons.check;
      case 'LATE': return Icons.schedule;
      case 'NO_SHOW': return Icons.close;
      case 'CANCELLED': return Icons.cancel;
      default: return Icons.help;
    }
  }

  String _attendanceLabel(String attendance) {
    switch (attendance) {
      case 'PRESENT': return '출석';
      case 'LATE': return '지각';
      case 'NO_SHOW': return '노쇼';
      case 'CANCELLED': return '취소';
      default: return attendance;
    }
  }
}

class _AttendanceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AttendanceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : Colors.grey.shade200,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppTheme.primaryColor : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
