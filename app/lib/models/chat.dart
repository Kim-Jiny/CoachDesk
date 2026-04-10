class ChatRoom {
  final String id;
  final String organizationId;
  final String organizationName;
  final ChatParticipant user;
  final ChatParticipant memberAccount;
  final ChatMessagePreview? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const ChatRoom({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.user,
    required this.memberAccount,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] as String,
      organizationId: json['organizationId'] as String,
      organizationName: json['organizationName'] as String? ?? '',
      user: ChatParticipant.fromJson(json['user'] as Map<String, dynamic>),
      memberAccount: ChatParticipant.fromJson(json['memberAccount'] as Map<String, dynamic>),
      lastMessage: json['lastMessage'] != null
          ? ChatMessagePreview.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'] as String)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }

  ChatRoom copyWith({
    ChatMessagePreview? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    return ChatRoom(
      id: id,
      organizationId: organizationId,
      organizationName: organizationName,
      user: user,
      memberAccount: memberAccount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class ChatParticipant {
  final String id;
  final String name;
  final String? profileImage;

  const ChatParticipant({
    required this.id,
    required this.name,
    this.profileImage,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id'] as String,
      name: json['name'] as String,
      profileImage: json['profileImage'] as String?,
    );
  }
}

class ChatMessage {
  final String id;
  final String chatRoomId;
  final String senderType;
  final String senderId;
  final String content;
  final String messageType;
  final bool isRead;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.chatRoomId,
    required this.senderType,
    required this.senderId,
    required this.content,
    required this.messageType,
    required this.isRead,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      chatRoomId: json['chatRoomId'] as String,
      senderType: json['senderType'] as String,
      senderId: json['senderId'] as String,
      content: json['content'] as String,
      messageType: json['messageType'] as String? ?? 'TEXT',
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class ChatMessagePreview {
  final String content;
  final String senderType;
  final DateTime createdAt;

  const ChatMessagePreview({
    required this.content,
    required this.senderType,
    required this.createdAt,
  });

  factory ChatMessagePreview.fromJson(Map<String, dynamic> json) {
    return ChatMessagePreview(
      content: json['content'] as String,
      senderType: json['senderType'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
