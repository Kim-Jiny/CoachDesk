import { Socket } from 'socket.io';
import { prisma } from '../../utils/prisma';
import { emitNewMessage, emitMessageRead, sendPushIfOffline } from '../emitters';

async function verifyRoomAccess(chatRoomId: string, userId: string, mode: string): Promise<boolean> {
  const room = await prisma.chatRoom.findUnique({
    where: { id: chatRoomId },
    select: { userId: true, memberAccountId: true },
  });
  if (!room) return false;
  return mode === 'member' ? room.memberAccountId === userId : room.userId === userId;
}

export function registerChatHandlers(socket: Socket) {
  const userId = (socket as any).userId as string;
  const mode = (socket as any).mode as string;

  // ─── Join Chat Room ─────────────────────────────────────
  socket.on('chat:join', async (data: { chatRoomId: string }) => {
    if (!data.chatRoomId) return;
    const hasAccess = await verifyRoomAccess(data.chatRoomId, userId, mode);
    if (!hasAccess) {
      socket.emit('chat:error', { error: 'Access denied to chat room' });
      return;
    }
    socket.join(`chat:${data.chatRoomId}`);
  });

  // ─── Leave Chat Room ────────────────────────────────────
  socket.on('chat:leave', (data: { chatRoomId: string }) => {
    if (!data.chatRoomId) return;
    socket.leave(`chat:${data.chatRoomId}`);
  });

  // ─── Send Message ───────────────────────────────────────
  socket.on('chat:send', async (data: {
    chatRoomId: string;
    content: string;
    messageType?: string;
  }) => {
    try {
      if (!data.chatRoomId || !data.content) {
        socket.emit('chat:error', { error: 'chatRoomId and content are required' });
        return;
      }

      const senderType = mode === 'member' ? 'MEMBER' : 'USER';

      // Verify room access + get room info in a single query
        const chatRoom = await prisma.chatRoom.findUnique({
        where: { id: data.chatRoomId },
        select: {
          userId: true,
          memberAccountId: true,
          user: {
            select: { fcmToken: true, name: true, notificationPreferences: true },
          },
          memberAccount: {
            select: { fcmToken: true, name: true, notificationPreferences: true },
          },
        },
      });

      if (!chatRoom) {
        socket.emit('chat:error', { error: 'Chat room not found' });
        return;
      }

      // Verify the sender has access to this room
      const hasAccess = mode === 'member'
        ? chatRoom.memberAccountId === userId
        : chatRoom.userId === userId;

      if (!hasAccess) {
        socket.emit('chat:error', { error: 'Access denied to chat room' });
        return;
      }

      // Validate messageType
      const validMessageTypes = ['TEXT', 'IMAGE', 'SYSTEM'];
      const messageType = validMessageTypes.includes(data.messageType ?? '')
        ? data.messageType!
        : 'TEXT';

      // Create message + update lastMessageAt in a transaction
      const message = await prisma.$transaction(async (tx) => {
        const msg = await tx.chatMessage.create({
          data: {
            chatRoomId: data.chatRoomId,
            senderType,
            senderId: userId,
            content: data.content,
            messageType: messageType as any,
          },
        });

        await tx.chatRoom.update({
          where: { id: data.chatRoomId },
          data: { lastMessageAt: new Date() },
        });

        return msg;
      });

      // Serialize Date to ISO string for socket emission
      const serializedMessage = {
        ...message,
        createdAt: message.createdAt.toISOString(),
      };

      const targetRoomIds: string[] = [];
      if (senderType === 'USER') {
        // Coach sent → notify member
        targetRoomIds.push(`member:${chatRoom.memberAccountId}`);
        sendPushIfOffline(
          `member:${chatRoom.memberAccountId}`,
          chatRoom.memberAccount?.fcmToken,
          chatRoom.memberAccount?.notificationPreferences,
          chatRoom.user?.name ?? '코치',
          data.content,
          { type: 'CHAT_MESSAGE', chatRoomId: data.chatRoomId },
        );
      } else {
        // Member sent → notify coach
        targetRoomIds.push(`user:${chatRoom.userId}`);
        sendPushIfOffline(
          `user:${chatRoom.userId}`,
          chatRoom.user?.fcmToken,
          chatRoom.user?.notificationPreferences,
          chatRoom.memberAccount?.name ?? '회원',
          data.content,
          { type: 'CHAT_MESSAGE', chatRoomId: data.chatRoomId },
        );
      }

      emitNewMessage(
        data.chatRoomId,
        serializedMessage,
        targetRoomIds,
        senderType === 'USER'
            ? chatRoom.user?.name ?? '코치'
            : chatRoom.memberAccount?.name ?? '회원',
      );
    } catch (err) {
      console.error('chat:send error:', err);
      socket.emit('chat:error', { error: 'Failed to send message' });
    }
  });

  // ─── Mark Read ──────────────────────────────────────────
  socket.on('chat:markRead', async (data: { chatRoomId: string }) => {
    try {
      if (!data.chatRoomId) return;

      const hasAccess = await verifyRoomAccess(data.chatRoomId, userId, mode);
      if (!hasAccess) return;

      // Mark messages from the OTHER side as read
      const senderType = mode === 'member' ? 'USER' : 'MEMBER';

      await prisma.chatMessage.updateMany({
        where: {
          chatRoomId: data.chatRoomId,
          senderType,
          isRead: false,
        },
        data: { isRead: true },
      });

      emitMessageRead(data.chatRoomId, userId);
    } catch (err) {
      console.error('chat:markRead error:', err);
    }
  });

  // ─── Typing Indicator ──────────────────────────────────
  socket.on('chat:typing', (data: { chatRoomId: string; isTyping: boolean }) => {
    if (!data.chatRoomId) return;
    socket.to(`chat:${data.chatRoomId}`).emit('chat:typing', {
      chatRoomId: data.chatRoomId,
      userId,
      isTyping: data.isTyping,
    });
  });
}
