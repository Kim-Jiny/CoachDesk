import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/member_booking.dart';
import '../../providers/auth_provider.dart';
import '../../providers/member_auth_provider.dart';
import '../../widgets/admin_register_dialog.dart';

class MemberHomeScreen extends ConsumerStatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  ConsumerState<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends ConsumerState<MemberHomeScreen> {
  List<MemberReservationSummary> _reservations = [];
  bool _isLoadingReservations = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(memberAuthProvider.notifier).fetchMyClasses();
      _loadReservations();
    });
  }

  Future<void> _loadReservations() async {
    setState(() => _isLoadingReservations = true);
    final result = await ref.read(memberAuthProvider.notifier).fetchMyReservations();
    if (mounted) setState(() { _reservations = result; _isLoadingReservations = false; });
  }

  void _showJoinDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('초대코드 입력'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '선생님에게 받은 코드를 입력하세요',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              final success =
                  await ref.read(memberAuthProvider.notifier).joinClass(code);
              if (mounted) {
                final message = success
                    ? '수업에 참여했습니다!'
                    : (ref.read(memberAuthProvider).error ?? '참여에 실패했습니다');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('참여하기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(memberAuthProvider);
    final name = authState.name ?? '회원';
    final classes = authState.classes;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Gradient header
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                bottom: 24,
                left: 24,
                right: 24,
              ),
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$name님의 수업',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${classes.length}개의 수업에 참여중',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        onSelected: (value) async {
                          if (value == 'switch_admin') {
                            final hasAdminToken = ApiClient.getAdminAccessToken() != null;
                            if (hasAdminToken) {
                              final switched = await ref.read(authProvider.notifier).switchFromMember();
                              if (!context.mounted) return;
                              if (switched) context.go('/home');
                            } else {
                              final result = await showDialog<bool>(
                                context: context,
                                builder: (_) => const AdminRegisterDialog(),
                              );
                              if (!context.mounted) return;
                              if (result == true) context.go('/home');
                            }
                          } else if (value == 'logout') {
                            await ref.read(memberAuthProvider.notifier).logout();
                            if (!context.mounted) return;
                            context.go('/auth-select');
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'switch_admin',
                            child: Row(
                              children: [
                                Icon(Icons.swap_horiz, size: 20),
                                SizedBox(width: 8),
                                Text('관리자 모드로 전환'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout, size: 20),
                                SizedBox(width: 8),
                                Text('로그아웃'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Upcoming reservations
          if (_reservations.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  children: [
                    const Text(
                      '다가오는 예약',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_reservations.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 96,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _reservations.length > 5 ? 5 : _reservations.length,
                  itemBuilder: (context, index) {
                    final r = _reservations[index];
                    return Container(
                      width: 200,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppTheme.softShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('M/d (E)', 'ko').format(r.date),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${r.startTime} - ${r.endTime}  ${r.coachName} 코치',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            r.organizationName,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ] else if (!_isLoadingReservations && classes.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox.shrink()),

          // My classes header
          if (classes.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: const Text(
                  '내 수업',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),

          // Content
          if (classes.isEmpty)
            SliverFillRemaining(
              child: _EmptyState(onJoin: _showJoinDialog),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ClassCard(
                      memberClass: classes[index],
                      onTap: () => context.push(
                        '/member/class/${classes[index].organizationId}',
                        extra: classes[index].organizationName,
                      ),
                    ),
                  ),
                  childCount: classes.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: classes.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _showJoinDialog,
              icon: const Icon(Icons.add),
              label: const Text('수업 참여'),
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onJoin;

  const _EmptyState({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.school_outlined,
                size: 64,
                color: AppTheme.primaryColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '참여 중인 수업이 없습니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '선생님에게 받은 초대코드로\n수업에 참여해보세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: onJoin,
                icon: const Icon(Icons.vpn_key_outlined),
                label: const Text('초대코드로 수업 찾기'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  minimumSize: const Size(220, 52),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final MemberClass memberClass;
  final VoidCallback? onTap;

  const _ClassCard({required this.memberClass, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(20),
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fitness_center,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  memberClass.organizationName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (memberClass.coaches.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: memberClass.coaches.map((coach) {
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    child: Text(
                      coach.name.isNotEmpty ? coach.name[0] : '?',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  label: Text(
                    coach.name,
                    style: const TextStyle(fontSize: 13),
                  ),
                  backgroundColor: Colors.grey.shade50,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    ),
    );
  }
}
