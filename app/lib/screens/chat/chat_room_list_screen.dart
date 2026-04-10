import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../models/chat.dart';
import '../../providers/chat_provider.dart';

class ChatRoomListScreen extends ConsumerStatefulWidget {
  const ChatRoomListScreen({super.key});

  @override
  ConsumerState<ChatRoomListScreen> createState() => _ChatRoomListScreenState();
}

class _ChatRoomListScreenState extends ConsumerState<ChatRoomListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(chatRoomListProvider.notifier).fetchRooms();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatRoomListProvider);
    final isMember = ApiClient.isMemberMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('채팅'),
      ),
      body: state.isLoading && state.rooms.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.rooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.error!,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref.read(chatRoomListProvider.notifier).fetchRooms(),
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : state.rooms.isEmpty
                  ? const Center(
                      child: Text(
                        '채팅방이 없습니다',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    )
              : RefreshIndicator(
                  onRefresh: () => ref.read(chatRoomListProvider.notifier).fetchRooms(),
                  child: ListView.builder(
                    itemCount: state.rooms.length,
                    itemBuilder: (context, index) {
                      final room = state.rooms[index];
                      final basePath = isMember ? '/member/chat' : '/chat';
                      return _ChatRoomTile(
                        room: room,
                        isMember: isMember,
                        onTap: () => context.push('$basePath/${room.id}'),
                      );
                    },
                  ),
                ),
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  final ChatRoom room;
  final bool isMember;
  final VoidCallback onTap;

  const _ChatRoomTile({
    required this.room,
    required this.isMember,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = isMember ? room.user.name : room.memberAccount.name;
    final subtitle = room.lastMessage?.content ?? '새 대화를 시작하세요';
    final timeStr = room.lastMessageAt != null
        ? _formatTime(room.lastMessageAt!)
        : '';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          displayName.isNotEmpty ? displayName[0] : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeStr.isNotEmpty)
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: room.unreadCount > 0 ? Colors.black87 : Colors.grey.shade600,
                fontWeight: room.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          if (room.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                room.unreadCount > 99 ? '99+' : '${room.unreadCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays == 0) {
      return DateFormat('HH:mm').format(time);
    } else if (diff.inDays == 1) {
      return '어제';
    } else if (diff.inDays < 7) {
      const days = ['일', '월', '화', '수', '목', '금', '토'];
      return days[time.weekday % 7];
    } else {
      return DateFormat('M/d').format(time);
    }
  }
}
