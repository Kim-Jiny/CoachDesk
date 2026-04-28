import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/member.dart';
import '../../models/package.dart';
import '../../providers/member_provider.dart';
import '../../widgets/common.dart';

class MemberPackageSummaryScreen extends ConsumerStatefulWidget {
  const MemberPackageSummaryScreen({super.key});

  @override
  ConsumerState<MemberPackageSummaryScreen> createState() =>
      _MemberPackageSummaryScreenState();
}

class _MemberPackageSummaryScreenState
    extends ConsumerState<MemberPackageSummaryScreen> {
  final NumberFormat _countFormatter = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(memberProvider.notifier).fetchMembers());
  }

  Future<void> _refresh() => ref.read(memberProvider.notifier).fetchMembers();

  bool _isActiveMemberPackage(MemberPackage memberPackage) {
    if (memberPackage.status != 'ACTIVE' ||
        memberPackage.remainingSessions <= 0) {
      return false;
    }
    final expiryDate = memberPackage.expiryDate;
    if (expiryDate == null) return true;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return !expiry.isBefore(today);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '무제한';
    return DateFormat('yyyy.MM.dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memberProvider);
    final members = state.members
        .where((member) => member.packageStatus == 'PACKAGE_ACTIVE')
        .map(
          (member) => (
            member: member,
            packages: member.memberPackages
                .where(_isActiveMemberPackage)
                .toList(),
          ),
        )
        .where((entry) => entry.packages.isNotEmpty)
        .toList();
    final packageCount = members.fold<int>(
      0,
      (sum, entry) => sum + entry.packages.length,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('패키지 이용 회원')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: _SummaryCard(
                  memberCount: members.length,
                  packageCount: packageCount,
                  countFormatter: _countFormatter,
                ),
              ),
            ),
            if (state.isLoading && state.members.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: ShimmerLoading(style: ShimmerStyle.card, itemCount: 5),
                ),
              )
            else if (state.error != null && state.members.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.error_outline,
                  message: '패키지 이용 회원을 불러올 수 없습니다',
                  actionLabel: '다시 시도',
                  onAction: _refresh,
                ),
              )
            else if (members.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.inventory_2_outlined,
                  message: '현재 이용 중인 패키지 회원이 없습니다',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.separated(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final entry = members[index];
                    return _MemberPackageCard(
                      member: entry.member,
                      packages: entry.packages,
                      formatDate: _formatDate,
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int memberCount;
  final int packageCount;
  final NumberFormat countFormatter;

  const _SummaryCard({
    required this.memberCount,
    required this.packageCount,
    required this.countFormatter,
  });

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                '현재 패키지 이용 현황',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${countFormatter.format(memberCount)}명의 회원이 '
            '${countFormatter.format(packageCount)}개의 패키지를 이용 중이에요',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberPackageCard extends StatelessWidget {
  final Member member;
  final List<MemberPackage> packages;
  final String Function(DateTime?) formatDate;

  const _MemberPackageCard({
    required this.member,
    required this.packages,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => context.push('/members/${member.id}'),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    member.name.isEmpty ? '?' : member.name.characters.first,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.successColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        member.phone?.isNotEmpty == true
                            ? member.phone!
                            : member.memberGroupName ?? '그룹 미지정',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge.fromStatus(member.packageStatus),
              ],
            ),
            const SizedBox(height: 16),
            for (final memberPackage in packages) ...[
              _PackageTile(
                memberPackage: memberPackage,
                formatDate: formatDate,
              ),
              if (memberPackage != packages.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  final MemberPackage memberPackage;
  final String Function(DateTime?) formatDate;

  const _PackageTile({required this.memberPackage, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final package = memberPackage.package;
    final progress = memberPackage.totalSessions == 0
        ? 0.0
        : memberPackage.remainingSessions / memberPackage.totalSessions;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  package?.name ?? '패키지',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '잔여 ${memberPackage.remainingSessions}/${memberPackage.totalSessions}회',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 7,
              backgroundColor: Colors.white,
              color: AppTheme.successColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.event_available_outlined,
                label: '만료 ${formatDate(memberPackage.expiryDate)}',
              ),
              if (package?.coachName?.isNotEmpty == true)
                _MetaChip(
                  icon: Icons.person_outline,
                  label: '${package!.coachName} 전용',
                ),
              if (package != null)
                _MetaChip(
                  icon: package.isAdminScoped
                      ? Icons.admin_panel_settings_outlined
                      : Icons.apartment_outlined,
                  label: package.scopeLabel,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
