import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { ClubRideRepository } from './repository';
import type { ClubRideReadRepository } from './read-repository';

export interface ClubRideReadHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly readRepository: ClubRideReadRepository;
}

export function isClubRideReadPath(pathname: string): boolean {
  return matchReadRoute(pathname) != null;
}

export async function handleClubRideReadRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: ClubRideReadHandlerDependencies,
): Promise<Response | null> {
  const route = matchReadRoute(url.pathname);
  if (route == null) {
    return null;
  }

  if (request.method !== 'GET') {
    return null;
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

  if (route.kind === 'list_clubs') {
    const clubs = await dependencies.readRepository.listClubsForRider(
      rider.id,
    );
    return jsonResponse({ clubs }, 200, requestId);
  }

  const membership = await dependencies.clubRideRepository.findClubMembership(
    route.clubId,
    rider.id,
  );
  if (membership?.status !== 'active') {
    return errorResponse(
      'club_membership_required',
      'An active Club membership is required to view its Rides.',
      403,
      requestId,
    );
  }

  const rides = await dependencies.readRepository.listRidesForClub(
    route.clubId,
    rider.id,
  );
  return jsonResponse({ rides }, 200, requestId);
}

type ReadRoute =
  | { readonly kind: 'list_clubs' }
  | { readonly kind: 'list_club_rides'; readonly clubId: string };

function matchReadRoute(pathname: string): ReadRoute | null {
  if (pathname === '/v1/clubs') {
    return { kind: 'list_clubs' };
  }

  const rides = /^\/v1\/clubs\/([^/]+)\/rides$/.exec(pathname);
  if (rides?.[1] == null) {
    return null;
  }

  return {
    kind: 'list_club_rides',
    clubId: decodeURIComponent(rides[1]),
  };
}
