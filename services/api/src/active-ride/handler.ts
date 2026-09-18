import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { ActiveRideGateway } from './gateway';
import { ACTIVE_RIDE_PROTOCOL_VERSION } from './protocol';

export interface ActiveRideHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly activeRideGateway: ActiveRideGateway;
}

export function isActiveRidePath(pathname: string): boolean {
  return matchActiveRidePath(pathname) != null;
}

export async function handleActiveRideRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: ActiveRideHandlerDependencies,
): Promise<Response | null> {
  const rideId = matchActiveRidePath(url.pathname);
  if (rideId == null) {
    return null;
  }

  if (request.method !== 'GET') {
    return errorResponse(
      'method_not_allowed',
      'Only GET is supported for the Active Ride WebSocket endpoint.',
      405,
      requestId,
    );
  }

  if (request.headers.get('upgrade')?.toLowerCase() !== 'websocket') {
    return errorResponse(
      'websocket_upgrade_required',
      'Active Ride realtime requires a WebSocket upgrade.',
      426,
      requestId,
    );
  }

  const version = url.searchParams.get('v');
  if (version !== String(ACTIVE_RIDE_PROTOCOL_VERSION)) {
    return errorResponse(
      'unsupported_protocol_version',
      'Use Active Ride protocol v=1.',
      400,
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

  const rider = authentication.rider;
  const ride = await dependencies.clubRideRepository.findRide(rideId);
  if (ride == null) {
    return errorResponse(
      'ride_not_found',
      'The Ride does not exist.',
      404,
      requestId,
    );
  }

  if (ride.status !== 'active') {
    return errorResponse(
      'active_ride_required',
      'Realtime room access is available only while the Ride is Active.',
      409,
      requestId,
    );
  }

  const membership =
    await dependencies.clubRideRepository.findRideMembership(
      rideId,
      rider.id,
    );

  if (
    membership == null ||
    membership.status === 'invited' ||
    membership.status === 'left' ||
    membership.status === 'finished'
  ) {
    return errorResponse(
      'ride_membership_required',
      'A participating Ride membership is required for realtime access.',
      403,
      requestId,
    );
  }

  return dependencies.activeRideGateway.connect(
    request,
    rideId,
    {
      riderId: rider.id,
      displayName: rider.displayName,
      role: membership.role,
    },
  );
}

function matchActiveRidePath(pathname: string): string | null {
  const match = /^\/v1\/rides\/([^/]+)\/live$/.exec(pathname);
  return match?.[1] == null ? null : decodeURIComponent(match[1]);
}
