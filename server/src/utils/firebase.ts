import * as admin from 'firebase-admin';
import * as path from 'path';
import * as fs from 'fs';
import { env } from '../config/env';

let firebaseInitialized = false;

export function initializeFirebase() {
  if (firebaseInitialized) return;

  if (env.FIREBASE_SERVICE_ACCOUNT) {
    const credPath = path.resolve(env.FIREBASE_SERVICE_ACCOUNT);
    if (!fs.existsSync(credPath)) {
      console.warn(`Firebase credentials file not found: ${credPath}`);
      return;
    }
    const serviceAccount = JSON.parse(fs.readFileSync(credPath, 'utf-8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    firebaseInitialized = true;
    console.log('Firebase Admin initialized');
  } else {
    console.warn('FIREBASE_SERVICE_ACCOUNT not set — push notifications disabled');
  }
}

export async function sendPush(
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>,
): Promise<boolean> {
  if (!firebaseInitialized) return false;

  try {
    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: data ?? {},
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    return true;
  } catch (err: any) {
    if (err.code === 'messaging/registration-token-not-registered') {
      console.warn('Invalid FCM token, should be cleaned up:', fcmToken.substring(0, 10));
    } else {
      console.error('FCM send error:', err.message);
    }
    return false;
  }
}
