import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ui_settings_provider.dart';
import '../../widgets/common.dart';

final dashboardProvider = FutureProvider.autoDispose((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/reports/dashboard');
  return response.data as Map<String, dynamic>;
});

final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/notifications/unread-count');
  return response.data['count'] as int? ?? 0;
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final dashboard = ref.watch(dashboardProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);
    final hideRevenueAmount = ref.watch(hideRevenueAmountProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dashboardProvider);
          ref.invalidate(unreadNotificationCountProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Gradient welcome header
            SliverToBoxAdapter(
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 20,
                  right: 20,
                  bottom: 24,
                ),
                decoration: const BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '안녕하세요, ${authState.user?.name ?? ''}님',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (authState.selectedCenter != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  authState.selectedCenter!.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat(
                                'yyyy년 M월 d일 (E)',
                                'ko',
                              ).format(DateTime.now()),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.notifications_outlined,
                                  color: Colors.white,
                                ),
                                onPressed: () => context.push('/notifications'),
                              ),
                            ),
                            unreadCount.when(
                              data: (count) => count > 0
                                  ? Positioned(
                                      top: -2,
                                      right: -2,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppTheme.errorColor,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                        child: Text(
                                          count > 99 ? '99+' : '$count',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Dashboard content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                child: dashboard.when(
                  data: (data) =>
                      _buildDashboard(context, ref, data, hideRevenueAmount),
                  loading: () =>
                      const ShimmerLoading(style: ShimmerStyle.stats),
                  error: (_, _) => const EmptyState(
                    icon: Icons.error_outline,
                    message: '데이터를 불러올 수 없습니다',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_create_reservation_fab',
        onPressed: () => context.push('/reservations/new'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDashboard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
    bool hideRevenueAmount,
  ) {
    final todayReservations = data['todayReservations'] as List? ?? [];
    final formatter = NumberFormat('#,###');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stats grid
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: '오늘 완료된 수업',
                value: '${data['todaySessions'] ?? 0}',
                icon: Icons.fitness_center,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: '대기 예약',
                value: '${data['pendingReservations'] ?? 0}',
                icon: Icons.schedule,
                color: Colors.orange,
                onTap: () async {
                  await context.push('/reservations/pending');
                  if (!context.mounted) return;
                  ref.invalidate(dashboardProvider);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: '패키지 이용 회원',
                value: '${data['activeMembers'] ?? 0}',
                icon: Icons.people,
                color: AppTheme.successColor,
                onTap: () => context.push('/packages/members'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: '이번 달 매출',
                value: hideRevenueAmount
                    ? '금액 숨김'
                    : '${formatter.format(data['monthRevenue'] ?? 0)}원',
                icon: Icons.attach_money,
                color: AppTheme.secondaryColor,
                onTap: () =>
                    context.push('/reports/revenue', extra: DateTime.now()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionHeader(title: '빠른 작업'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.add_circle_outline,
                title: '새 예약',
                subtitle: '바로 등록',
                color: AppTheme.primaryColor,
                onTap: () => context.push('/reservations/new'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.person_add_alt_1,
                title: '회원 등록',
                subtitle: '신규 추가',
                color: AppTheme.successColor,
                onTap: () => context.push('/members-form'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.inventory_2_outlined,
                title: '패키지 관리',
                subtitle: '상품 설정',
                color: AppTheme.secondaryColor,
                onTap: () => context.push('/packages'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.schedule_rounded,
                title: '수업시간 설정',
                subtitle: '시간 관리',
                color: Colors.orange,
                onTap: () => context.push('/settings/schedules'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Today's reservations
        const SectionHeader(title: '오늘 예약'),
        const SizedBox(height: 8),
        if (todayReservations.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppTheme.softShadow,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.event_available,
                  size: 40,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  '오늘 예약이 없습니다',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ],
            ),
          )
        else
          ...todayReservations.map(
            (r) => _TimelineReservationCard(reservation: r),
          ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
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
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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

class _TimelineReservationCard extends StatelessWidget {
  final Map<String, dynamic> reservation;

  const _TimelineReservationCard({required this.reservation});

  @override
  Widget build(BuildContext context) {
    final status = reservation['status'] as String?;
    final color = _statusColor(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Timeline indicator
            SizedBox(
              width: 56,
              child: Column(
                children: [
                  Text(
                    reservation['startTime'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reservation['endTime'] as String? ?? '',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            // Vertical line
            Container(
              width: 3,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Card
            Expanded(
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
                        (reservation['member']?['name'] as String? ?? '?')[0],
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        reservation['member']?['name'] as String? ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    StatusBadge.fromStatus(status),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    return switch (status) {
      'CONFIRMED' => Colors.blue,
      'PENDING' => Colors.orange,
      'COMPLETED' => const Color(0xFF22C55E),
      'CANCELLED' => Colors.red,
      _ => Colors.grey,
    };
  }
}
