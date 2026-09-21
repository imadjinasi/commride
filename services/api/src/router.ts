import {
  DurableObjectActiveRideGateway,
  type ActiveRideGateway,
} from './active-ride/gateway';
import {
  handleActiveRideRequest,
  isActiveRidePath,
} from './active-ride/handler';
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
  handleCheckpointRequest,
  isCheckpointPath,
} from './checkpoints/handler';
import {
  D1CheckpointRepository,
  type CheckpointRepository,
} from './checkpoints/repository';
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
import {
  handlePushTokenRequest,
  isPushTokenPath,
} from './push/handler';
import type { RidePushNotifier } from './push/notifier';
import {
  D1PushRepository,
  type PushRepository,
} from './push/repository';
import { resolveRidePushNotifier } from './push/runtime';
import {
  handleRideCommsRequest,
  isRideCommsPath,
} from './ride-comms/handler';
import {
  D1RideMessageRepository,
  type RideMessageRepository,
} from './ride-comms/repository';
import { handleRideSosRequest, isRideSosPath } from './ride-sos/handler';
import {
  handleRideRecapRequest,
  isRideRecapPath,
} from './ride-recap/handler';
import {
  D1RideRecapRepository,
  type RideRecapRepository,
} from './ride-recap/repository';
import {
  D1RideSosRepository,
  type RideSosRepository,
} from './ride-sos/repository';
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
import {
  handleVehicleRequest,
  isVehicleRequestPath,
} from './vehicles/vehicle-handler';
import {
  D1VehicleRepository,
  type VehicleRepository,
} from './vehicles/vehicle-repository';

const SERVICE_NAME = 'commride-api';
const SERVICE_VERSION = '0.1.0';

const firebaseVerifiers = new Map<string, FirebaseIdTokenVerifier>();

export interface RouterOverrides {
  readonly identityVerifier?: IdentityVerifier;
  readonly riderRepository?: RiderRepository;
  readonly vehicleRepository?: VehicleRepository;
  readonly clubRideRepository?: ClubRideRepository;
  readonly clubRideReadRepository?: ClubRideReadRepository;
  readonly routePlaceProvider?: RoutePlaceProvider;
  readonly routePlanRepository?: RoutePlanRepository;
  readonly rideBriefingRepository?: RideBriefingRepository;
  readonly checkpointRepository?: CheckpointRepository;
  readonly rideMessageRepository?: RideMessageRepository;
  readonly rideSosRepository?: RideSosRepository;
  readonly rideRecapRepository?: RideRecapRepository;
  readonly pushRepository?: PushRepository;
  readonly ridePushNotifier?: RidePushNotifier;
  readonly activeRideGateway?: ActiveRideGateway;
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

