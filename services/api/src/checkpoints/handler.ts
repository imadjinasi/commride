import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { RidePushNotifier } from '../push/notifier';
import type { RoutePlan, RouteStop } from '../route-plans/models';
import type { RoutePlanRepository } from '../route-plans/repository';
import type {
  RideCheckpointItem,
  RideCheckpointView,
} from './models';
import type {
  CheckpointParticipantRecord,
  CheckpointRepository,
} from './repository';

export interface CheckpointHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly routePlanRepository: RoutePlanRepository;
  readonly checkpointRepository: CheckpointRepository;
  readonly pushNotifier?: RidePushNotifier;
  readonly now?: () => Date;
}

type CheckpointRoute =
  | {
      readonly kind: 'list';
      readonly rideId: string;
    }
  | {
      readonly kind: 'check_in' | 'release';
      readonly rideId: string;
      readonly checkpointId: string;
    };

export function isCheckpointPath(pathname: string): boolean {
  return matchCheckpointRoute(pathname) != null;
}

export async function handleCheckpointRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: CheckpointHandlerDependencies,
): Promise<Response | null> {
  const route = matchCheckpointRoute(url.pathname);
  if (route == null) {
    return null;
  }

  const allowedMethod =
    route.kind === 'list' ? 'GET' : 'POST';
  if (request.method !== allowedMethod) {
    return errorResponse(
      'method_not_allowed',
      `Only ${allowedMethod} is supported for this endpoint.`,
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
  const ride = await dependencies.clubRideRepository.findRide(route.rideId);
  if (ride == null) {
    return errorResponse(
      'ride_not_found',
      'The Ride does not exist.',
      404,
      requestId,
    );
  }

  const membership =
    await dependencies.clubRideRepository.findRideMembership(
      route.rideId,
      rider.id,
    );
  if (
    membership == null ||
    membership.status === 'invited' ||
    membership.status === 'left'
  ) {
    return errorResponse(
      'ride_participant_required',
      'A participating Ride membership is required.',
      403,
      requestId,
    );
  }

  if (
    route.kind === 'list' &&
    ride.status !== 'active' &&
    ride.status !== 'completed'
  ) {
    return errorResponse(
      'checkpoint_ride_state_conflict',
      'Checkpoint coordination is available after the Ride starts.',
      409,
      requestId,
    );
  }

  if (
    route.kind !== 'list' &&
    ride.status !== 'active'
  ) {
    return errorResponse(
      'active_ride_required',
      'Checkpoint coordination can change only while the Ride is Active.',
      409,
      requestId,
    );
  }

  if (
    route.kind === 'release' &&
    membership.role !== 'leader'
  ) {
    return errorResponse(
      'ride_leader_required',
      'The Ride Leader role is required to release a Checkpoint.',
      403,
      requestId,
    );
  }

  const routePlan =
    await dependencies.routePlanRepository.findCurrent(route.rideId);
  if (routePlan == null) {
    return errorResponse(
      'checkpoint_route_plan_required',
      'A saved RoutePlan is required for Checkpoint coordination.',
      409,
      requestId,
    );
  }

  const checkpointStops = routePlan.stops.filter(
    (
      stop,
    ): stop is RouteStop & {
      readonly checkpointType: NonNullable<RouteStop['checkpointType']>;
    } => stop.checkpointType != null,
  );

  if (route.kind === 'check_in') {
    const checkpoint = checkpointStops.find(
      (stop) => stop.id === route.checkpointId,
    );
    if (checkpoint == null) {
      return errorResponse(
        'checkpoint_not_found',
        'The Checkpoint does not belong to the Active Ride RoutePlan.',
        404,
        requestId,
      );
    }

    const checkedInAt =
      (dependencies.now?.() ?? new Date()).toISOString();
    await dependencies.checkpointRepository.checkIn(
      route.rideId,
      routePlan.id,
      checkpoint.id,
      rider.id,
      checkedInAt,
    );
  }

  if (route.kind === 'release') {
    const checkpoint = checkpointStops.find(
      (stop) => stop.id === route.checkpointId,
    );
    if (checkpoint == null) {
      return errorResponse(
        'checkpoint_not_found',
        'The Checkpoint does not belong to the Active Ride RoutePlan.',
        404,
        requestId,
      );
    }

    const released = await dependencies.checkpointRepository.release(
      route.rideId,
      routePlan.id,
      checkpoint.id,
      checkpoint.sequence,
      rider.id,
      (dependencies.now?.() ?? new Date()).toISOString(),
    );

    if (!released) {
      return errorResponse(
        'checkpoint_release_order_conflict',
        'Earlier Checkpoints must be released before this Checkpoint.',
        409,
        requestId,
      );
    }

    await notifyCheckpointReleaseBestEffort(
      route.rideId,
      routePlan.id,
      checkpoint.id,
      checkpoint.label,
      rider.id,
      dependencies,
    );
  }

  const checkpointView = await buildCheckpointView(
    route.rideId,
    rider.id,
    routePlan,
    checkpointStops,
    dependencies.checkpointRepository,
  );

  return jsonResponse({ checkpointView }, 200, requestId);
}

async function notifyCheckpointReleaseBestEffort(
  rideId: string,
  routePlanId: string,
  checkpointId: string,
  checkpointLabel: string,
  leaderRiderId: string,
  dependencies: CheckpointHandlerDependencies,
): Promise<void> {
  const notifier = dependencies.pushNotifier;
  if (notifier == null) {
    return;
  }

  try {
    await notifier.notify({
      eventKey: `checkpoint-release:${routePlanId}:${checkpointId}`,
      rideId,
      kind: 'checkpoint_released',
      title: 'Checkpoint dilepas',
      body: `${checkpointLabel}: rombongan dapat melanjutkan Ride.`,
      data: {
        type: 'ride.checkpoint_released',
        rideId,
        routePlanId,
        checkpointId,
      },
      excludeRiderId: leaderRiderId,
    });
  } catch {
    // Checkpoint release persistence remains authoritative.
  }
}

async function buildCheckpointView(
  rideId: string,
  currentRiderId: string,
  routePlan: RoutePlan,
  checkpointStops: readonly (
    RouteStop & {
      readonly checkpointType: NonNullable<RouteStop['checkpointType']>;
    }
  )[],
  repository: CheckpointRepository,
): Promise<RideCheckpointView> {
  const [participants, checkIns, releases] = await Promise.all([
    repository.listParticipants(rideId),
    repository.listCheckIns(rideId, routePlan.id),
    repository.listReleases(rideId, routePlan.id),
  ]);

  const releaseByCheckpoint = new Map(
    releases.map((release) => [release.checkpointId, release]),
  );
  const checkInByCheckpoint = new Map<string, Map<string, string>>();
  for (const checkIn of checkIns) {
    let byRider = checkInByCheckpoint.get(checkIn.checkpointId);
    if (byRider == null) {
      byRider = new Map<string, string>();
      checkInByCheckpoint.set(checkIn.checkpointId, byRider);
    }
    byRider.set(checkIn.riderId, checkIn.checkedInAt);
  }

  const firstUnreleasedIndex = checkpointStops.findIndex(
    (stop) => !releaseByCheckpoint.has(stop.id),
  );

  const checkpoints: RideCheckpointItem[] = checkpointStops.map(
    (stop, index) => {
      const release = releaseByCheckpoint.get(stop.id) ?? null;
      const checkInByRider =
        checkInByCheckpoint.get(stop.id) ?? new Map<string, string>();

      const participantViews = participants.map((participant) => ({
        riderId: participant.riderId,
        displayName: participant.displayName,
        role: participant.role,
        membershipStatus: participant.membershipStatus,
        checkedInAt: checkInByRider.get(participant.riderId) ?? null,
      }));

      const checkedInCount = participantViews.filter(
        (participant) => participant.checkedInAt != null,
      ).length;

      return {
        checkpointId: stop.id,
        sequence: stop.sequence,
        label: stop.label,
        formattedAddress: stop.formattedAddress,
        latitude: stop.location.latitude,
        longitude: stop.location.longitude,
        checkpointType: stop.checkpointType,
        plannedDurationMinutes: stop.plannedDurationMinutes,
        state:
          release != null
            ? 'released'
            : index === firstUnreleasedIndex
              ? 'current'
              : 'upcoming',
        expectedCount: participantViews.length,
        checkedInCount,
        missingCount: participantViews.length - checkedInCount,
        currentRiderCheckedIn: checkInByRider.has(currentRiderId),
        releasedAt: release?.releasedAt ?? null,
        participants: participantViews,
      };
    },
  );

  return {
    rideId,
    routePlanId: routePlan.id,
    routePlanRevision: routePlan.revision,
    checkpoints,
  };
}

function matchCheckpointRoute(pathname: string): CheckpointRoute | null {
  const listMatch = /^\/v1\/rides\/([^/]+)\/checkpoints$/.exec(pathname);
  if (listMatch != null) {
    return {
      kind: 'list',
      rideId: decodeURIComponent(listMatch[1]),
    };
  }

  const actionMatch =
    /^\/v1\/rides\/([^/]+)\/checkpoints\/([^/]+)\/(check-in|release)$/.exec(
      pathname,
    );
  if (actionMatch == null) {
    return null;
  }

  return {
    kind: actionMatch[3] === 'check-in' ? 'check_in' : 'release',
    rideId: decodeURIComponent(actionMatch[1]),
    checkpointId: decodeURIComponent(actionMatch[2]),
  };
}
