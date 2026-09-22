import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { ActiveRideGateway } from '../active-ride/gateway';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse, jsonResponse } from '../http/json';
import type {
  GeoPoint,
  RouteManeuver,
  RouteTravelMode,
} from '../maps/models';
import type { RiderRepository } from '../riders/rider-repository';
import type {
  CheckpointType,
  SaveRoutePlanInput,
  SaveRouteStopInput,
  StopType,
} from './models';
import type { RoutePlanRepository } from './repository';

const MAX_ROUTE_STOPS = 10;

export interface RoutePlanHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly routePlanRepository: RoutePlanRepository;
  readonly activeRideGateway?: ActiveRideGateway;
  readonly idFactory?: () => string;
}

export function isRoutePlanPath(pathname: string): boolean {
  return matchRoutePlanPath(pathname) != null;
}

export async function handleRoutePlanRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: RoutePlanHandlerDependencies,
): Promise<Response | null> {
  const rideId = matchRoutePlanPath(url.pathname);
  if (rideId == null) {
    return null;
  }

  if (request.method !== 'GET' && request.method !== 'PUT') {
    return errorResponse(
      'method_not_allowed',
      'Only GET and PUT are supported for this endpoint.',
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

  const membership = await dependencies.clubRideRepository.findRideMembership(
    rideId,
    rider.id,
  );

  const joinedParticipant =
    membership != null &&
    membership.status !== 'invited' &&
    membership.status !== 'left';

  if (!joinedParticipant) {
    return errorResponse(
      'ride_membership_required',
      'A joined Ride membership is required to access the RoutePlan.',
      403,
      requestId,
    );
  }

  if (request.method === 'GET') {
    const routePlan = await dependencies.routePlanRepository.findCurrent(
      rideId,
    );
    if (routePlan == null) {
      return errorResponse(
        'route_plan_not_found',
        'This Ride does not have a saved RoutePlan yet.',
        404,
        requestId,
      );
    }

    return jsonResponse({ routePlan }, 200, requestId);
  }

  const canReplacePreRide =
    membership.role === 'leader' &&
    (ride.status === 'draft' || ride.status === 'published');
  const canReplaceActive =
    ride.status === 'active' &&
    (membership.role === 'leader' || membership.role === 'navigator');

  if (!canReplacePreRide && !canReplaceActive) {
    if (ride.status === 'completed' || ride.status === 'cancelled') {
      return errorResponse(
        'ride_state_conflict',
        'RoutePlan replacement is unavailable after the Ride is completed or cancelled.',
        409,
        requestId,
      );
    }

    return errorResponse(
      'ride_route_manager_required',
      ride.status === 'active'
        ? 'The Ride Leader or Navigator role is required to revise an Active Ride RoutePlan.'
        : 'The Ride Leader role is required to replace the pre-Ride RoutePlan.',
      403,
      requestId,
    );
  }

  const inputResult = await readRoutePlanInput(
    request,
    rideId,
    rider.id,
    dependencies,
  );
  if ('error' in inputResult) {
    return errorResponse(
      'invalid_route_plan',
      inputResult.error,
      400,
      requestId,
    );
  }

  const routePlan = await dependencies.routePlanRepository.replaceCurrent(
    inputResult.value,
  );

  let activeRideBroadcast: boolean | null = null;
  if (ride.status === 'active') {
    activeRideBroadcast = false;
    try {
      await dependencies.activeRideGateway?.routePlanUpdated?.({
        rideId,
        revision: routePlan.revision,
        updatedByRiderId: rider.id,
        updatedByRole: membership.role,
      });
      activeRideBroadcast =
        dependencies.activeRideGateway?.routePlanUpdated != null;
    } catch {
      // The D1 revision is already authoritative. Return the persisted plan
      // and expose degraded realtime delivery rather than fabricating rollback.
      activeRideBroadcast = false;
    }
  }

  return jsonResponse(
    {
      routePlan,
      ...(activeRideBroadcast == null ? {} : { activeRideBroadcast }),
    },
    200,
    requestId,
  );
}

async function readRoutePlanInput(
  request: Request,
  rideId: string,
  riderId: string,
  dependencies: RoutePlanHandlerDependencies,
): Promise<{ value: SaveRoutePlanInput } | { error: string }> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return { error: 'Request body must be valid JSON.' };
  }

  if (!isRecord(body)) {
    return { error: 'Request body must be a JSON object.' };
  }

  const travelMode = parseTravelMode(body.travelMode);
  const origin = routeEndpoint(body.origin);
  const destination = routeEndpoint(body.destination);
  const distanceMeters = nonNegativeInteger(body.distanceMeters);
  const durationSeconds = nonNegativeInteger(body.durationSeconds);
  const encodedPolyline = requiredString(body.encodedPolyline, 1, 200000);
  const maneuvers = parseManeuvers(body.maneuvers);

  if (
    travelMode == null ||
    origin == null ||
    destination == null ||
    distanceMeters == null ||
    durationSeconds == null ||
    encodedPolyline == null ||
    maneuvers == null
  ) {
    return {
      error:
        'RoutePlan requires valid endpoints, travel mode, route summary, and encoded polyline.',
    };
  }

  if (!Array.isArray(body.stops)) {
    return { error: 'stops must be an array.' };
  }

  if (body.stops.length > MAX_ROUTE_STOPS) {
    return {
      error: 'The MVP supports at most 10 intermediate stops.',
    };
  }

  const stops: SaveRouteStopInput[] = [];
  for (const [sequence, rawStop] of body.stops.entries()) {
    const stop = parseStop(rawStop, sequence, dependencies);
    if (stop == null) {
      return {
        error: `Stop at sequence ${sequence} is invalid.`,
      };
    }
    stops.push(stop);
  }

  return {
    value: {
      id: makeId(dependencies),
      rideId,
      createdByRiderId: riderId,
      travelMode,
      originLabel: origin.label,
      origin: origin.location,
      destinationLabel: destination.label,
      destination: destination.location,
      distanceMeters,
      durationSeconds,
      encodedPolyline,
      maneuvers,
      stops,
    },
  };
}

