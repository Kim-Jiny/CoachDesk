import { randomUUID } from 'crypto';
import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/prisma';
import { authMiddleware } from '../middleware/auth';
import { uploadFile } from '../utils/storage';

const router = Router();
router.use(authMiddleware);

// ─── Get Chat Rooms ─────────────────────────────────────
router.get('/rooms', async (req: Request, res: Response) => {
  try {
    const userId = req.user!.userId;
    const mode = req.query.mode as string; // 'admin' | 'member'

    let where: any;
    if (mode === 'member') {
      where = { memberAccountId: userId };
    } else {
      where = { userId };
    }

    const rooms = await prisma.chatRoom.findMany({
      where,
      include: {
        user: { select: { id: true, name: true, profileImage: true } },
        memberAccount: { select: { id: true, name: true } },
        organization: { select: { id: true, name: true } },
        messages: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          select: { content: true, createdAt: true, senderType: true, messageType: true },
        },
      },
      orderBy: { lastMessageAt: 'desc' },
    });

    // Count unread messages for each room
    const roomsWithUnread = await Promise.all(
      rooms.map(async (room) => {
        const senderType = mode === 'member' ? 'USER' : 'MEMBER';
        const unreadCount = await prisma.chatMessage.count({
          where: {
            chatRoomId: room.id,
            senderType,
            isRead: false,
          },
        });

        return {
          id: room.id,
          organizationId: room.organizationId,
          organizationName: room.organization.name,
          user: room.user,
          memberAccount: { id: room.memberAccount.id, name: room.memberAccount.name },
          lastMessage: room.messages[0] ?? null,
          lastMessageAt: room.lastMessageAt,
          unreadCount,
        };
      }),
    );

    res.json(roomsWithUnread);
  } catch (err) {
    console.error('Get chat rooms error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Create or Get Chat Room (upsert) ───────────────────
const createRoomSchema = z.object({
  organizationId: z.string().uuid(),
  userId: z.string().uuid(),
  memberAccountId: z.string().uuid(),
});

router.post('/rooms', async (req: Request, res: Response) => {
  try {
    const body = createRoomSchema.parse(req.body);
    const callerId = req.user!.userId;

    // Verify the caller is one of the participants
    if (callerId !== body.userId && callerId !== body.memberAccountId) {
      res.status(403).json({ error: 'You must be a participant in the chat room' });
      return;
    }

    const [membership, member] = await Promise.all([
      prisma.orgMembership.findUnique({
        where: {
          userId_organizationId: {
            userId: body.userId,
            organizationId: body.organizationId,
          },
        },
        select: { id: true },
      }),
      prisma.member.findFirst({
        where: {
          organizationId: body.organizationId,
          memberAccountId: body.memberAccountId,
          status: 'ACTIVE',
        },
        select: { id: true },
      }),
    ]);

    if (!membership) {
      res.status(403).json({ error: 'User is not part of this organization' });
      return;
    }

    if (!member) {
      res.status(403).json({ error: 'Member account is not active in this organization' });
      return;
    }

    const room = await prisma.chatRoom.upsert({
      where: {
        organizationId_userId_memberAccountId: {
          organizationId: body.organizationId,
          userId: body.userId,
          memberAccountId: body.memberAccountId,
        },
      },
      create: {
        organizationId: body.organizationId,
        userId: body.userId,
        memberAccountId: body.memberAccountId,
      },
      update: {},
      include: {
        user: { select: { id: true, name: true, profileImage: true } },
        memberAccount: { select: { id: true, name: true } },
        organization: { select: { id: true, name: true } },
      },
    });

    res.json({
      id: room.id,
      organizationId: room.organizationId,
      organizationName: room.organization.name,
      user: room.user,
      memberAccount: { id: room.memberAccount.id, name: room.memberAccount.name },
      lastMessageAt: room.lastMessageAt,
    });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Create chat room error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Get Messages (cursor pagination) ───────────────────
router.get('/rooms/:roomId/messages', async (req: Request, res: Response) => {
  try {
    const userId = req.user!.userId;
    const roomId = req.params.roomId as string;

    // Verify the user has access to this room
    const room = await prisma.chatRoom.findUnique({
      where: { id: roomId },
      select: { userId: true, memberAccountId: true },
    });
    if (!room || (room.userId !== userId && room.memberAccountId !== userId)) {
      res.status(403).json({ error: 'Access denied' });
      return;
    }

    const cursor = req.query.cursor as string | undefined;
    const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);

    const where: any = { chatRoomId: roomId };
    if (cursor) {
      where.createdAt = { lt: new Date(cursor) };
    }

    const messages = await prisma.chatMessage.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const nextCursor = messages.length === limit
      ? messages[messages.length - 1].createdAt.toISOString()
      : null;

    res.json({
      messages: messages.reverse(),
      nextCursor,
    });
  } catch (err) {
    console.error('Get messages error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Upload Chat Image (인증샷 등) ───────────────────────
const uploadChatImageSchema = z.object({
  fileName: z.string().min(1).max(255),
  contentType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  base64Data: z.string().min(1),
});

router.post('/rooms/:roomId/upload-image', async (req: Request, res: Response) => {
  try {
    const userId = req.user!.userId;
    const roomId = req.params.roomId as string;

    const room = await prisma.chatRoom.findUnique({
      where: { id: roomId },
      select: { userId: true, memberAccountId: true },
    });
    if (!room || (room.userId !== userId && room.memberAccountId !== userId)) {
      res.status(403).json({ error: 'Access denied' });
      return;
    }

    const body = uploadChatImageSchema.parse(req.body);
    const buffer = Buffer.from(body.base64Data, 'base64');
    if (buffer.length === 0) {
      res.status(400).json({ error: 'Image data required' });
      return;
    }
    if (buffer.length > 6 * 1024 * 1024) {
      res.status(400).json({ error: '이미지는 6MB 이하만 업로드할 수 있습니다' });
      return;
    }

    const safeName = body.fileName.replace(/[^a-zA-Z0-9._-]/g, '_');
    const ext = safeName.includes('.') ? safeName.split('.').pop() : 'jpg';
    const objectName = `chat/${roomId}/${randomUUID()}.${ext}`;
    const imageUrl = await uploadFile(objectName, buffer, body.contentType);

    res.json({ imageUrl });
  } catch (err) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation error', details: err.errors });
      return;
    }
    console.error('Upload chat image error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ─── Unread Count ───────────────────────────────────────
router.get('/unread-count', async (req: Request, res: Response) => {
  try {
    const userId = req.user!.userId;
    const mode = req.query.mode as string;

    let roomWhere: any;
    let senderType: string;

    if (mode === 'member') {
      roomWhere = { memberAccountId: userId };
      senderType = 'USER';
    } else {
      roomWhere = { userId };
      senderType = 'MEMBER';
    }

    const rooms = await prisma.chatRoom.findMany({
      where: roomWhere,
      select: { id: true },
    });

    if (rooms.length === 0) {
      res.json({ unreadCount: 0 });
      return;
    }

    const count = await prisma.chatMessage.count({
      where: {
        chatRoomId: { in: rooms.map((r) => r.id) },
        senderType: senderType as any,
        isRead: false,
      },
    });

    res.json({ unreadCount: count });
  } catch (err) {
    console.error('Unread count error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
