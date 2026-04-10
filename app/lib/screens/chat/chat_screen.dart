import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/socket_service.dart';
import '../../models/chat.dart';
import '../../providers/chat_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String roomId;

  const ChatScreen({super.key, required this.roomId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTyping = false;
  bool _peerTyping = false;
  Timer? _typingTimer;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();

    // Mark this room as active to suppress unread badge increments
    Future.microtask(() {
      ref.read(activeChatRoomIdProvider.notifier).state = widget.roomId;

      final notifier = ref.read(chatMessagesProvider(widget.roomId).notifier);
      notifier.joinRoom();
      notifier.fetchMessages();
      notifier.markRead();
      // Update local badge count (no extra socket emit — markRead above handles it)
      ref.read(chatRoomListProvider.notifier).clearRoomUnread(widget.roomId);
    });

    SocketService.instance.on('chat:typing', _onPeerTyping);
  }

  void _onPeerTyping(dynamic data) {
    if (data is! Map) return;
    if (data['chatRoomId'] != widget.roomId) return;
    if (!mounted) return;
    setState(() => _peerTyping = data['isTyping'] == true);
  }

  @override
  void dispose() {
    // Emit leave directly via socket (don't read the autoDispose provider)
    SocketService.instance.emit('chat:leave', {'chatRoomId': widget.roomId});
    SocketService.instance.off('chat:typing', _onPeerTyping);
    // Clear active room
    ref.read(activeChatRoomIdProvider.notifier).state = null;
    _controller.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _sendMessage() {
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    ref.read(chatMessagesProvider(widget.roomId).notifier).sendMessage(content);
    _controller.clear();
    _onTypingStopped();

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      ref.read(chatMessagesProvider(widget.roomId).notifier).sendTyping(true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _onTypingStopped);
  }

  void _onTypingStopped() {
    if (_isTyping) {
      _isTyping = false;
      ref.read(chatMessagesProvider(widget.roomId).notifier).sendTyping(false);
    }
  }

  void _scrollToBottomIfNear() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll < 200) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatMessagesProvider(widget.roomId));
    final isMember = ApiClient.isMemberMode;

    // Auto-scroll when new messages arrive (only once per new message)
    if (state.messages.length > _lastMessageCount && _lastMessageCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomIfNear();
      });
    }
    _lastMessageCount = state.messages.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('대화'),
      ),
      body: Column(
        children: [
          Expanded(
            child: state.isLoading && state.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.messages.isEmpty
                    ? const Center(
                        child: Text(
                          '대화를 시작하세요',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final message = state.messages[index];
                          final isMe = isMember
                              ? message.senderType == 'MEMBER'
                              : message.senderType == 'USER';

                          final showDate = index == 0 ||
                              !_isSameDay(
                                state.messages[index - 1].createdAt,
                                message.createdAt,
                              );

                          return Column(
                            children: [
                              if (showDate) _DateSeparator(date: message.createdAt),
                              _MessageBubble(
                                message: message,
                                isMe: isMe,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          if (_peerTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Text(
                '상대방이 입력 중...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: _onTextChanged,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: '메시지를 입력하세요',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              textInputAction: TextInputAction.send,
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _sendMessage,
            icon: Icon(
              Icons.send_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _DateSeparator extends StatelessWidget {
  final DateTime date;

  const _DateSeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            DateFormat('yyyy년 M월 d일').format(date),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMe) ...[
            Text(
              DateFormat('HH:mm').format(message.createdAt),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          if (!isMe) ...[
            const SizedBox(width: 4),
            Text(
              DateFormat('HH:mm').format(message.createdAt),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
            ),
          ],
        ],
      ),
    );
  }
}
