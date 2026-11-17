import {
  applicationDefault,
  cert,
  getApps,
  initializeApp,
} from 'firebase-admin/app';
import { getMessaging, type Messaging } from 'firebase-admin/messaging';
import { User } from '../models/User.js';

const TOKEN_BATCH_SIZE = 500;
const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

export interface PushNotification {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushSendResult {
  successCount: number;
  failureCount: number;
}

let messaging: Messaging | null = null;

export const initializeFirebaseAdmin = (): void => {
  if (messaging) return;

  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  const existingApp = getApps().find((app) => app.name === '[DEFAULT]');
  const app =
    existingApp ??
    (serviceAccountJson
      ? initializeApp({
          credential: cert(parseServiceAccount(serviceAccountJson)),
        })
      : initializeApp({ credential: applicationDefault() }));

  if (!serviceAccountJson && !process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim()) {
    console.warn(
      'Firebase Admin usa Application Default Credentials; configura GOOGLE_APPLICATION_CREDENTIALS o FIREBASE_SERVICE_ACCOUNT_JSON si el entorno no las proporciona.',
    );
  }
  messaging = getMessaging(app);
};

const parseServiceAccount = (
  value: string,
): { projectId: string; clientEmail: string; privateKey: string } => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value);
  } catch {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON no contiene JSON válido');
  }

  if (typeof parsed !== 'object' || parsed === null) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON debe ser un objeto JSON');
  }
  const account = parsed as Record<string, unknown>;
  const projectId = account.project_id;
  const clientEmail = account.client_email;
  const privateKey = account.private_key;
  if (
    typeof projectId !== 'string' ||
    typeof clientEmail !== 'string' ||
    typeof privateKey !== 'string'
  ) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT_JSON debe incluir project_id, client_email y private_key',
    );
  }

  return {
    projectId,
    clientEmail,
    privateKey: privateKey.replace(/\\n/g, '\n'),
  };
};

export const sendPushToUser = async (
  userId: string,
  notification: PushNotification,
): Promise<PushSendResult> => {
  if (!messaging) {
    throw new Error('Firebase Admin no ha sido inicializado');
  }

  const user = await User.findById(userId).select('+fcmTokens');
  const tokens = user?.fcmTokens ?? [];
  if (tokens.length === 0) {
    return { successCount: 0, failureCount: 0 };
  }

  let successCount = 0;
  let failureCount = 0;
  const invalidTokens = new Set<string>();

  for (let offset = 0; offset < tokens.length; offset += TOKEN_BATCH_SIZE) {
    const batch = tokens.slice(offset, offset + TOKEN_BATCH_SIZE);
    const response = await messaging.sendEachForMulticast({
      tokens: batch,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      ...(notification.data ? { data: notification.data } : {}),
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });

    successCount += response.successCount;
    failureCount += response.failureCount;
    response.responses.forEach((result, index) => {
      const token = batch[index];
      if (token && result.error && INVALID_TOKEN_CODES.has(result.error.code)) {
        invalidTokens.add(token);
      }
    });
  }

  if (invalidTokens.size > 0) {
    try {
      await User.updateOne(
        { _id: userId },
        { $pull: { fcmTokens: { $in: [...invalidTokens] } } },
      );
    } catch (error) {
      console.error('No se pudieron eliminar tokens FCM inválidos', error);
    }
  }

  if (failureCount > 0) {
    console.warn(
      `Firebase rechazó ${failureCount} de ${successCount + failureCount} notificaciones para el usuario ${userId}`,
    );
  }

  return { successCount, failureCount };
};
