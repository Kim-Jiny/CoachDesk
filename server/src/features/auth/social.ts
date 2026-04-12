import bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import { z } from 'zod';
import { prisma } from '../../utils/prisma';
import { verifyAppleIdentityToken } from '../../utils/apple-auth';
import { env } from '../../config/env';
import { toMemberAccountPayload, toMemberLinks, toOrganizationPayload, toUserPayload } from './payloads';

export const socialLoginSchema = z.object({
  idToken: z.string().min(1),
  provider: z.enum(['google', 'apple']),
  name: z.string().nullish().transform((value) => value || undefined),
});

const googleClient = new OAuth2Client();
const googleAudiences = [
  env.GOOGLE_CLIENT_ID,
  env.GOOGLE_ANDROID_CLIENT_ID,
  env.GOOGLE_IOS_CLIENT_ID,
].filter(Boolean);

function buildAppleFallbackEmail(sub: string): string {
  const normalizedSub = sub.toLowerCase().replace(/[^a-z0-9._-]/g, '');
  return `apple-${normalizedSub}@users.coachdesk.local`;
}

async function resolveSocialIdentity(body: z.infer<typeof socialLoginSchema>) {
  let email: string;
  let socialId: string;
  let displayName: string | undefined = body.name;

  if (body.provider === 'google') {
    const ticket = await googleClient.verifyIdToken({
      idToken: body.idToken,
      audience: googleAudiences,
    });
    const payload = ticket.getPayload();
    if (!payload || !payload.email) {
      throw new Error('Invalid Google token');
    }
    email = payload.email;
    socialId = payload.sub;
    displayName = displayName || payload.name || email.split('@')[0];
  } else {
    const payload = await verifyAppleIdentityToken(body.idToken);
    socialId = payload.sub;
    email = payload.email ?? buildAppleFallbackEmail(payload.sub);
    displayName = displayName || payload.email?.split('@')[0];
  }

  return {
    email,
    socialId,
    displayName,
    socialField: body.provider === 'google' ? 'googleId' : 'appleId',
  };
}

export function handleSocialLoginError(res: any, label: string, err: unknown) {
  if (err instanceof z.ZodError) {
    res.status(400).json({ error: 'Validation error', details: err.errors });
    return;
  }

  if (err instanceof Error) {
    console.error(label, err);
    const message = err.message;
    if (
      /apple|jwt|token|audience|issuer|public key|signature|invalid|timed out|failed to reach/i.test(message)
    ) {
      res.status(400).json({ error: message });
      return;
    }
    if (/unique constraint|duplicate key/i.test(message)) {
      res.status(409).json({ error: '이미 연결된 계정입니다' });
      return;
    }
    if (env.NODE_ENV !== 'production') {
      res.status(500).json({ error: message });
      return;
    }
  } else {
    console.error(label, err);
  }

  res.status(500).json({ error: 'Internal server error' });
}

export async function socialLoginUser(params: {
  body: z.infer<typeof socialLoginSchema>;
  generateAccessToken: (payload: { userId: string; email: string }) => string;
  generateRefreshToken: (payload: { userId: string; email: string }) => string;
}) {
  const { email, socialId, displayName, socialField } = await resolveSocialIdentity(params.body);

  let user = await prisma.user.findFirst({
    where: email
      ? { OR: [{ [socialField]: socialId }, { email }] }
      : { [socialField]: socialId },
    include: { memberships: { include: { organization: true }, orderBy: { createdAt: 'asc' } } },
  });

  if (user) {
    if (!(user as any)[socialField]) {
      user = await prisma.user.update({
        where: { id: user.id },
        data: { [socialField]: socialId },
        include: { memberships: { include: { organization: true }, orderBy: { createdAt: 'asc' } } },
      });
    }
  } else {
    const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();
    const result = await prisma.$transaction(async (tx) => {
      const newUser = await tx.user.create({
        data: {
          email,
          password: await bcrypt.hash(Math.random().toString(36), 12),
          name: displayName || email.split('@')[0],
          [socialField]: socialId,
        },
      });
      const org = await tx.organization.create({
        data: { name: `${displayName || email.split('@')[0]}'s Studio`, inviteCode },
      });
      await tx.orgMembership.create({
        data: { userId: newUser.id, organizationId: org.id, role: 'OWNER' },
      });
      return { user: newUser, org };
    });

    user = (await prisma.user.findUnique({
      where: { id: result.user.id },
      include: { memberships: { include: { organization: true }, orderBy: { createdAt: 'asc' } } },
    })) as any;
  }

  const tokenPayload = { userId: user!.id, email: user!.email };
  return {
    accessToken: params.generateAccessToken(tokenPayload),
    refreshToken: params.generateRefreshToken(tokenPayload),
    user: toUserPayload(user!),
    organization: toOrganizationPayload(user!),
  };
}

export async function socialLoginMemberAccount(params: {
  body: z.infer<typeof socialLoginSchema>;
  generateAccessToken: (payload: { userId: string; email: string }) => string;
  generateRefreshToken: (payload: { userId: string; email: string }) => string;
}) {
  const { email, socialId, displayName, socialField } = await resolveSocialIdentity(params.body);

  let account = await prisma.memberAccount.findFirst({
    where: email
      ? { OR: [{ [socialField]: socialId }, { email }] }
      : { [socialField]: socialId },
    include: { members: true },
  });

  if (account) {
    if (!(account as any)[socialField]) {
      account = await prisma.memberAccount.update({
        where: { id: account.id },
        data: { [socialField]: socialId },
        include: { members: true },
      });
    }
  } else {
    account = await prisma.memberAccount.create({
      data: {
        email,
        password: await bcrypt.hash(Math.random().toString(36), 12),
        name: displayName || email.split('@')[0],
        [socialField]: socialId,
      },
      include: { members: true },
    });
  }

  const tokenPayload = { userId: account.id, email: account.email };
  return {
    accessToken: params.generateAccessToken(tokenPayload),
    refreshToken: params.generateRefreshToken(tokenPayload),
    memberAccount: toMemberAccountPayload(account),
    members: toMemberLinks(account.members),
  };
}
