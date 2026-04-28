import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/package.dart';
import '../../providers/member_auth_provider.dart';

class MemberPackageDetailScreen extends ConsumerStatefulWidget {
  final String memberPackageId;

  const MemberPackageDetailScreen({super.key, required this.memberPackageId});

  @override
  ConsumerState<MemberPackageDetailScreen> createState() =>
      _MemberPackageDetailScreenState();
}

class _MemberPackageDetailScreenState
    extends ConsumerState<MemberPackageDetailScreen> {
  MemberPackageDetail? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final detail = await ref
        .read(memberAuthProvider.notifier)
        .fetchMyPackageDetail(widget.memberPackageId);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('yyyy.MM.dd').format(date);
  }

  String _formatDateTime(DateTime date) =>
      DateFormat('yyyy.MM.dd HH:mm').format(date);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('패키지 상세')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? const Center(child: Text('패키지 정보를 불러오지 못했습니다'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      _HeaderCard(detail: _detail!),
                      const SizedBox(height: 16),
                      _PeriodCard(
                        detail: _detail!,
                        formatDate: _formatDate,
                      ),
                      const SizedBox(height: 16),
                      _AdjustmentsSection(
                        adjustments: _detail!.adjustments,
                        formatDateTime: _formatDateTime,
                        formatDate: _formatDate,
                      ),
                      const SizedBox(height: 16),
                      _SessionsSection(
                        sessions: _detail!.sessions,
                        formatDate: _formatDate,
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final MemberPackageDetail detail;
  const _HeaderCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final pkg = detail.memberPackage;
    final total = pkg.totalSessions == 0 ? 1 : pkg.totalSessions;
    final progress = pkg.remainingSessions / total;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pkg.package?.name ?? '패키지',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            '잔여 ${pkg.remainingSessions}/${pkg.totalSessions}회',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 8,
              backgroundColor: Colors.grey.shade100,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  final MemberPackageDetail detail;
  final String Function(DateTime?) formatDate;
  const _PeriodCard({required this.detail, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final pkg = detail.memberPackage;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          _PeriodRow(label: '시작일', value: formatDate(pkg.purchaseDate)),
          const Divider(height: 20),
          _PeriodRow(
            label: '만료일',
            value: pkg.expiryDate == null ? '무제한' : formatDate(pkg.expiryDate),
          ),
          if (pkg.pauseExtensionDays > 0) ...[
            const Divider(height: 20),
            _PeriodRow(
              label: '정지로 연장된 기간',
              value: '${pkg.pauseExtensionDays}일',
            ),
          ],
          if (pkg.pauseStartDate != null && pkg.pauseEndDate != null) ...[
            const Divider(height: 20),
            _PeriodRow(
              label: '현재 정지 기간',
              value:
                  '${formatDate(pkg.pauseStartDate)} ~ ${formatDate(pkg.pauseEndDate)}',
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final String label;
  final String value;
  const _PeriodRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _AdjustmentsSection extends StatelessWidget {
  final List<MemberPackageAdjustment> adjustments;
  final String Function(DateTime) formatDateTime;
  final String Function(DateTime?) formatDate;

  const _AdjustmentsSection({
    required this.adjustments,
    required this.formatDateTime,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '관리자 조정 내역',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (adjustments.isEmpty)
          _EmptyCard(text: '아직 조정된 내역이 없습니다')
        else
          ...adjustments.map(
            (adjustment) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
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
                      Text(
                        adjustment.typeLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatDateTime(adjustment.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (adjustment.isSessionAdjustment)
                    Text(
                      '${adjustment.sessionDelta > 0 ? '+' : ''}${adjustment.sessionDelta}회',
                      style: TextStyle(
                        fontSize: 13,
                        color: adjustment.sessionDelta > 0
                            ? AppTheme.primaryColor
                            : AppTheme.errorColor,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text(
                      '${formatDate(adjustment.expiryDateBefore)} → ${formatDate(adjustment.expiryDateAfter)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  if (adjustment.reason != null &&
                      adjustment.reason!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      adjustment.reason!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '처리: ${adjustment.adminName}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SessionsSection extends StatelessWidget {
  final List<MemberPackageSessionEntry> sessions;
  final String Function(DateTime?) formatDate;

  const _SessionsSection({required this.sessions, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '사용 이력',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              '${sessions.length}회',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (sessions.isEmpty)
          _EmptyCard(text: '아직 사용한 수업이 없습니다')
        else
          ...sessions.map(
            (session) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppTheme.softShadow,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatDate(session.date),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (session.startTime != null &&
                                session.endTime != null)
                              '${session.startTime} - ${session.endTime}',
                            if (session.coachName.isNotEmpty)
                              session.coachName,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (session.attendance != 'PRESENT')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _attendanceLabel(session.attendance),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _attendanceLabel(String attendance) => switch (attendance) {
        'NO_SHOW' => '불참',
        'LATE' => '지각',
        'CANCELLED' => '취소',
        _ => attendance,
      };
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.softShadow,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
      ),
    );
  }
}
