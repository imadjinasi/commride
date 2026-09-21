import type { Env } from '../env';
import { FcmHttpV1Transport } from './fcm';
import { BestEffortRidePushNotifier, type RidePushNotifier } from './notifier';
import { D1PushRepository } from './repository';

const notifiers = new Map<string, RidePushNotifier>();

export function resolveRidePushNotifier(env: Env): RidePushNotifier | null {
  const database = env.DB;
  const projectId = env.FIREBASE_PROJECT_ID?.trim();
  const clientEmail = env.FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL?.trim();
  const privateKey = env.FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY?.trim();

  if (
    database == null ||
    projectId == null ||
    projectId.length === 0 ||
    clientEmail == null ||
    clientEmail.length === 0 ||
    privateKey == null ||
    privateKey.length === 0
  ) {
    return null;
  }

  const cacheKey = `${projectId}|${clientEmail}`;
  const cached = notifiers.get(cacheKey);
  if (cached != null) {
    return cached;
  }

  const repository = new D1PushRepository(database);
  const transport = new FcmHttpV1Transport({
    projectId,
    clientEmail,
    privateKeyPem: privateKey,
    pushRepository: repository,
  });
  const notifier = new BestEffortRidePushNotifier(repository, transport);
  notifiers.set(cacheKey, notifier);
  return notifier;
}