    if (isActiveRidePath(url.pathname)) {
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
      const activeRideGateway =
        overrides.activeRideGateway ?? resolveActiveRideGateway(env);

      if (
        riderRepository == null ||
        clubRideRepository == null
      ) {
        return errorResponse(
          'database_not_configured',
          'Active Ride authorization persistence is not configured.',
          503,
          requestId,
        );
      }

      if (activeRideGateway == null) {
        return errorResponse(
          'realtime_not_configured',
          'Active Ride realtime is not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleActiveRideRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          activeRideGateway,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isRideRecapPath(url.pathname)) {
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
      const rideRecapRepository =
        overrides.rideRecapRepository ??
        (env.DB == null ? null : new D1RideRecapRepository(env.DB));

      if (
        riderRepository == null ||
        clubRideRepository == null ||
        rideRecapRepository == null
      ) {
        return errorResponse(
          'database_not_configured',
          'Ride Recap persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleRideRecapRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          rideRecapRepository,
          now: overrides.now,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isCheckpointPath(url.pathname)) {
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
      const checkpointRepository =
        overrides.checkpointRepository ??
        (env.DB == null ? null : new D1CheckpointRepository(env.DB));

      if (
        riderRepository == null ||
        clubRideRepository == null ||
        routePlanRepository == null ||
        checkpointRepository == null
      ) {
        return errorResponse(
          'database_not_configured',
          'Checkpoint coordination persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleCheckpointRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          routePlanRepository,
          checkpointRepository,
          pushNotifier:
            overrides.ridePushNotifier ??
            resolveRidePushNotifier(env) ??
            undefined,
          now: overrides.now,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isRideSosPath(url.pathname)) {
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
      const rideSosRepository =
        overrides.rideSosRepository ??
        (env.DB == null ? null : new D1RideSosRepository(env.DB));

      if (
        riderRepository == null ||
        clubRideRepository == null ||
        rideSosRepository == null
      ) {
        return errorResponse(
          'database_not_configured',
          'Ride SOS persistence is not configured.',
          503,
          requestId,
        );
      }

      const response = await handleRideSosRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          rideSosRepository,
          activeRideGateway:
            overrides.activeRideGateway ??
            resolveActiveRideGateway(env) ??
            undefined,
          pushNotifier:
            overrides.ridePushNotifier ??
            resolveRidePushNotifier(env) ??
            undefined,
          idFactory: overrides.idFactory,
          now: overrides.now,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isRideCommsPath(url.pathname)) {
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
      const rideMessageRepository =
        overrides.rideMessageRepository ??
        (env.DB == null ? null : new D1RideMessageRepository(env.DB));

      if (
        riderRepository == null ||
        clubRideRepository == null ||
        rideMessageRepository == null
      ) {
        return errorResponse(
          'database_not_configured',
          'Ride communication persistence is not configured.',
          503,
          requestId,
        );
      }

      const response = await handleRideCommsRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          clubRideRepository,
          messageRepository: rideMessageRepository,
          activeRideGateway:
            overrides.activeRideGateway ??
            resolveActiveRideGateway(env) ??
            undefined,
          pushNotifier:
            overrides.ridePushNotifier ??
            resolveRidePushNotifier(env) ??
            undefined,
          idFactory: overrides.idFactory,
          now: overrides.now,
        },
      );

      if (response != null) {
        return response;
      }
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
          pushNotifier:
            overrides.ridePushNotifier ??
            resolveRidePushNotifier(env) ??
            undefined,
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
          activeRideGateway:
            overrides.activeRideGateway ?? resolveActiveRideGateway(env) ?? undefined,
          rideSosRepository:
            overrides.rideSosRepository ??
            (env.DB == null ? undefined : new D1RideSosRepository(env.DB)),
          pushNotifier:
            overrides.ridePushNotifier ??
            resolveRidePushNotifier(env) ??
            undefined,
          idFactory: overrides.idFactory,
          now: overrides.now,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isVehicleRequestPath(url.pathname)) {
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
      const vehicleRepository =
        overrides.vehicleRepository ??
        (env.DB == null ? null : new D1VehicleRepository(env.DB));

      if (riderRepository == null || vehicleRepository == null) {
        return errorResponse(
          'database_not_configured',
          'Vehicle persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      const response = await handleVehicleRequest(
        request,
        url,
        requestId,
        {
          identityVerifier,
          riderRepository,
          vehicleRepository,
          idFactory: overrides.idFactory,
        },
      );

      if (response != null) {
        return response;
      }
    }

    if (isPushTokenPath(url.pathname)) {
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
      const pushRepository =
        overrides.pushRepository ??
        (env.DB == null ? null : new D1PushRepository(env.DB));

      if (riderRepository == null || pushRepository == null) {
        return errorResponse(
          'database_not_configured',
          'Push-token persistence is not configured for this environment.',
          503,
          requestId,
        );
      }

      return handlePushTokenRequest(request, requestId, {
        identityVerifier,
        riderRepository,
        pushRepository,
        idFactory: overrides.idFactory,
        now: overrides.now,
      });
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


function resolveActiveRideGateway(env: Env): ActiveRideGateway | null {
  if (env.ACTIVE_RIDE_ROOM == null) {
    return null;
  }

  return new DurableObjectActiveRideGateway(env.ACTIVE_RIDE_ROOM);
}
