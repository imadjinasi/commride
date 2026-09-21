import {
  AuthenticationRequiredError,
  extractBearerToken,
} from '../auth/authorization';
import {
  type IdentityVerifier,
  InvalidIdentityTokenError,
} from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from './rider-repository';

export interface RiderProfileHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly idFactory?: () => string;
}

interface ProfileInput {
  readonly displayName: string;
  readonly callsign: string | null;
  readonly homeArea: string | null;
}

export async function handleRiderProfile(
  request: Request,
  requestId: string,
  dependencies: RiderProfileHandlerDependencies,
): Promise<Response> {
  let token: string;
  try {
    token = extractBearerToken(request);
  } catch (error) {
    if (error instanceof AuthenticationRequiredError) {
      return errorResponse(
        'authentication_required',
        error.message,
        401,
        requestId,
      );
    }
    throw error;
  }

  let authSubject: string;
  try {
    const identity = await dependencies.identityVerifier.verify(token);
    authSubject = identity.subject;
  } catch (error) {
    if (error instanceof InvalidIdentityTokenError) {
      return errorResponse(
        'invalid_authentication_token',
        error.message,
        401,
        requestId,
      );
    }
    throw error;
  }

  if (request.method === 'GET') {
    const profile = await dependencies.riderRepository.findByAuthSubject(
      authSubject,
    );

    if (profile == null) {
      return errorResponse(
        'rider_profile_not_found',
        'The authenticated Rider does not have a profile yet.',
        404,
        requestId,
      );
    }

    return jsonResponse({ rider: profile }, 200, requestId);
  }

  if (request.method === 'PUT') {
    const inputResult = await readProfileInput(request);
    if ('error' in inputResult) {
      return errorResponse(
        'invalid_rider_profile',
        inputResult.error,
        400,
        requestId,
      );
    }

    const profile = await dependencies.riderRepository.upsertProfile({
      newRiderId:
        dependencies.idFactory?.() ?? crypto.randomUUID(),
      authSubject,
      displayName: inputResult.value.displayName,
      callsign: inputResult.value.callsign,
      homeArea: inputResult.value.homeArea,
    });

    return jsonResponse({ rider: profile }, 200, requestId);
  }

  return errorResponse(
    'method_not_allowed',
    'Only GET and PUT are supported for this endpoint.',
    405,
    requestId,
  );
}

async function readProfileInput(
  request: Request,
): Promise<{ value: ProfileInput } | { error: string }> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { error: 'Request body must be valid JSON.' };
  }

  if (!isRecord(body)) {
    return { error: 'Request body must be a JSON object.' };
  }

  const displayName = normalizeRequiredString(body.displayName, 80);
  if (displayName == null) {
    return {
      error: 'displayName must be between 1 and 80 characters.',
    };
  }

  const callsign = normalizeOptionalString(body.callsign, 40);
  if (callsign === undefined) {
    return {
      error: 'callsign must be null or between 1 and 40 characters.',
    };
  }

  const homeArea = normalizeOptionalString(body.homeArea, 120);
  if (homeArea === undefined) {
    return {
      error: 'homeArea must be null or at most 120 characters.',
    };
  }

  return {
    value: {
      displayName,
      callsign,
      homeArea,
    },
  };
}

function normalizeRequiredString(
  value: unknown,
  maxLength: number,
): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maxLength) {
    return null;
  }

  return normalized;
}

function normalizeOptionalString(
  value: unknown,
  maxLength: number,
): string | null | undefined {
  if (value == null) {
    return null;
  }

  if (typeof value !== 'string') {
    return undefined;
  }

  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maxLength) {
    return undefined;
  }

  return normalized;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
