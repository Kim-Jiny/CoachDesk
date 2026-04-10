import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/api_client.dart';
import '../core/socket_service.dart';
import '../models/chat.dart';

// ─── Chat Room List ─────────────────────────────────────

class ChatRoomListState {
  final List<ChatRoom> rooms;
  final bool isLoading;
  final String? error;

  const ChatRoomListState({
    this.rooms = const [],
    this.isLoading = false,
    this.error,
  });

  ChatRoomListState copyWith({
    List<ChatRoom>? rooms,
    bool? isLoading,
    String? error,
  }) {
    return ChatRoomListState(
      rooms: rooms ?? this.rooms,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// The roomId currently being viewed by the user (null if not in any chat).
final activeChatRoomIdProvider = StateProvider<String?>((ref) => null);

class ChatRoomListNotifier extends Notifier<ChatRoomListState> {
  @override
  ChatRoomListState build() {
    _setupSocketListener();
    return const ChatRoomListState();
  }

  Dio get _dio => ref.read(dioProvider);

  void _setupSocketListener() {
    final socket = SocketService.instance;

    void registerListeners() {
      socket.on('chat:notification', _onChatNotification);
    }

    // Register now (if connected) AND on every future connect
    registerListeners();
    socket.addConnectCallback(registerListeners);

    ref.onDispose(() {
      socket.off('chat:notification', _onChatNotification);
      socket.removeConnectCallback(registerListeners);
    });
  }

  void _onChatNotification(dynamic data) {
    if (data is! Map) return;
    final chatRoomId = data['chatRoomId'] as String?;
    if (chatRoomId == null) return;

    final messageData = data['message'] as Map<String, dynamic>?;
    if (messageData == null) return;

    // Don't increment unread if this room is currently being viewed
    final activeRoomId = ref.read(activeChatRoomIdProvider);
    final isActiveRoom = activeRoomId == chatRoomId;

    final rooms = [...state.rooms];
    final index = rooms.indexWhere((r) => r.id == chatRoomId);

    if (index >= 0) {
      final room = rooms[index];
      rooms[index] = room.copyWith(
        lastMessage: ChatMessagePreview(
          content: messageData['content'] as String? ?? '',
          senderType: messageData['senderType'] as String? ?? '',
          createdAt: DateTime.tryParse(messageData['createdAt'] as String? ?? '') ?? DateTime.now(),
        ),
        lastMessageAt: DateTime.now(),
        unreadCount: isActiveRoom ? 0 : room.unreadCount + 1,
      );
      // Move to top
      final updated = rooms.removeAt(index);
      rooms.insert(0, updated);
      state = state.copyWith(rooms: rooms);
    } else {
      // New room — refetch
      fetchRooms();
    }
  }

  Future<void> fetchRooms() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final mode = ApiClient.isMemberMode ? 'member' : 'admin';
      final response = await _dio.get('/chat/rooms', queryParameters: {'mode': mode});
      final rooms = (response.data as List)
          .map((json) => ChatRoom.fromJson(json as Map<String, dynamic>))
          .toList();
      state = state.copyWith(rooms: rooms, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data?['error'] as String? ?? 'Failed to load chat rooms',
      );
    }
  }

  Future<ChatRoom?> getOrCreateRoom({
    required String organizationId,
    required String userId,
    required String memberAccountId,
  }) async {
    try {
      final response = await _dio.post('/chat/rooms', data: {
        'organizationId': organizationId,
        'userId': userId,
        'memberAccountId': memberAccountId,
      });
      return ChatRoom.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Marks room as read: clears local badge AND emits socket event.
  void markRoomRead(String roomId) {
    clearRoomUnread(roomId);
    SocketService.instance.emit('chat:markRead', {'chatRoomId': roomId});
  }

  /// Clears local unread badge only (no socket emit).
  /// Use when another component already emits the socket event.
  void clearRoomUnread(String roomId) {
    final rooms = [...state.rooms];
    final index = rooms.indexWhere((r) => r.id == roomId);
    if (index >= 0) {
      rooms[index] = rooms[index].copyWith(unreadCount: 0);
      state = state.copyWith(rooms: rooms);
    }
  }

  /// Total unread count across all rooms.
  int get totalUnreadCount =>
      state.rooms.fold(0, (sum, room) => sum + room.unreadCount);
}

final chatRoomListProvider =
    NotifierProvider<ChatRoomListNotifier, ChatRoomListState>(ChatRoomListNotifier.new);

// ─── Chat Messages ──────────────────────────────────────

class ChatMessagesState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? nextCursor;

  const ChatMessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.nextCursor,
  });

