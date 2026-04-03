import crypto from 'crypto';
import jwt, { JwtHeader } from 'jsonwebtoken';
import { env } from '../config/env';

type AppleJwk = {
  kty: string;
  kid: string;
  use: string;
  alg: string;
  n: string;
  e: string;
};

type AppleJwksResponse = {
  keys: AppleJwk[];
};

type AppleIdentityTokenPayload = {
  iss: string;
  aud: string;
  exp: number;
  iat: number;
  sub: string;
  email?: string;
  email_verified?: boolean | string;
};

const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';
const APPLE_KEYS_TTL_MS = 60 * 60 * 1000;

let cachedKeys: AppleJwk[] = [];
let cachedAt = 0;

async function fetchAppleKeys(): Promise<AppleJwk[]> {
  const now = Date.now();
  if (cachedKeys.length > 0 && now - cachedAt < APPLE_KEYS_TTL_MS) {
    return cachedKeys;
  }

  const response = await fetch(APPLE_KEYS_URL);
  if (!response.ok) {
    throw new Error(`Failed to fetch Apple public keys: ${response.status}`);
  }

  const body = await response.json() as AppleJwksResponse;
  cachedKeys = body.keys;
  cachedAt = now;
  return cachedKeys;
}

export async function verifyAppleIdentityToken(identityToken: string): Promise<AppleIdentityTokenPayload> {
  const decoded = jwt.decode(identityToken, { complete: true });
  if (!decoded || typeof decoded === 'string') {
    throw new Error('Invalid Apple token');
  }

  const header = decoded.header as JwtHeader;
  if (header.alg !== 'RS256' || !header.kid) {
    throw new Error('Invalid Apple token header');
  }

  const keys = await fetchAppleKeys();
  const jwk = keys.find((key) => key.kid === header.kid && key.alg === 'RS256');
  if (!jwk) {
    throw new Error('Apple public key not found');
  }

  const publicKey = crypto.createPublicKey({
    key: jwk,
    format: 'jwk',
  });

  const payload = jwt.verify(identityToken, publicKey, {
    algorithms: ['RS256'],
    issuer: 'https://appleid.apple.com',
    audience: env.APPLE_AUDIENCES.length === 1
      ? env.APPLE_AUDIENCES[0]
      : env.APPLE_AUDIENCES as [string, ...string[]],
  }) as AppleIdentityTokenPayload;

  if (!payload.sub) {
    throw new Error('Invalid Apple token payload');
  }

  return payload;
}
