import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

final memberNotificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/auth/member/notifications');
  return (response.data as List).cast<Map<String, dynamic>>();
});

class MemberNotificationScreen extends ConsumerWidget {
  const MemberNotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(memberNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          TextButton(
            onPressed: () async {
              final dio = ref.read(dioProvider);
              await dio.patch('/auth/member/notifications/read-all');
              ref.invalidate(memberNotificationsProvider);
            },
            child: const Text('전체 읽음'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(memberNotificationsProvider);
          await ref.read(memberNotificationsProvider.future);
        },
        child: notifications.when(
          loading: () =>
              const ShimmerLoading(style: ShimmerStyle.list, itemCount: 8),
          error: (_, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 140),
              EmptyState(
                icon: Icons.notifications_off_outlined,
                message: '알림을 불러올 수 없습니다',
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 140),
                  EmptyState(
                    icon: Icons.notifications_none_rounded,
                    message: '새 알림이 없습니다',
                  ),
                ],
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isRead = item['isRead'] as bool? ?? false;
                final createdAt = DateTime.tryParse(
                  item['createdAt'] as String? ?? '',
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      if (!isRead) {
                        final dio = ref.read(dioProvider);
                        await dio.patch(
                          '/auth/member/notifications/${item['id']}/read',
                        );
                        ref.invalidate(memberNotificationsProvider);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isRead
                            ? Colors.white
                            : AppTheme.primaryColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppTheme.softShadow,
                        border: Border.all(
                          color: isRead
                              ? Colors.transparent
                              : AppTheme.primaryColor
                                  .withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isRead
                                  ? Colors.grey.shade100
                                  : AppTheme.primaryColor
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _iconForType(item['type'] as String?),
                              color: isRead
                                  ? Colors.grey.shade500
                                  : AppTheme.primaryColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item['title'] as String? ?? '알림',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isRead
                                              ? Colors.black87
                                              : AppTheme.primaryColor,
                                        ),
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primaryColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item['body'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                    height: 1.4,
                                  ),
                                ),
                                if (createdAt != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    DateFormat('M월 d일 HH:mm', 'ko')
                                        .format(createdAt.toLocal()),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static IconData _iconForType(String? type) {
    return switch (type) {
      'NEW_RESERVATION' => Icons.event_available_rounded,
      'RESERVATION_STATUS_UPDATED' => Icons.event_note_rounded,
      'RESERVATION_CANCELLED' => Icons.event_busy_rounded,
      'RESERVATION_DELAYED' => Icons.schedule_rounded,
      'PACKAGE_PAUSE_APPROVED' => Icons.pause_circle_outline,
      'PACKAGE_PAUSE_REJECTED' => Icons.cancel_outlined,
      _ => Icons.notifications_rounded,
    };
  }
}
