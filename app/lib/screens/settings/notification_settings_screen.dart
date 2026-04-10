import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fcm_service.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  final bool isMember;

  const NotificationSettingsScreen({super.key, required this.isMember});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  NotificationPreferences _preferences = const NotificationPreferences();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _preferences = FcmService.getCachedNotificationPreferences(
      isMember: widget.isMember,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final preferences = await FcmService.syncNotificationPreferences(
        isMember: widget.isMember,
      );
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _update(NotificationPreferences next) async {
    setState(() {
      _preferences = next;
      _isSaving = true;
    });

    try {
      await FcmService.updateNotificationPreferences(
        isMember: widget.isMember,
        preferences: next,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('알림 설정을 저장했습니다')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('알림 설정 저장에 실패했습니다')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isMember ? '앱 설정' : '알림 설정'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SettingsSwitchCard(
                  title: '예약 알림',
                  subtitle: '예약 신청, 승인, 거절, 취소, 시간 변경 알림',
                  value: _preferences.reservation,
                  onChanged: (value) =>
                      _update(_preferences.copyWith(reservation: value)),
                ),
                const SizedBox(height: 10),
                _SettingsSwitchCard(
                  title: '채팅 알림',
                  subtitle: '채팅 메시지 알림',
                  value: _preferences.chat,
                  onChanged: (value) =>
                      _update(_preferences.copyWith(chat: value)),
                ),
                const SizedBox(height: 10),
                _SettingsSwitchCard(
                  title: '패키지 알림',
                  subtitle: '패키지 정지 승인/반려 등 패키지 관련 알림',
                  value: _preferences.package,
                  onChanged: (value) =>
                      _update(_preferences.copyWith(package: value)),
                ),
                const SizedBox(height: 10),
                _SettingsSwitchCard(
                  title: '기타 알림',
                  subtitle: '분류되지 않은 일반 알림',
                  value: _preferences.general,
                  onChanged: (value) =>
                      _update(_preferences.copyWith(general: value)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    widget.isMember
                        ? '포어그라운드에서는 채팅만 간단 배너로 보여주고, 나머지는 일반 알림처럼 표시됩니다.'
                        : '앱을 보고 있을 때도 알림이 보이며, 채팅은 간단 배너로 표시됩니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SettingsSwitchCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
