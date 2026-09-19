import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { PushPlatform } from './models';
import type { PushRepository } from './repository';

const MAX_TOKEN_LENGTH = 4096;

export interface PushTokenHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly pushRepository: PushRepository;
  readonly idFactory?: () => string;
  readonly now?: () => Date;
}

export function isPushTokenPath(pathname: string): boolean {
  return pathname === '/v1/me/push-tokens';
}

export async function handlePushTokenRequest(
  request: Request,
  requestId: string,
  dependencies: PushTokenHandlerDependencies,
): Promise<Response> {
  if (request.method !== 'POST' && request.method !== 'DELETE') {
    return errorResponse(
      'method_not_allowed',
      'Only POST or DELETE is supported for this endpoint.',
      405,
      requestId,
    );
  }

  const authentication = await authenticateRider(
    request,
    dependencies.identityVerifier,
    dependencies.riderRepository,
  );
  if ('error' in authentication) {
    return errorResponse(
      authentication.error,
      authentication.message,
      authentication.status,
      requestId,
    );
  }

  const body = await readBody(request);
  if ('error' in body) {
    return errorResponse('invalid_push_token', body.error, 400, requestId);
  }

  if (request.method === 'DELETE') {
    await dependencies.pushRepository.unregisterToken(
      authentication.rider.id,
      body.token,
    );
    return jsonResponse({ unregistered: true }, 200, requestId);
  }

  const now = (dependencies.now?.() ?? new Date()).toISOString();
  const token = await dependencies.pushRepository.registerToken({
    id: dependencies.idFactory?.() ?? crypto.randomUUID(),
    riderId: authentication.rider.id,
    token: body.token,
    platform: body.platform,
    now,
  });
  return jsonResponse(
    {
      pushToken: {
        id: token.id,
        platform: token.platform,
        updatedAt: token.updatedAt,
      },
    },
    200,
    requestId,
  );
}

async function readBody(
  request: Request,
): Promise<
  | { readonly token: string; readonly platform: PushPlatform }
  | { readonly error: string }
> {
  let decoded: unknown;
  try {
    decoded = await request.json();
  } catch {
    return { error: 'Request body must be valid JSON.' };
  }
  if (!isRecord(decoded)) {
    return { error: 'Request body must be a JSON object.' };
  }

  const token = decoded.token;
  if (
    typeof token !== 'string' ||
    token.trim().length === 0 ||
    token.length > MAX_TOKEN_LENGTH
  ) {
    return { error: 'token must be a non-empty string up to 4096 characters.' };
  }

  const platform = decoded.platform;
  if (platform !== 'android' && platform !== 'ios') {
    return { error: 'platform must be android or ios.' };
  }

  return { token: token.trim(), platform };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
