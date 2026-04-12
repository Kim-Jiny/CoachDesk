import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/member_auth_provider.dart';

final appVersionProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

class SettingsScreen extends ConsumerStatefulWidget {
  final bool isMember;

  const SettingsScreen({super.key, this.isMember = false});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final memberState = ref.watch(memberAuthProvider);
    final version = ref.watch(appVersionProvider);
    final isMember = widget.isMember;
    final title = isMember ? '회원 설정' : '관리자 설정';
    final name = isMember ? memberState.name : authState.user?.name;
    final email = isMember ? memberState.email : authState.user?.email;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileCard(
              title: name ?? '계정',
              subtitle: email ?? '',
              badge: isMember ? '회원 모드' : '관리자 모드',
              icon: isMember
                  ? Icons.person_rounded
                  : Icons.admin_panel_settings_rounded,
            ),
            const SizedBox(height: 12),
            _SectionTitle(isMember ? '회원 계정' : '관리자 계정'),
            _SettingsGroup(
              children: [
                _SettingsItem(
                  icon: Icons.badge_rounded,
                  iconColor: AppTheme.primaryColor,
                  title: '이름',
                  subtitle: name ?? '-',
                ),
                _SettingsItem(
                  icon: Icons.mail_rounded,
                  iconColor: Colors.blue,
                  title: '이메일',
                  subtitle: email ?? '-',
                ),
                if (isMember)
                  _SettingsItem(
                    icon: Icons.school_rounded,
                    iconColor: Colors.teal,
                    title: '참여 중인 수업',
                    subtitle: memberState.classes.isEmpty
                        ? '참여 중인 수업이 없습니다'
                        : memberState.classes
                              .map((item) => item.organizationName)
                              .join(', '),
                  )
                else if (authState.selectedCenter != null) ...[
                  _SettingsItem(
                    icon: Icons.business_rounded,
                    iconColor: Colors.teal,
                    title: '센터',
                    subtitle: authState.selectedCenter!.name,
                  ),
                  _SettingsItem(
                    icon: Icons.vpn_key_rounded,
                    iconColor: AppTheme.secondaryColor,
                    title: '초대 코드',
                    subtitle: authState.selectedCenter!.inviteCode,
                    trailing: IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 20,
                        color: Colors.grey.shade500,
                      ),
                      onPressed: () => _copyInviteCode(
                        context,
                        authState.selectedCenter!.inviteCode,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _SectionTitle('푸시 설정'),
            _SettingsGroup(
              children: [
                _SettingsItem(
                  icon: Icons.notifications_active_rounded,
                  iconColor: Colors.redAccent,
                  title: '알림 설정',
                  subtitle: isMember
                      ? '예약, 채팅, 패키지 알림을 회원 기준으로 설정합니다'
                      : '예약, 채팅, 패키지 알림을 관리자 기준으로 설정합니다',
                  onTap: () => context.push(
                    isMember
                        ? '/member/settings/notifications'
                        : '/settings/notifications',
                  ),
                ),
              ],
            ),
            if (!isMember) ...[
              const SizedBox(height: 16),
              _SectionTitle('관리 메뉴'),
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
                ],
              ),
            ],
            const SizedBox(height: 16),
            _SectionTitle('앱 정보'),
            _SettingsGroup(
              children: [
                _SettingsItem(
                  icon: Icons.info_rounded,
                  iconColor: Colors.indigo,
                  title: '앱 버전',
                  subtitle: version.when(
                    data: (info) => '${info.version} (${info.buildNumber})',
                    loading: () => '확인 중',
                    error: (_, _) => '버전 정보를 불러오지 못했습니다',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildModeButton(context, ref),
            const SizedBox(height: 10),
            _buildLogoutButton(context, ref),
            const SizedBox(height: 10),
            _buildDeleteAccountButton(context, ref),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _copyInviteCode(BuildContext context, String inviteCode) {
    Clipboard.setData(ClipboardData(text: inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('초대 코드가 복사되었습니다'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildModeButton(BuildContext context, WidgetRef ref) {
    final isMember = widget.isMember;
    return OutlinedButton.icon(
      onPressed: () async {
        if (isMember) {
          final hasAdminToken = ApiClient.getAdminAccessToken() != null;
          if (hasAdminToken) {
            final switched =
                await ref.read(authProvider.notifier).switchFromMember();
            if (!switched && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('관리자 모드로 전환할 수 없습니다'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
            // Router redirect navigates based on center state
          } else if (context.mounted) {
            context.go('/login');
          }
          return;
        }

        final memberNotifier = ref.read(memberAuthProvider.notifier);
        final hasMemberToken = ApiClient.getMemberAccessToken() != null;
        if (hasMemberToken) {
          final switched = await memberNotifier.switchFromAdmin();
          if (!switched && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('회원 모드로 전환할 수 없습니다'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          // Router redirect navigates to /member/home
        } else if (context.mounted) {
          context.go('/member/login');
        }
      },
      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
      label: Text(isMember ? '관리자 모드로 전환' : '회원 모드로 전환'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryColor,
        side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () async {
        final confirmed = await _confirm(
          context,
          title: '로그아웃',
          content: '로그아웃 하시겠습니까?',
          actionText: '로그아웃',
        );
        if (confirmed != true) return;

        if (widget.isMember) {
          await ref.read(memberAuthProvider.notifier).logout();
        } else {
          await ref.read(authProvider.notifier).logout();
        }
        if (!context.mounted) return;
        context.go(widget.isMember ? '/auth-select' : '/login');
      },
      icon: const Icon(Icons.logout_rounded, size: 20),
      label: const Text('로그아웃'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.errorColor,
        side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildDeleteAccountButton(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: _isDeleting
          ? null
          : () async {
              final isMember = widget.isMember;
              final confirmed = await _confirm(
                context,
                title: isMember ? '회원 탈퇴' : '관리자 계정 삭제',
                content: isMember
                    ? '회원 로그인 계정이 삭제됩니다. 기존 스튜디오의 회원 기록과 예약 기록은 보존됩니다.'
                    : '관리자 로그인 권한이 제거됩니다. 수업, 예약, 세션 기록은 보존되며 조직에 남은 관리자/오너가 없으면 삭제할 수 없습니다.',
                actionText: isMember ? '탈퇴하기' : '삭제하기',
              );
              if (confirmed != true) return;

              setState(() => _isDeleting = true);
              final error = isMember
                  ? await ref.read(memberAuthProvider.notifier).deleteAccount()
                  : await ref.read(authProvider.notifier).deleteAccount();
              if (!context.mounted) return;
              setState(() => _isDeleting = false);

              if (error != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error)));
                return;
              }
              context.go('/auth-select');
            },
      icon: _isDeleting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.delete_forever_rounded, size: 20),
      label: Text(widget.isMember ? '회원 탈퇴' : '관리자 계정 삭제'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.errorColor,
        side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String content,
    required String actionText,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              actionText,
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;

  const _ProfileCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontSize: 13,
          fontWeight: FontWeight.w800,
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
