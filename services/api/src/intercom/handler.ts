import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import {
  IntercomProviderError,
  type IntercomPreset,
  type IntercomRoomProvider,
} from './provider';
import type { IntercomRoomRepository } from './repository';

export interface RideIntercomHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  /** Null when no provider credentials are configured. */
  readonly provider: IntercomRoomProvider | null;
  readonly roomRepository: IntercomRoomRepository;
  readonly now?: () => Date;
}

export function isRideIntercomPath(pathname: string): boolean {
  return matchRideIntercomPath(pathname) != null;
}

/**
 * Mints a voice intercom join token for a participating Rider of an Active
 * Ride. Provider credentials never leave the Worker.
 */
export async function handleRideIntercomRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: RideIntercomHandlerDependencies,
): Promise<Response | null> {
  const rideId = matchRideIntercomPath(url.pathname);
  if (rideId == null) {
    return null;
  }

  if (request.method !== 'POST') {
    return errorResponse(
      'method_not_allowed',
      'Only POST is supported for the intercom token endpoint.',
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
      'Intercom is available only while the Ride is Active.',
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
      'A participating Ride membership is required for intercom access.',
      403,
      requestId,
    );
  }

  const provider = dependencies.provider;
  if (provider == null) {
    return errorResponse(
      'intercom_not_configured',
      'Voice intercom is not configured for this environment.',
      503,
      requestId,
    );
  }

  const preset: IntercomPreset =
    membership.role === 'leader' ? 'leader' : 'rider';

  try {
    let room = await dependencies.roomRepository.find(rideId);
    if (room == null) {
      const providerRoomId = await provider.createRoom(
        `CommRide Ride ${rideId}`,
      );
      room = await dependencies.roomRepository.insertIfAbsent({
        rideId,
        provider: provider.name,
        providerRoomId,
        createdAt: (dependencies.now?.() ?? new Date()).toISOString(),
      });
    }

    const authToken = await provider.addParticipant({
      roomId: room.providerRoomId,
      riderId: rider.id,
      displayName: rider.callsign ?? rider.displayName,
      preset,
    });

    return jsonResponse(
      {
        intercom: {
          provider: provider.name,
          authToken,
          baseDomain: provider.clientBaseDomain,
          role: preset,
          canModerate: preset === 'leader',
        },
      },
      200,
      requestId,
    );
  } catch (error) {
    if (error instanceof IntercomProviderError) {
      return errorResponse(
        'intercom_provider_unavailable',
        'The voice intercom provider could not be reached.',
        502,
        requestId,
      );
    }
    throw error;
  }
}

function matchRideIntercomPath(pathname: string): string | null {
  const match = /^\/v1\/rides\/([^/]+)\/intercom\/token$/.exec(pathname);
  return match?.[1] == null ? null : decodeURIComponent(match[1]);
}