function parseManeuvers(value: unknown): RouteManeuver[] | null {
  if (value == null) {
    // Backward compatible while existing pilot clients are upgraded.
    return [];
  }
  if (!Array.isArray(value) || value.length > 500) {
    return null;
  }

  const maneuvers: RouteManeuver[] = [];
  for (const raw of value) {
    if (!isRecord(raw)) return null;
    const instruction = requiredString(raw.instruction, 1, 500);
    const type = optionalString(raw.type, 100);
    const distanceMeters = nonNegativeInteger(raw.distanceMeters);
    const durationSeconds = nonNegativeInteger(raw.durationSeconds);
    const beginShapeIndex = nonNegativeInteger(raw.beginShapeIndex);
    const endShapeIndex = nonNegativeInteger(raw.endShapeIndex);
    const verbalPreTransitionInstruction = optionalString(
      raw.verbalPreTransitionInstruction,
      500,
    );
    const verbalTransitionInstruction = optionalString(
      raw.verbalTransitionInstruction,
      500,
    );
    const verbalPostTransitionInstruction = optionalString(
      raw.verbalPostTransitionInstruction,
      500,
    );

    if (
      instruction == null ||
      type === undefined ||
      distanceMeters == null ||
      durationSeconds == null ||
      beginShapeIndex == null ||
      endShapeIndex == null ||
      endShapeIndex < beginShapeIndex ||
      verbalPreTransitionInstruction === undefined ||
      verbalTransitionInstruction === undefined ||
      verbalPostTransitionInstruction === undefined
    ) {
      return null;
    }

    maneuvers.push({
      instruction,
      type,
      distanceMeters,
      durationSeconds,
      beginShapeIndex,
      endShapeIndex,
      verbalPreTransitionInstruction,
      verbalTransitionInstruction,
      verbalPostTransitionInstruction,
    });
  }
  return maneuvers;
}

function routeEndpoint(
  value: unknown,
): { label: string | null; location: GeoPoint } | null {
  if (!isRecord(value)) {
    return null;
  }

  const label = optionalString(value.label, 240);
  const location = point(value.location);
  if (label === undefined || location == null) {
    return null;
  }

  return { label, location };
}

function parseStop(
  value: unknown,
  sequence: number,
  dependencies: RoutePlanHandlerDependencies,
): SaveRouteStopInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const label = requiredString(value.label, 1, 200);
  const formattedAddress = optionalString(value.formattedAddress, 500);
  const location = point(value.location);
  const stopType = parseStopType(value.stopType);
  const checkpointType = parseCheckpointType(value.checkpointType);
  const plannedDurationMinutes = optionalInteger(
    value.plannedDurationMinutes,
    0,
    1440,
  );

  if (
    label == null ||
    formattedAddress === undefined ||
    location == null ||
    stopType == null ||
    checkpointType === undefined ||
    plannedDurationMinutes === undefined
  ) {
    return null;
  }

  return {
    id: makeId(dependencies),
    sequence,
    label,
    formattedAddress,
    location,
    stopType,
    checkpointType,
    plannedDurationMinutes,
  };
}

function point(value: unknown): GeoPoint | null {
  if (!isRecord(value)) {
    return null;
  }

  const latitude = value.latitude;
  const longitude = value.longitude;
  if (
    typeof latitude !== 'number' ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    typeof longitude !== 'number' ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }

  return { latitude, longitude };
}

function parseTravelMode(value: unknown): RouteTravelMode | null {
  return value === 'drive' || value === 'two_wheeler' ? value : null;
}

function parseStopType(value: unknown): StopType | null {
  return value === 'generic' ||
    value === 'fuel' ||
    value === 'rest' ||
    value === 'meal' ||
    value === 'hotel' ||
    value === 'custom'
    ? value
    : null;
}

function parseCheckpointType(
  value: unknown,
): CheckpointType | null | undefined {
  if (value == null) {
    return null;
  }

  return value === 'stop' ||
    value === 'fuel' ||
    value === 'rest' ||
    value === 'meal' ||
    value === 'regroup' ||
    value === 'mandatory_regroup' ||
    value === 'hotel' ||
    value === 'custom' ||
    value === 'finish'
    ? value
    : undefined;
}

function nonNegativeInteger(value: unknown): number | null {
  return typeof value === 'number' &&
    Number.isInteger(value) &&
    value >= 0
    ? value
    : null;
}

function optionalInteger(
  value: unknown,
  min: number,
  max: number,
): number | null | undefined {
  if (value == null) {
    return null;
  }

  return typeof value === 'number' &&
    Number.isInteger(value) &&
    value >= min &&
    value <= max
    ? value
    : undefined;
}

function requiredString(
  value: unknown,
  minLength: number,
  maxLength: number,
): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim();
  return normalized.length >= minLength && normalized.length <= maxLength
    ? normalized
    : null;
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

function matchRoutePlanPath(pathname: string): string | null {
  const match = /^\/v1\/rides\/([^/]+)\/route-plan$/.exec(pathname);
  return match?.[1] == null ? null : decodeURIComponent(match[1]);
}

function makeId(dependencies: RoutePlanHandlerDependencies): string {
  return dependencies.idFactory?.() ?? crypto.randomUUID();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
