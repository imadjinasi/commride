import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { RidePushNotifier } from '../push/notifier';
import type { RoutePlanRepository } from '../route-plans/repository';
import type {
  PublishRideBriefingInput,
  RideBriefingView,
} from './models';
import type { RideBriefingRepository } from './repository';

export interface RideBriefingHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly routePlanRepository: RoutePlanRepository;
  readonly rideBriefingRepository: RideBriefingRepository;
  readonly pushNotifier?: RidePushNotifier;
  readonly idFactory?: () => string;
  readonly now?: () => Date;
}

type BriefingAction = 'read' | 'publish' | 'acknowledge';

interface BriefingPathMatch {
  readonly rideId: string;
  readonly action: BriefingAction;
}

export function isRideBriefingPath(pathname: string): boolean {
  return matchBriefingPath(pathname) != null;
}

export async function handleRideBriefingRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: RideBriefingHandlerDependencies,
): Promise<Response | null> {
  const path = matchBriefingPath(url.pathname);
  if (path == null) {
    return null;
  }

  const expectedMethod = path.action === 'read' ? 'GET' : 'POST';
  if (request.method !== expectedMethod) {
    return errorResponse(
      'method_not_allowed',
      `Only ${expectedMethod} is supported for this endpoint.`,
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
    rider.id,
  );
  const joinedParticipant =
    membership != null &&
    membership.status !== 'invited' &&
    membership.status !== 'left';

  if (!joinedParticipant) {
    return errorResponse(
      'ride_membership_required',
      'A joined Ride membership is required to access the Briefing.',
      403,
      requestId,
    );
  }

  if (path.action === 'read') {
    const view = await buildCurrentView(
      path.rideId,
      rider.id,
      dependencies,
    );
    if (view == null) {
      return errorResponse(
        'briefing_not_found',
        'This Ride does not have a published Briefing yet.',
        404,
        requestId,
      );
    }

    return jsonResponse({ briefingView: view }, 200, requestId);
  }

  if (path.action === 'publish') {
    if (membership.role !== 'leader') {
      return errorResponse(
        'ride_leader_required',
        'The Ride Leader role is required to publish the Briefing.',
        403,
        requestId,
      );
    }

    if (ride.status !== 'draft' && ride.status !== 'published') {
      return errorResponse(
        'ride_state_conflict',
        'A Briefing can only be published while the Ride is Draft or Published.',
        409,
        requestId,
      );
    }

    const routePlan = await dependencies.routePlanRepository.findCurrent(
      path.rideId,
    );
    if (routePlan == null) {
      return errorResponse(
        'route_plan_required',
        'Save a valid RoutePlan before publishing the Briefing.',
        409,
        requestId,
      );
    }

    const roles =
      await dependencies.rideBriefingRepository.resolveRoleSnapshot(
        path.rideId,
      );
    if (roles == null || roles.leader.riderId !== rider.id) {
      return errorResponse(
        'briefing_roles_invalid',
        'The Ride does not have a valid current Leader role.',
        409,
        requestId,
      );
    }

    const notesResult = await readPublishNotes(request);
    if ('error' in notesResult) {
      return errorResponse(
        'invalid_briefing',
        notesResult.error,
        400,
        requestId,
      );
    }

    const publishedAt = (
      dependencies.now?.() ?? new Date()
    ).toISOString();

    const input: PublishRideBriefingInput = {
      id: dependencies.idFactory?.() ?? crypto.randomUUID(),
      rideId: path.rideId,
      routePlanId: routePlan.id,
      createdByRiderId: rider.id,
      scheduledStartAt: ride.scheduledStartAt,
      roles,
      notes: notesResult.notes,
      publishedAt,
    };

    await dependencies.rideBriefingRepository.publish(input);

    const view = await buildCurrentView(
      path.rideId,
      rider.id,
      dependencies,
    );
    if (view == null) {
      return errorResponse(
        'briefing_not_persisted',
        'The Briefing revision could not be loaded after publication.',
        500,
        requestId,
      );
    }

    await notifyBriefingBestEffort(
      view.briefing.id,
      path.rideId,
      rider.id,
      ride.title,
      dependencies,
    );

    return jsonResponse({ briefingView: view }, 200, requestId);
  }

  if (ride.status !== 'draft' && ride.status !== 'published') {
    return errorResponse(
      'ride_state_conflict',
      'Briefing readiness is only tracked before the Ride becomes Active.',
      409,
      requestId,
    );
  }

  const briefing =
    await dependencies.rideBriefingRepository.findCurrent(path.rideId);
  if (briefing == null) {
    return errorResponse(
      'briefing_not_found',
      'This Ride does not have a published Briefing yet.',
      404,
      requestId,
    );
  }

  const currentRoutePlan =
    await dependencies.routePlanRepository.findCurrent(path.rideId);
  if (
    currentRoutePlan == null ||
    currentRoutePlan.id !== briefing.routePlanId
  ) {
    return errorResponse(
      'briefing_stale',
      'The RoutePlan changed after this Briefing was published. The Leader must publish a new Briefing.',
      409,
      requestId,
    );
  }

  const acknowledgedAt = (
    dependencies.now?.() ?? new Date()
  ).toISOString();

  await dependencies.rideBriefingRepository.acknowledge(
    briefing.id,
    rider.id,
    acknowledgedAt,
  );

  const view = await buildCurrentView(
    path.rideId,
    rider.id,
    dependencies,
  );
  if (view == null) {
    return errorResponse(
      'briefing_not_found',
      'The current Briefing is no longer available.',
      404,
      requestId,
    );
  }

  return jsonResponse({ briefingView: view }, 200, requestId);
}

async function notifyBriefingBestEffort(
  briefingId: string,
  rideId: string,
  leaderRiderId: string,
  rideTitle: string,
  dependencies: RideBriefingHandlerDependencies,
): Promise<void> {
  const notifier = dependencies.pushNotifier;
  if (notifier == null) {
    return;
  }

  try {
    await notifier.notify({
      eventKey: `briefing:${briefingId}`,
      rideId,
      kind: 'briefing_published',
      title: 'Ride Briefing diperbarui',
      body: `${rideTitle}: briefing terbaru siap dibaca.`,
      data: {
        type: 'ride.briefing_published',
        rideId,
        briefingId,
      },
      excludeRiderId: leaderRiderId,
    });
  } catch {
    // Briefing persistence remains authoritative.
  }
}

async function buildCurrentView(
  rideId: string,
  currentRiderId: string,
  dependencies: RideBriefingHandlerDependencies,
): Promise<RideBriefingView | null> {
  const briefing =
    await dependencies.rideBriefingRepository.findCurrent(rideId);
  if (briefing == null) {
    return null;
  }

  const routePlan = await dependencies.routePlanRepository.findById(
    briefing.routePlanId,
  );
  if (routePlan == null) {
    throw new Error('Briefing references a missing RoutePlan revision.');
  }

  const currentRoutePlan =
    await dependencies.routePlanRepository.findCurrent(rideId);
  const readiness =
    await dependencies.rideBriefingRepository.getReadiness(
      rideId,
      briefing.id,
      currentRiderId,
    );

  return {
    briefing,
    routePlan,
    readiness,
    routePlanIsCurrent: currentRoutePlan?.id === routePlan.id,
  };
}

async function readPublishNotes(
  request: Request,
): Promise<{ notes: string | null } | { error: string }> {
  const raw = await request.text();
  if (raw.trim().length === 0) {
    return { notes: null };
  }

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return { error: 'Request body must be valid JSON.' };
  }

  if (!isRecord(body)) {
    return { error: 'Request body must be a JSON object.' };
  }

  const notes = optionalString(body.notes, 4000);
  if (notes === undefined) {
    return { error: 'notes must be null or a non-empty string up to 4000 characters.' };
  }

  return { notes };
}

function optionalString(
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

function matchBriefingPath(pathname: string): BriefingPathMatch | null {
  const read = /^\/v1\/rides\/([^/]+)\/briefing$/.exec(pathname);
  if (read?.[1] != null) {
    return {
      rideId: decodeURIComponent(read[1]),
      action: 'read',
    };
  }

  const publish =
    /^\/v1\/rides\/([^/]+)\/briefing\/publish$/.exec(pathname);
  if (publish?.[1] != null) {
    return {
      rideId: decodeURIComponent(publish[1]),
      action: 'publish',
    };
  }

  const acknowledge =
    /^\/v1\/rides\/([^/]+)\/briefing\/acknowledge$/.exec(
      pathname,
    );
  if (acknowledge?.[1] != null) {
    return {
      rideId: decodeURIComponent(acknowledge[1]),
      action: 'acknowledge',
    };
  }

  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
