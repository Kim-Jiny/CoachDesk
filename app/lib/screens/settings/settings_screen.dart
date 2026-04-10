import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/member_auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('더보기')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Gradient profile card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    child: Text(
                      (authState.user?.name ?? '?')[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          authState.user?.name ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          authState.user?.email ?? '',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Organization info card
            if (authState.organization != null) ...[
              _SettingsGroup(
                children: [
                  _SettingsItem(
                    icon: Icons.business_rounded,
                    iconColor: AppTheme.primaryColor,
                    title: '스튜디오',
                    subtitle: authState.organization!.name,
                  ),
                  _SettingsItem(
                    icon: Icons.vpn_key_rounded,
                    iconColor: AppTheme.secondaryColor,
                    title: '초대 코드',
                    subtitle: authState.organization!.inviteCode,
                    trailing: IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 20,
                        color: Colors.grey.shade500,
                      ),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: authState.organization!.inviteCode,
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('초대 코드가 복사되었습니다'),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Menu groups
            _SettingsGroup(
              children: [
                _SettingsItem(
                  icon: Icons.inventory_2_rounded,
                  iconColor: Colors.teal,
                  title: '패키지 관리',
                  onTap: () => context.push('/packages'),
                ),
                _SettingsItem(
                  icon: Icons.bar_chart_rounded,
                  iconColor: Colors.blue,
                  title: '매출 리포트',
                  onTap: () => context.push('/reports/revenue'),
                ),
                _SettingsItem(
                  icon: Icons.pie_chart_rounded,
                  iconColor: Colors.purple,
                  title: '출석 통계',
                  onTap: () => context.push('/reports/attendance'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _SettingsGroup(
              children: [
                _SettingsItem(
                  icon: Icons.schedule_rounded,
                  iconColor: Colors.orange,
                  title: '수업시간 설정',
                  onTap: () => context.push('/settings/schedules'),
                ),
                _SettingsItem(
                  icon: Icons.group_rounded,
                  iconColor: AppTheme.successColor,
                  title: '팀 관리',
                  onTap: () => context.push('/settings/team'),
                ),
                _SettingsItem(
                  icon: Icons.notifications_active_rounded,
                  iconColor: Colors.redAccent,
                  title: '알림 설정',
                  onTap: () => context.push('/settings/notifications'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Switch to member mode
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final memberNotifier = ref.read(memberAuthProvider.notifier);
                  final hasMemberToken =
                      ApiClient.getMemberAccessToken() != null;
                  if (hasMemberToken) {
                    final switched = await memberNotifier.switchFromAdmin();
                    if (switched && context.mounted) {
                      context.go('/member/home');
                    }
                  } else {
                    if (context.mounted) context.go('/member/login');
                  }
                },
                icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                label: const Text('회원 모드로 전환'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Logout button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: const Text('로그아웃'),
                      content: const Text('로그아웃 하시겠습니까?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            '확인',
                            style: TextStyle(color: AppTheme.errorColor),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  }
                },
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('로그아웃'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  side: BorderSide(
                    color: AppTheme.errorColor.withValues(alpha: 0.3),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, indent: 56, color: Colors.grey.shade100),
          ],
        ],
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            )
          : null,
      trailing:
          trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400)
              : null),
      onTap: onTap,
    );
  }
}
