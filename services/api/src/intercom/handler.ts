import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { RideMembership } from '../clubs-rides/models';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderProfile } from '../riders/rider-profile';
import type { RiderRepository } from '../riders/rider-repository';
import {
  IntercomProviderError,
  type IntercomPreset,
  type IntercomRoomProvider,
} from './provider';

export interface RideIntercomHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  /** Null when no provider credentials are configured. */
  readonly provider: IntercomRoomProvider | null;
}

type IntercomAction = 'token' | 'mute';

export function isRideIntercomPath(pathname: string): boolean {
  return matchRideIntercomPath(pathname) != null;
}

/**
 * Ride voice intercom for participating Riders of an Active Ride:
 * `token` mints a join token, `mute` lets the Ride Leader mute a Rider's
 * microphone for everyone. Provider credentials never leave the Worker.
 */
export async function handleRideIntercomRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: RideIntercomHandlerDependencies,
): Promise<Response | null> {
  const match = matchRideIntercomPath(url.pathname);
  if (match == null) {
    return null;
  }
  const { rideId, action } = match;

  if (request.method !== 'POST') {
    return errorResponse(
      'method_not_allowed',
      'Only POST is supported for intercom endpoints.',
      405,
      requestId,
    );
  }

  const access = await authorize(request, rideId, requestId, dependencies);
  if (access instanceof Response) {
    return access;
  }
  const { rider, membership } = access;

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
    if (action === 'token') {
      const authToken = await provider.mintJoinToken({
        rideId,
        riderId: rider.id,
        displayName: rider.callsign ?? rider.displayName,
      });
      return jsonResponse(
        {
          intercom: {
            provider: provider.name,
            serverUrl: provider.clientUrl,
            authToken,
            role: preset,
            canModerate: preset === 'leader',
          },
        },
        200,
        requestId,
      );
    }

    if (preset !== 'leader') {
      return errorResponse(
        'ride_leader_required',
        'Only the Ride Leader can mute a Rider for everyone.',
        403,
        requestId,
      );
    }
    const target = await readTargetRiderId(request);
    if (target == null) {
      return errorResponse(
        'invalid_request',
        'Body must be {"riderId": string}.',
        400,
        requestId,
      );
    }
    const muted = await provider.muteRider(rideId, target);
    if (!muted) {
      return errorResponse(
        'intercom_participant_not_found',
        'That Rider is not talking in the intercom.',
        404,
        requestId,
      );
    }
    return jsonResponse({ muted: true }, 200, requestId);
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

async function authorize(
  request: Request,
  rideId: string,
  requestId: string,
  dependencies: RideIntercomHandlerDependencies,
): Promise<{ rider: RiderProfile; membership: RideMembership } | Response> {
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

  return { rider, membership };
}

async function readTargetRiderId(request: Request): Promise<string | null> {
  try {
    const body = (await request.json()) as { riderId?: unknown };
    return typeof body.riderId === 'string' && body.riderId.trim() !== ''
      ? body.riderId
      : null;
  } catch {
    return null;
  }
}

function matchRideIntercomPath(
  pathname: string,
): { rideId: string; action: IntercomAction } | null {
  const match = /^\/v1\/rides\/([^/]+)\/intercom\/(token|mute)$/.exec(
    pathname,
  );
  if (match?.[1] == null || match[2] == null) {
    return null;
  }
  return {
    rideId: decodeURIComponent(match[1]),
    action: match[2] as IntercomAction,
  };
}