  ChatMessagesState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    Object? nextCursor = _sentinel,
  }) {
    return ChatMessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      nextCursor: nextCursor == _sentinel ? this.nextCursor : nextCursor as String?,
    );
  }
}

const _sentinel = Object();

class ChatMessagesNotifier extends StateNotifier<ChatMessagesState> {
  final String roomId;
  final Dio _dio;
  late final void Function() _connectCallback;

  ChatMessagesNotifier(this.roomId, this._dio) : super(const ChatMessagesState()) {
    _connectCallback = _registerListeners;
    _registerListeners();
    SocketService.instance.addConnectCallback(_connectCallback);
  }

  void _registerListeners() {
    final socket = SocketService.instance;
    socket.on('chat:message', _onMessage);
    socket.on('chat:read', _onRead);
  }

  @override
  void dispose() {
    SocketService.instance.off('chat:message', _onMessage);
    SocketService.instance.off('chat:read', _onRead);
    SocketService.instance.removeConnectCallback(_connectCallback);
    super.dispose();
  }

  void _onMessage(dynamic data) {
    if (data is! Map) return;
    final msg = ChatMessage.fromJson(Map<String, dynamic>.from(data));
    if (msg.chatRoomId != roomId) return;

    // Avoid duplicates
    if (state.messages.any((m) => m.id == msg.id)) return;

    state = state.copyWith(
      messages: [...state.messages, msg],
    );
  }

  void _onRead(dynamic data) {
    if (data is! Map) return;
    if (data['chatRoomId'] != roomId) return;

    state = state.copyWith(
      messages: state.messages
          .map((m) => ChatMessage(
                id: m.id,
                chatRoomId: m.chatRoomId,
                senderType: m.senderType,
                senderId: m.senderId,
                content: m.content,
                messageType: m.messageType,
                isRead: true,
                createdAt: m.createdAt,
              ))
          .toList(),
    );
  }

  Future<void> fetchMessages({bool loadMore = false}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final params = <String, dynamic>{'limit': 50};
      if (loadMore && state.nextCursor != null) {
        params['cursor'] = state.nextCursor;
      }

      final response = await _dio.get('/chat/rooms/$roomId/messages', queryParameters: params);
      final data = response.data as Map<String, dynamic>;
      final messages = (data['messages'] as List)
          .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        messages: loadMore ? [...messages, ...state.messages] : messages,
        isLoading: false,
        nextCursor: data['nextCursor'] as String?,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  void sendMessage(String content) {
    SocketService.instance.emit('chat:send', {
      'chatRoomId': roomId,
      'content': content,
    });
  }

  void markRead() {
    SocketService.instance.emit('chat:markRead', {'chatRoomId': roomId});
  }

  void joinRoom() {
    SocketService.instance.emit('chat:join', {'chatRoomId': roomId});
  }

  void leaveRoom() {
    SocketService.instance.emit('chat:leave', {'chatRoomId': roomId});
  }

  void sendTyping(bool isTyping) {
    SocketService.instance.emit('chat:typing', {
      'chatRoomId': roomId,
      'isTyping': isTyping,
    });
  }
}

final chatMessagesProvider = StateNotifierProvider.autoDispose
    .family<ChatMessagesNotifier, ChatMessagesState, String>(
  (ref, roomId) => ChatMessagesNotifier(roomId, ref.read(dioProvider)),
);

// ─── Unread Count (computed from room list) ─────────────

final chatUnreadCountProvider = Provider<int>((ref) {
  final state = ref.watch(chatRoomListProvider);
  return state.rooms.fold(0, (sum, room) => sum + room.unreadCount);
});
