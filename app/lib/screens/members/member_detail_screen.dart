import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/member_provider.dart';
import '../../widgets/common.dart';

final memberDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final dio = ref.watch(dioProvider);
      final response = await dio.get('/members/$id');
      return response.data as Map<String, dynamic>;
    });

class MemberDetailScreen extends ConsumerStatefulWidget {
  final String memberId;

  const MemberDetailScreen({super.key, required this.memberId});

  @override
  ConsumerState<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends ConsumerState<MemberDetailScreen> {
  int _tabIndex = 0;
  String? _processingPackageId;

  bool _isPackageActive(String? status) => status == 'PACKAGE_ACTIVE';

  Future<void> _approvePauseRequest(String memberPackageId) async {
    setState(() => _processingPackageId = memberPackageId);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(
        '/packages/member-packages/$memberPackageId/pause/approve',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.data['message'] as String? ?? '정지 신청을 승인했습니다'),
        ),
      );
      ref.invalidate(memberDetailProvider(widget.memberId));
      ref.read(memberProvider.notifier).fetchMembers();
    } finally {
      if (mounted) {
        setState(() => _processingPackageId = null);
      }
    }
  }

  Future<void> _openChatWithMember(Map<String, dynamic> data) async {
    final memberAccountId = data['memberAccountId'] as String?;
    if (memberAccountId == null) return;

    final auth = ref.read(authProvider);
    final coachId = auth.user?.id;
    final orgId = auth.organization?.id;
    if (coachId == null || orgId == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final room = await ref
        .read(chatRoomListProvider.notifier)
        .getOrCreateRoom(
          organizationId: orgId,
          userId: coachId,
          memberAccountId: memberAccountId,
        );

    if (!mounted) return;
    if (room == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('채팅방을 열 수 없습니다')),
      );
      return;
    }

    // Refresh list so the new room appears with latest metadata.
    await ref.read(chatRoomListProvider.notifier).fetchRooms();
    if (!mounted) return;
    router.push('/chat/${room.id}');
  }

  Future<void> _changeMemberGroup(Map<String, dynamic> data) async {
    // Make sure the group list is loaded. `fetchMembers` loads both members
    // and groups in one call, so use it when we don't have any groups yet.
    if (ref.read(memberProvider).groups.isEmpty) {
      await ref.read(memberProvider.notifier).fetchMembers();
    }
    if (!mounted) return;

    final groups = [...ref.read(memberProvider).groups]
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    final currentGroupId =
        (data['memberGroup'] as Map<String, dynamic>?)?['id'] as String? ??
        data['memberGroupId'] as String?;

    final result = await showModalBottomSheet<_GroupChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '그룹 변경',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _GroupChoiceTile(
                      title: '미분류',
                      subtitle: '어떤 그룹에도 속하지 않습니다',
                      icon: Icons.folder_open_outlined,
                      selected: currentGroupId == null,
                      onTap: () => Navigator.pop(
                        sheetContext,
                        const _GroupChoice(id: null, name: '미분류'),
                      ),
                    ),
                    for (final group in groups)
                      _GroupChoiceTile(
                        title: group.name,
                        icon: Icons.folder_outlined,
                        selected: currentGroupId == group.id,
                        onTap: () => Navigator.pop(
                          sheetContext,
                          _GroupChoice(id: group.id, name: group.name),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (result == null || !mounted) return;
    if (result.id == currentGroupId) return;

    final success = await ref
        .read(memberProvider.notifier)
        .moveMemberToGroup(widget.memberId, result.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '${data['name'] as String? ?? '회원'}님을 "${result.name}" 그룹으로 이동했습니다'
              : '그룹 변경에 실패했습니다',
        ),
      ),
    );

    if (success) {
      ref.invalidate(memberDetailProvider(widget.memberId));
    }
  }

  Future<void> _rejectPauseRequest(String memberPackageId) async {
    setState(() => _processingPackageId = memberPackageId);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/packages/member-packages/$memberPackageId/pause/reject');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('정지 신청을 반려했습니다')));
      ref.invalidate(memberDetailProvider(widget.memberId));
      ref.read(memberProvider.notifier).fetchMembers();
    } finally {
      if (mounted) {
        setState(() => _processingPackageId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(memberDetailProvider(widget.memberId));

    return Scaffold(
      body: detail.when(
        data: (data) => _buildContent(context, ref, data),
        loading: () => const Center(
          child: ShimmerLoading(style: ShimmerStyle.card, itemCount: 4),
        ),
        error: (_, _) => const Center(
          child: EmptyState(
            icon: Icons.error_outline,
            message: '회원 정보를 불러올 수 없습니다',
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
  ) {
    final packages = (data['memberPackages'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final sessions = (data['sessions'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final hasAssignedPackages = packages.isNotEmpty;
    final activePackages = packages
        .where(
          (package) =>
              package['status'] == 'ACTIVE' &&
              !(package['pauseStartDate'] != null &&
                  package['pauseEndDate'] != null),
        )
        .length;
    final completedSessions = sessions
        .where((session) => session['attendance'] == 'PRESENT')
        .length;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 20,
              right: 20,
              bottom: 28,
            ),
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if ((data['hasMemberAccount'] as bool? ?? false) &&
                            (data['memberAccountId'] as String?) != null)
                          IconButton(
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              color: Colors.white,
                            ),
                            tooltip: '채팅하기',
                            onPressed: () => _openChatWithMember(data),
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Colors.white,
                          ),
                          onPressed: () async {
                            final result = await context.push(
                              '/members-form',
                              extra: data,
                            );
                            if (result == true) {
                              ref.invalidate(
                                memberDetailProvider(widget.memberId),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  child: Text(
                    (data['name'] as String? ?? '?')[0],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  data['name'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                if (data['phone'] != null)
                  Text(
                    data['phone'] as String,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                if (data['email'] != null)
                  Text(
                    data['email'] as String,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _isPackageActive(data['packageStatus'] as String?)
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    data['packageStatusLabel'] as String? ?? '일반 회원',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    StatusBadge(
                      label:
                          data['memberSourceLabel'] as String? ?? '관리자 등록 회원',
                      color: (data['hasMemberAccount'] as bool? ?? false)
                          ? AppTheme.primaryColor
                          : Colors.blueGrey,
                    ),
                    StatusBadge(
                      label: data['memberAccessLabel'] as String? ?? '채팅 미연동',
                      color: (data['hasMemberAccount'] as bool? ?? false)
                          ? Colors.orange
                          : Colors.grey,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _HeaderMetric(
                        label: '활성 패키지',
                        value: '$activePackages',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeaderMetric(
                        label: '최근 세션',
                        value: '${sessions.length}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeaderMetric(
                        label: '출석 완료',
                        value: '$completedSessions',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.add_circle_outline,
                        title: '예약 등록',
                        subtitle: '이 회원으로 바로 시작',
                        color: AppTheme.primaryColor,
                        onTap: () => context.push(
                          '/reservations/new',
                          extra: {
                            'memberId': data['id'],
                            'memberName': data['name'],
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.inventory_2_outlined,
                        title: hasAssignedPackages ? '추가 패키지 할당' : '패키지 할당',
                        subtitle: hasAssignedPackages
                            ? '기존 회원권에 이어서 추가'
                            : '빠르게 추가',
                        color: AppTheme.successColor,
                        onTap: () async {
                          final result = await context.push(
                            '/packages/assign',
                            extra: {
                              'memberId': data['id'] as String,
                              'memberName': data['name'] as String,
                            },
                          );
                          if (result == true) {
                            ref.invalidate(
                              memberDetailProvider(widget.memberId),
                            );
                            // Refresh the member list so packageStatus label
                            // (e.g. "패키지 이용 회원") updates when the user
                            // navigates back.
                            ref
                                .read(memberProvider.notifier)
                                .fetchMembers();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _TabChip(
                        label: '요약',
                        selected: _tabIndex == 0,
                        onTap: () => setState(() => _tabIndex = 0),
                      ),
                      const SizedBox(width: 8),
                      _TabChip(
                        label: '패키지',
                        selected: _tabIndex == 1,
                        onTap: () => setState(() => _tabIndex = 1),
                      ),
                      const SizedBox(width: 8),
                      _TabChip(
                        label: '세션',
                        selected: _tabIndex == 2,
                        onTap: () => setState(() => _tabIndex = 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_tabIndex == 0) ...[
                  _buildSummaryCard(data),
                  const SizedBox(height: 16),
                  if (data['quickMemo'] != null &&
                      (data['quickMemo'] as String).isNotEmpty)
                    _buildQuickMemoCard(data['quickMemo'] as String),
                  if (data['quickMemo'] != null &&
                      (data['quickMemo'] as String).isNotEmpty)
                    const SizedBox(height: 12),
                  if (data['memo'] != null &&
                      (data['memo'] as String).isNotEmpty)
                    _buildMemoCard(data['memo'] as String),
                  if (data['memo'] != null &&
                      (data['memo'] as String).isNotEmpty)
                    const SizedBox(height: 16),
                  const SectionHeader(title: '최근 패키지'),
                  const SizedBox(height: 8),
                  if (packages.isEmpty)
                    _buildEmptyCard('등록된 패키지가 없습니다')
                  else
                    ...packages
                        .take(2)
                        .map(
                          (package) => _PackageProgressCard(
                            package: package,
                            isProcessing: _processingPackageId == package['id'],
                            onApprovePause:
                                package['pauseRequestStatus'] == 'PENDING'
                                ? () => _approvePauseRequest(
                                    package['id'] as String,
                                  )
                                : null,
                            onRejectPause:
                                package['pauseRequestStatus'] == 'PENDING'
                                ? () => _rejectPauseRequest(
                                    package['id'] as String,
                                  )
                                : null,
                          ),
                        ),
                  const SizedBox(height: 16),
                  const SectionHeader(title: '최근 세션'),
                  const SizedBox(height: 8),
                  if (sessions.isEmpty)
                    _buildEmptyCard('세션 기록이 없습니다')
                  else
                    ...sessions
                        .take(3)
                        .map(
                          (session) => _SessionHistoryCard(session: session),
                        ),
                ] else if (_tabIndex == 1) ...[
                  Row(
                    children: [
                      const Expanded(child: SectionHeader(title: '패키지')),
                      Text(
                        '${packages.length}개',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (packages.isEmpty)
                    _buildEmptyCard('등록된 패키지가 없습니다')
                  else
                    ...packages.map(
                      (package) => _PackageProgressCard(
                        package: package,
                        isProcessing: _processingPackageId == package['id'],
                        onApprovePause:
                            package['pauseRequestStatus'] == 'PENDING'
                            ? () =>
                                  _approvePauseRequest(package['id'] as String)
                            : null,
                        onRejectPause:
                            package['pauseRequestStatus'] == 'PENDING'
                            ? () => _rejectPauseRequest(package['id'] as String)
                            : null,
                      ),
                    ),
                ] else ...[
                  Row(
                    children: [
                      const Expanded(child: SectionHeader(title: '세션 기록')),
                      TextButton(
                        onPressed: () => context.push(
                          '/sessions',
                          extra: data['id'] as String,
                        ),
                        child: const Text('전체 보기'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (sessions.isEmpty)
                    _buildEmptyCard('세션 기록이 없습니다')
                  else
                    ...sessions.map(
                      (session) => _SessionHistoryCard(session: session),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> data) {
    final groupName =
        (data['memberGroup'] as Map<String, dynamic>?)?['name'] as String? ??
        '미분류';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: '그룹',
            value: groupName,
            trailing: TextButton.icon(
              onPressed: () => _changeMemberGroup(data),
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('변경'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 0,
                ),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          _SummaryRow(label: '전화번호', value: data['phone'] as String? ?? '미등록'),
          _SummaryRow(label: '이메일', value: data['email'] as String? ?? '미등록'),
          _SummaryRow(
            label: '생년월일',
            value: _formatDate(data['birthDate'] as String?),
          ),
          _SummaryRow(
            label: '성별',
            value: _genderLabel(data['gender'] as String?),
          ),
          _SummaryRow(
            label: '회원 유형',
            value: data['memberSourceLabel'] as String? ?? '관리자 등록 회원',
          ),
          _SummaryRow(
            label: '연동 상태',
            value: data['memberAccessLabel'] as String? ?? '채팅 미연동',
          ),
          _SummaryRow(
            label: '회원 상태',
            value: data['packageStatusLabel'] as String? ?? '일반 회원',
          ),
          _SummaryRow(
            label: '계정 상태',
            value: _memberAccountStatusLabel(data['status'] as String?),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMemoCard(String memo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.sticky_note_2_outlined,
            color: Colors.amber.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              memo,
              style: TextStyle(color: Colors.amber.shade900, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMemoCard(String memo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.short_text_rounded,
            color: Colors.orange.shade700,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              memo,
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.softShadow,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      ),
    );
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '미등록';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return DateFormat('yyyy.MM.dd').format(parsed);
  }

  String _genderLabel(String? gender) {
    switch (gender) {
      case 'MALE':
        return '남성';
      case 'FEMALE':
        return '여성';
      case 'OTHER':
        return '기타';
      default:
        return '미등록';
    }
  }

  String _memberAccountStatusLabel(String? status) {
    switch (status) {
      case 'ACTIVE':
        return '사용 중';
      case 'INACTIVE':
        return '비활성';
      case 'ARCHIVED':
        return '보관됨';
      default:
        return status ?? '-';
    }
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : Colors.white,
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;
  final Widget? trailing;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isLast = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PackageProgressCard extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback? onApprovePause;
  final VoidCallback? onRejectPause;
  final bool isProcessing;

  const _PackageProgressCard({
    required this.package,
    this.onApprovePause,
    this.onRejectPause,
    this.isProcessing = false,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = package['remainingSessions'] as int? ?? 0;
    final total = package['totalSessions'] as int? ?? 1;
    final progress = total > 0 ? remaining / total : 0.0;
    final isActive = package['status'] == 'ACTIVE';
    final isPaused =
        package['pauseStartDate'] != null && package['pauseEndDate'] != null;
    final hasPendingPause = package['pauseRequestStatus'] == 'PENDING';
    final pauseRequestedStartDate =
        package['pauseRequestedStartDate'] as String?;
    final pauseRequestedEndDate = package['pauseRequestedEndDate'] as String?;
    final pauseStartDate = package['pauseStartDate'] as String?;
    final pauseEndDate = package['pauseEndDate'] as String?;
    final expiryDate = package['expiryDate'] as String?;
    final pauseExtensionDays = package['pauseExtensionDays'] as int? ?? 0;

    String formatDateLabel(String? value) {
      if (value == null || value.isEmpty) return '-';
      final parsed = DateTime.tryParse(value);
      if (parsed == null) return value;
      return DateFormat('yyyy.MM.dd').format(parsed);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
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
                    package['package']?['name'] as String? ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                StatusBadge(
                  label: hasPendingPause
                      ? '정지 신청'
                      : isPaused
                      ? '정지 중'
                      : isActive
                      ? '사용중'
                      : (package['status'] as String? ?? ''),
                  color: hasPendingPause
                      ? Colors.orange
                      : isPaused
                      ? Colors.orange
                      : isActive
                      ? AppTheme.successColor
                      : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '잔여 $remaining/$total회',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const Spacer(),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: progress > 0.3
                        ? AppTheme.primaryColor
                        : AppTheme.errorColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: Colors.grey.shade100,
                color: isPaused
                    ? Colors.orange
                    : progress > 0.3
                    ? AppTheme.primaryColor
                    : AppTheme.errorColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '만료일: ${expiryDate == null ? '무제한' : formatDateLabel(expiryDate)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (pauseExtensionDays > 0) ...[
              const SizedBox(height: 4),
              Text(
                '정지 승인으로 총 $pauseExtensionDays일 연장됨',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
              ),
            ],
            if (hasPendingPause &&
                pauseRequestedStartDate != null &&
                pauseRequestedEndDate != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '회원 정지 신청: ${formatDateLabel(pauseRequestedStartDate)} ~ ${formatDateLabel(pauseRequestedEndDate)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    if ((package['pauseRequestReason'] as String?)
                            ?.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 4),
                      Text(
                        package['pauseRequestReason'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isProcessing ? null : onRejectPause,
                      child: const Text('반려'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: isProcessing ? null : onApprovePause,
                      child: isProcessing
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('승인'),
                    ),
                  ),
                ],
              ),
            ],
            if (isPaused && pauseStartDate != null && pauseEndDate != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '현재 정지 기간: ${formatDateLabel(pauseStartDate)} ~ ${formatDateLabel(pauseEndDate)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupChoice {
  final String? id;
  final String name;
  const _GroupChoice({required this.id, required this.name});
}

class _GroupChoiceTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GroupChoiceTile({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? AppTheme.primaryColor : Colors.blueGrey,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? AppTheme.primaryColor : null,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryColor)
          : null,
      onTap: onTap,
    );
  }
}

class _SessionHistoryCard extends StatelessWidget {
  final Map<String, dynamic> session;

  const _SessionHistoryCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final attendance = session['attendance'] as String?;
    final (icon, color) = switch (attendance) {
      'PRESENT' => (Icons.check_circle_rounded, AppTheme.successColor),
      'LATE' => (Icons.schedule_rounded, Colors.orange),
      'NO_SHOW' => (Icons.cancel_rounded, AppTheme.errorColor),
      'CANCELLED' => (Icons.block_rounded, Colors.grey),
      _ => (Icons.circle, Colors.grey),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppTheme.softShadow,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (session['date'] as String? ?? '').split('T')[0],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (session['memo'] != null &&
                      (session['memo'] as String).isNotEmpty)
                    Text(
                      session['memo'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              _attendanceLabel(attendance),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _attendanceLabel(String? value) {
    switch (value) {
      case 'PRESENT':
        return '출석';
      case 'LATE':
        return '지각';
      case 'NO_SHOW':
        return '노쇼';
      case 'CANCELLED':
        return '취소';
      default:
        return value ?? '-';
    }
  }
}
