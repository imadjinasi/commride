import { FirebaseIdTokenVerifier } from './auth/firebase-id-token-verifier';
import type { IdentityVerifier } from './auth/identity';
import type { Env } from './env';
import { errorResponse, jsonResponse } from './http/json';
import { resolveRequestId } from './request-id';
import { handleRiderProfile } from './riders/profile-handler';
import {
  D1RiderRepository,
  type RiderRepository,
} from './riders/rider-repository';

const SERVICE_NAME = 'commride-api';
const SERVICE_VERSION = '0.1.0';

const firebaseVerifiers = new Map<string, FirebaseIdTokenVerifier>();

export interface RouterOverrides {
  readonly identityVerifier?: IdentityVerifier;
  readonly riderRepository?: RiderRepository;
  readonly idFactory?: () => string;
}

export async function handleRequest(
  request: Request,
  env: Env,
  overrides: RouterOverrides = {},
): Promise<Response> {
  const requestId = resolveRequestId(request);
  const url = new URL(request.url);

  try {
    if (url.pathname === '/health') {
      if (request.method !== 'GET') {
        return errorResponse(
          'method_not_allowed',
          'Only GET is supported for this endpoint.',
          405,
          requestId,
        );
      }

      return jsonResponse(
        {
          status: 'ok',
          service: SERVICE_NAME,
          version: SERVICE_VERSION,
          requestId,
        },
        200,
        requestId,
      );
    }

    if (url.pathname === '/version') {
      if (request.method !== 'GET') {
        return errorResponse(
          'method_not_allowed',
          'Only GET is supported for this endpoint.',
          405,
          requestId,
        );
      }

      return jsonResponse(
        {
          service: SERVICE_NAME,
          version: SERVICE_VERSION,
          requestId,
        },
        200,
        requestId,
      );
    }

    if (url.pathname === '/v1/me') {
      const identityVerifier =
        overrides.identityVerifier ?? resolveFirebaseVerifier(env);
      if (identityVerifier == null) {
        return errorResponse(
          'authentication_not_configured',
          'Authentication is not configured for this environment.',
          503,
          requestId,
        );
      }

      const riderRepository =
        overrides.riderRepository ??
        (env.DB == null ? null : new D1RiderRepository(env.DB));
      if (riderRepository == null) {
        return errorResponse(
          'database_not_configured',
          'Rider persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      return handleRiderProfile(request, requestId, {
        identityVerifier,
        riderRepository,
        idFactory: overrides.idFactory,
      });
    }

    return errorResponse(
      'not_found',
      'The requested API endpoint does not exist.',
      404,
      requestId,
    );
  } catch {
    return errorResponse(
      'internal_error',
      'The request could not be completed.',
      500,
      requestId,
    );
  }
}

function resolveFirebaseVerifier(env: Env): IdentityVerifier | null {
  const projectId = env.FIREBASE_PROJECT_ID?.trim();
  if (projectId == null || projectId.length === 0) {
    return null;
  }

  const existing = firebaseVerifiers.get(projectId);
  if (existing != null) {
    return existing;
  }

  const verifier = new FirebaseIdTokenVerifier(projectId);
  firebaseVerifiers.set(projectId, verifier);
  return verifier;
}
