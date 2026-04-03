import { Client } from 'minio';
import { env } from '../config/env';

const url = new URL(env.MINIO_ENDPOINT);

export const minioClient = new Client({
  endPoint: url.hostname,
  port: parseInt(url.port) || 9000,
  useSSL: url.protocol === 'https:',
  accessKey: env.MINIO_ACCESS_KEY,
  secretKey: env.MINIO_SECRET_KEY,
});

export async function uploadFile(
  fileName: string,
  buffer: Buffer,
  contentType: string,
): Promise<string> {
  await minioClient.putObject(env.MINIO_BUCKET, fileName, buffer, buffer.length, {
    'Content-Type': contentType,
  });
  return `${env.STORAGE_PUBLIC_URL}/${fileName}`;
}
