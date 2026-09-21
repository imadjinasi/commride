import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { RideRecapRepository } from './repository';

export interface RideRecapHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly rideRecapRepository: RideRecapRepository;
  readonly now?: () => Date;
}

interface RideRecapPath {
  readonly rideId: string;
}

export function isRideRecapPath(pathname: string): boolean {
  return matchRideRecapPath(pathname) != null;
}

export async function handleRideRecapRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: RideRecapHandlerDependencies,
): Promise<Response | null> {
  const path = matchRideRecapPath(url.pathname);
  if (path == null) {
    return null;
  }

  if (request.method !== 'GET') {
    return errorResponse(
      'method_not_allowed',
      'Only GET is supported for this endpoint.',
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

  const ride = await dependencies.clubRideRepository.findRide(path.rideId);
  if (ride == null) {
    return errorResponse(
      'ride_not_found',
      'The Ride does not exist.',
      404,
      requestId,
    );
  }

  const membership = await dependencies.clubRideRepository.findRideMembership(
    path.rideId,
    authentication.rider.id,
  );
  if (
    membership == null ||
    membership.status === 'invited' ||
    membership.status === 'left'
  ) {
    return errorResponse(
      'ride_membership_required',
      'A participating Ride membership is required to view this recap.',
      403,
      requestId,
    );
  }

  if (ride.status !== 'completed') {
    return errorResponse(
      'ride_not_completed',
      'Ride Recap is available after the Ride is completed.',
      409,
      requestId,
    );
  }

  const generatedAt = (dependencies.now?.() ?? new Date()).toISOString();
  const recap = await dependencies.rideRecapRepository.build(
    path.rideId,
    generatedAt,
  );
  if (recap == null) {
    return errorResponse(
      'ride_recap_unavailable',
      'Ride Recap could not be built.',
      500,
      requestId,
    );
  }

  return jsonResponse({ recap }, 200, requestId);
}

function matchRideRecapPath(pathname: string): RideRecapPath | null {
  const match = /^\/v1\/rides\/([^/]+)\/recap$/.exec(pathname);
  if (match?.[1] == null) {
    return null;
  }
  return { rideId: decodeURIComponent(match[1]) };
}
