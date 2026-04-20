import dotenv from 'dotenv';
dotenv.config();

function getRequiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function getOptionalEnv(name: string, fallback: string): string {
  return process.env[name]?.trim() || fallback;
}

const nodeEnv = getOptionalEnv('NODE_ENV', 'development');
const jwtSecret = getOptionalEnv('JWT_SECRET', 'dev-secret');
const jwtRefreshSecret = getOptionalEnv('JWT_REFRESH_SECRET', 'dev-refresh-secret');

if (nodeEnv === 'production') {
  if (jwtSecret === 'dev-secret') {
    throw new Error('JWT_SECRET must be set in production');
  }
  if (jwtRefreshSecret === 'dev-refresh-secret') {
    throw new Error('JWT_REFRESH_SECRET must be set in production');
  }
}

export const env = {
  PORT: parseInt(getOptionalEnv('PORT', '3010'), 10),
  NODE_ENV: nodeEnv,
  DATABASE_URL: getRequiredEnv('DATABASE_URL'),
  JWT_SECRET: jwtSecret,
  JWT_REFRESH_SECRET: jwtRefreshSecret,
  MINIO_ENDPOINT: getOptionalEnv('MINIO_ENDPOINT', 'http://localhost:9000'),
  MINIO_ACCESS_KEY: getOptionalEnv('MINIO_ACCESS_KEY', 'minioadmin'),
  MINIO_SECRET_KEY: getOptionalEnv('MINIO_SECRET_KEY', 'minioadmin'),
  MINIO_BUCKET: getOptionalEnv('MINIO_BUCKET', 'coachdesk'),
  STORAGE_PUBLIC_URL: getOptionalEnv('STORAGE_PUBLIC_URL', 'http://localhost:9000/coachdesk'),
  FIREBASE_SERVICE_ACCOUNT:
    process.env.FIREBASE_SERVICE_ACCOUNT || process.env.GOOGLE_APPLICATION_CREDENTIALS || '',
  GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID || '',
  GOOGLE_ANDROID_CLIENT_ID: process.env.GOOGLE_ANDROID_CLIENT_ID || '',
  GOOGLE_IOS_CLIENT_ID: process.env.GOOGLE_IOS_CLIENT_ID || '',
  APPLE_AUDIENCES: getOptionalEnv('APPLE_AUDIENCES', 'com.jiny.coachdesk')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean),
};
