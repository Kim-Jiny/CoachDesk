import { getIO } from './index';
import { sendPush } from '../utils/firebase';

// ─── Reservation Events ─────────────────────────────────

export async function emitReservationCreated(
  orgId: string,
  reservation: any,
  memberAccountId?: string | null,
) {
  const io = getIO();

  // Notify coaches in the org
  io.in(`org:${orgId}`).emit('reservation:created', reservation);

  // Notify member if linked
  if (memberAccountId) {
    io.in(`member:${memberAccountId}`).emit('reservation:created', reservation);
  }
}

export async function emitReservationUpdated(
  orgId: string,
  reservation: any,
  memberAccountId?: string | null,
) {
  const io = getIO();

  io.in(`org:${orgId}`).emit('reservation:updated', reservation);

  if (memberAccountId) {
    io.in(`member:${memberAccountId}`).emit('reservation:updated', reservation);
  }
}

export async function emitReservationCancelled(
  orgId: string,
  reservation: any,
  userId?: string | null,
  memberAccountId?: string | null,
) {
  const io = getIO();

  io.in(`org:${orgId}`).emit('reservation:cancelled', reservation);

  if (userId) {
    io.in(`user:${userId}`).emit('reservation:cancelled', reservation);
  }

  if (memberAccountId) {
    io.in(`member:${memberAccountId}`).emit('reservation:cancelled', reservation);
  }
}

// ─── Chat Events ────────────────────────────────────────

export async function emitNewMessage(
  chatRoomId: string,
  message: any,
  targetRoomIds: string[],
) {
  const io = getIO();

  // Emit to the chat room (for users currently viewing)
  io.in(`chat:${chatRoomId}`).emit('chat:message', message);

  // Also send notification to target rooms (for badge updates etc.)
  for (const roomId of targetRoomIds) {
    io.in(roomId).emit('chat:notification', {
      chatRoomId,
      message,
    });
  }
}

export async function emitMessageRead(chatRoomId: string, readBy: string) {
  const io = getIO();
  io.in(`chat:${chatRoomId}`).emit('chat:read', { chatRoomId, readBy });
}

// ─── Online Check + FCM Fallback ────────────────────────

export async function sendPushIfOffline(
  room: string,
  fcmToken: string | null | undefined,
  title: string,
  body: string,
  data?: Record<string, string>,
) {
  if (!fcmToken) return;

  const io = getIO();
  const sockets = await io.in(room).fetchSockets();

  // If user is online via socket, skip push
  if (sockets.length > 0) return;

  sendPush(fcmToken, title, body, data);
}
