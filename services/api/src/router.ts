import { FirebaseIdTokenVerifier } from './auth/firebase-id-token-verifier';
import {
  handleRideBriefingRequest,
  isRideBriefingPath,
} from './briefings/handler';
import {
  D1RideBriefingRepository,
  type RideBriefingRepository,
} from './briefings/repository';
import type { IdentityVerifier } from './auth/identity';
import {
  handleClubRideRequest,
  isClubRideRequestPath,
} from './clubs-rides/handler';
import {
  handleClubRideReadRequest,
  isClubRideReadPath,
} from './clubs-rides/read-handler';
import {
  D1ClubRideReadRepository,
  type ClubRideReadRepository,
} from './clubs-rides/read-repository';
import {
  D1ClubRideRepository,
  type ClubRideRepository,
} from './clubs-rides/repository';
import type { Env } from './env';
import { errorResponse, jsonResponse } from './http/json';
import { GoogleMapsPlatformProvider } from './maps/google-maps-platform-provider';
import { handleMapsRequest, isMapsPath } from './maps/handler';
import type { RoutePlaceProvider } from './maps/provider';
import { resolveRequestId } from './request-id';
import { handleRiderProfile } from './riders/profile-handler';
import {
  handleRoutePlanRequest,
  isRoutePlanPath,
} from './route-plans/handler';
import {
  D1RoutePlanRepository,
  type RoutePlanRepository,
} from './route-plans/repository';
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
  readonly clubRideRepository?: ClubRideRepository;
  readonly clubRideReadRepository?: ClubRideReadRepository;
  readonly routePlaceProvider?: RoutePlaceProvider;
  readonly routePlanRepository?: RoutePlanRepository;
  readonly rideBriefingRepository?: RideBriefingRepository;
  readonly idFactory?: () => string;
  readonly now?: () => Date;
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

    if (isRideBriefingPath(url.pathname)) {
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
      const clubRideRepository =
        overrides.clubRideRepository ??
        (env.DB == null ? null : new D1ClubRideRepository(env.DB));
      const routePlanRepository =
        overrides.routePlanRepository ??
        (env.DB == null ? null : new D1RoutePlanRepository(env.DB));
      const rideBriefingRepository =
        overrides.rideBriefingRepository ??
        (env.DB == null ? null : new D1RideBriefingRepository(env.DB));

      if (
        riderRepository == null ||
        clubRideRepository == null ||
        routePlanRepository == null ||
        rideBriefingRepository == null
      ) {
        return errorResponse(
          'database_not_configured',
          'Ride Briefing persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleRideBriefingRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          routePlanRepository,
          rideBriefingRepository,
          idFactory: overrides.idFactory,
          now: overrides.now,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isRoutePlanPath(url.pathname)) {
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
      const clubRideRepository =
        overrides.clubRideRepository ??
        (env.DB == null ? null : new D1ClubRideRepository(env.DB));
      const routePlanRepository =
        overrides.routePlanRepository ??
        (env.DB == null ? null : new D1RoutePlanRepository(env.DB));

      if (
        riderRepository == null ||
        clubRideRepository == null ||
        routePlanRepository == null
      ) {
        return errorResponse(
          'database_not_configured',
          'RoutePlan persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleRoutePlanRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          routePlanRepository,
          idFactory: overrides.idFactory,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isMapsPath(url.pathname)) {
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

      const routePlaceProvider =
        overrides.routePlaceProvider ?? resolveRoutePlaceProvider(env);
      if (routePlaceProvider == null) {
        return errorResponse(
          'maps_not_configured',
          'Route and place services are not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleMapsRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          provider: routePlaceProvider,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (request.method === 'GET' && isClubRideReadPath(url.pathname)) {
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
      const clubRideRepository =
        overrides.clubRideRepository ??
        (env.DB == null ? null : new D1ClubRideRepository(env.DB));
      const clubRideReadRepository =
        overrides.clubRideReadRepository ??
        (env.DB == null ? null : new D1ClubRideReadRepository(env.DB));

      if (
        riderRepository == null ||
        clubRideRepository == null ||
        clubRideReadRepository == null
      ) {
        return errorResponse(
          'database_not_configured',
          'Club and Ride read persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleClubRideReadRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          readRepository: clubRideReadRepository,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isClubRideRequestPath(url.pathname)) {
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
      const clubRideRepository =
        overrides.clubRideRepository ??
        (env.DB == null ? null : new D1ClubRideRepository(env.DB));

      if (riderRepository == null || clubRideRepository == null) {
        return errorResponse(
          'database_not_configured',
          'Club and Ride persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleClubRideRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          idFactory: overrides.idFactory,
          now: overrides.now,
        },
      );

      if (response != null) {
        return response;
      }
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


function resolveRoutePlaceProvider(env: Env): RoutePlaceProvider | null {
  const apiKey = env.GOOGLE_MAPS_PLATFORM_API_KEY?.trim();
  if (apiKey == null || apiKey.length === 0) {
    return null;
  }

  return new GoogleMapsPlatformProvider(apiKey);
}
