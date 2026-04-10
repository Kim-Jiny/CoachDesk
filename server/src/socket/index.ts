import { Server as HttpServer } from 'http';
import { Server, Socket } from 'socket.io';
import { verifyAccessToken } from '../utils/jwt';
import { prisma } from '../utils/prisma';
import { registerChatHandlers } from './handlers/chat';
import { registerReservationHandlers } from './handlers/reservation';

let io: Server;

export function getIO(): Server {
  if (!io) throw new Error('Socket.IO not initialized');
  return io;
}

export function initializeSocket(httpServer: HttpServer): Server {
  io = new Server(httpServer, {
    cors: {
      origin: '*',
      methods: ['GET', 'POST'],
    },
    pingInterval: 25000,
    pingTimeout: 20000,
  });

  // JWT authentication middleware
  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth.token as string;
      const mode = socket.handshake.auth.mode as string; // 'admin' | 'member'

      if (!token) {
        return next(new Error('Authentication token required'));
      }

      const payload = verifyAccessToken(token);
      const claimedMode = mode === 'member' ? 'member' : 'admin';

      // Validate that the userId actually exists in the claimed table
      if (claimedMode === 'member') {
        const account = await prisma.memberAccount.findUnique({
          where: { id: payload.userId },
          select: { id: true },
        });
        if (!account) return next(new Error('Invalid member account'));
      } else {
        const user = await prisma.user.findUnique({
          where: { id: payload.userId },
          select: { id: true },
        });
        if (!user) return next(new Error('Invalid user account'));
      }

      (socket as any).userId = payload.userId;
      (socket as any).mode = claimedMode;
      next();
    } catch {
      next(new Error('Invalid authentication token'));
    }
  });

  io.on('connection', async (socket: Socket) => {
    const userId = (socket as any).userId as string;
    const mode = (socket as any).mode as string;

    console.log(`Socket connected: ${userId} (${mode})`);

    if (mode === 'member') {
      // Member mode: join member-specific room
      socket.join(`member:${userId}`);
    } else {
      // Admin/Coach mode: join user room + org rooms
      socket.join(`user:${userId}`);

      try {
        const memberships = await prisma.orgMembership.findMany({
          where: { userId },
          select: { organizationId: true },
        });
        for (const m of memberships) {
          socket.join(`org:${m.organizationId}`);
        }
      } catch (err) {
        console.error('Failed to join org rooms:', err);
      }
    }

    // Register event handlers
    registerChatHandlers(socket);
    registerReservationHandlers(socket);

    socket.on('disconnect', () => {
      console.log(`Socket disconnected: ${userId} (${mode})`);
    });
  });

  console.log('Socket.IO initialized');
  return io;
}
