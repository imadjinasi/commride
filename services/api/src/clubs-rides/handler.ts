import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderProfile } from '../riders/rider-profile';
import type { RiderRepository } from '../riders/rider-repository';
import type {
  ClubMembership,
  Ride,
  RideMembership,
  RideRole,
  RideStatus,
} from './models';
import type { ClubRideRepository } from './repository';

export interface ClubRideHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly idFactory?: () => string;
  readonly now?: () => Date;
}

interface ClubInput {
  readonly name: string;
  readonly slug: string;
  readonly homeArea: string | null;
  readonly visibility: 'private' | 'unlisted' | 'public';
}

interface ClubInvitationInput {
  readonly riderId: string;
  readonly role: 'admin' | 'member';
}

interface RideInput {
  readonly title: string;
  readonly scheduledStartAt: string | null;
  readonly notes: string | null;
}

interface RideInvitationInput {
  readonly riderId: string;
  readonly role: Exclude<RideRole, 'leader'>;
}

export function isClubRideRequestPath(pathname: string): boolean {
  return matchRoute(pathname) != null;
}

export async function handleClubRideRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: ClubRideHandlerDependencies,
): Promise<Response | null> {
  const route = matchRoute(url.pathname);
  if (route == null) {
    return null;
  }

  if (request.method !== 'POST') {
    return errorResponse(
      'method_not_allowed',
      'Only POST is supported for this endpoint.',
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

  switch (route.kind) {
    case 'create_club':
      return createClub(request, requestId, rider, dependencies);
    case 'invite_club_member':
      return inviteClubMember(
        request,
        requestId,
        route.clubId,
        rider,
        dependencies,
      );
    case 'join_club':
      return joinClub(requestId, route.clubId, rider, dependencies);
    case 'create_ride':
      return createRide(
        request,
        requestId,
        route.clubId,
        rider,
        dependencies,
      );
    case 'invite_ride_member':
      return inviteRideMember(
        request,
        requestId,
        route.rideId,
        rider,
        dependencies,
      );
    case 'join_ride':
      return joinRide(requestId, route.rideId, rider, dependencies);
    case 'publish_ride':
      return transitionRide(
        requestId,
        route.rideId,
        rider,
        dependencies,
        'draft',
        'published',
      );
    case 'start_ride':
      return transitionRide(
        requestId,
        route.rideId,
        rider,
        dependencies,
        'published',
        'active',
      );
    case 'end_ride':
      return transitionRide(
        requestId,
        route.rideId,
        rider,
        dependencies,
        'active',
        'completed',
      );
  }
}

async function createClub(
  request: Request,
  requestId: string,
  rider: RiderProfile,
  dependencies: ClubRideHandlerDependencies,
): Promise<Response> {
  const inputResult = await readClubInput(request);
  if ('error' in inputResult) {
    return errorResponse(
      'invalid_club',
      inputResult.error,
      400,
      requestId,
    );
  }

  const club = await dependencies.clubRideRepository.createClubWithOwner({
    clubId: makeId(dependencies),
    creatorRiderId: rider.id,
    name: inputResult.value.name,
    slug: inputResult.value.slug,
    homeArea: inputResult.value.homeArea,
    visibility: inputResult.value.visibility,
  });

  return jsonResponse({ club }, 201, requestId);
}

async function inviteClubMember(
  request: Request,
  requestId: string,
  clubId: string,
  rider: RiderProfile,
  dependencies: ClubRideHandlerDependencies,
): Promise<Response> {
  const authorization = await requireClubAdmin(
    clubId,
    rider.id,
    dependencies.clubRideRepository,
  );
  if (authorization != null) {
    return errorResponse(
      authorization.code,
      authorization.message,
      authorization.status,
      requestId,
    );
  }

  const inputResult = await readClubInvitationInput(request);
  if ('error' in inputResult) {
    return errorResponse(
      'invalid_club_invitation',
      inputResult.error,
      400,
      requestId,
    );
  }

  const target = await dependencies.riderRepository.findById(
    inputResult.value.riderId,
  );
  if (target == null) {
    return errorResponse(
      'rider_not_found',
      'The invited Rider does not exist.',
      404,
      requestId,
    );
  }

  const existing = await dependencies.clubRideRepository.findClubMembership(
    clubId,
    target.id,
  );
  if (existing?.status === 'active') {
    return errorResponse(
      'club_membership_conflict',
      'The Rider is already an active Club member.',
      409,
      requestId,
    );
  }

  const membership = await dependencies.clubRideRepository.inviteClubMember(
    clubId,
    target.id,
    inputResult.value.role,
  );

  return jsonResponse({ membership }, 200, requestId);
}

async function joinClub(
  requestId: string,
  clubId: string,
  rider: RiderProfile,
  dependencies: ClubRideHandlerDependencies,
): Promise<Response> {
  const existing = await dependencies.clubRideRepository.findClubMembership(
    clubId,
    rider.id,
  );

  if (existing == null || existing.status === 'left') {
    return errorResponse(
      'club_invitation_required',
      'An active Club invitation is required to join.',
      409,
      requestId,
    );
  }

  if (existing.status === 'active') {
    return jsonResponse({ membership: existing }, 200, requestId);
  }

  const membership = await dependencies.clubRideRepository.acceptClubInvite(
    clubId,
    rider.id,
  );

  if (membership == null || membership.status !== 'active') {
    return errorResponse(
      'club_invitation_required',
      'An active Club invitation is required to join.',
      409,
      requestId,
    );
  }

  return jsonResponse({ membership }, 200, requestId);
}

async function createRide(
  request: Request,
  requestId: string,
  clubId: string,
  rider: RiderProfile,
  dependencies: ClubRideHandlerDependencies,
): Promise<Response> {
  const authorization = await requireClubAdmin(
    clubId,
    rider.id,
    dependencies.clubRideRepository,
  );
  if (authorization != null) {
    return errorResponse(
      authorization.code,
      authorization.message,
      authorization.status,
      requestId,
    );
  }

  const inputResult = await readRideInput(request);
  if ('error' in inputResult) {
    return errorResponse(
      'invalid_ride',
      inputResult.error,
      400,
      requestId,
    );
  }

  const ride = await dependencies.clubRideRepository.createRideWithLeader({
    rideId: makeId(dependencies),
    clubId,
    creatorRiderId: rider.id,
    title: inputResult.value.title,
    scheduledStartAt: inputResult.value.scheduledStartAt,
    notes: inputResult.value.notes,
  });

  return jsonResponse({ ride }, 201, requestId);
}

async function inviteRideMember(
  request: Request,
  requestId: string,
  rideId: string,
  rider: RiderProfile,
  dependencies: ClubRideHandlerDependencies,
): Promise<Response> {
  const leaderAuthorization = await requireRideLeader(
    rideId,
    rider.id,
    dependencies.clubRideRepository,
  );
  if (leaderAuthorization != null) {
    return errorResponse(
      leaderAuthorization.code,
      leaderAuthorization.message,
      leaderAuthorization.status,
      requestId,
    );
  }

  const ride = await dependencies.clubRideRepository.findRide(rideId);
  if (ride == null) {
    return errorResponse(
      'ride_not_found',
      'The Ride does not exist.',
      404,
      requestId,
    );
  }

  if (ride.status === 'completed' || ride.status === 'cancelled') {
    return errorResponse(
      'ride_state_conflict',
      'Completed or cancelled Rides cannot receive invitations.',
      409,
      requestId,
    );
  }

  const inputResult = await readRideInvitationInput(request);
  if ('error' in inputResult) {
    return errorResponse(
      'invalid_ride_invitation',
      inputResult.error,
      400,
      requestId,
    );
  }

  const target = await dependencies.riderRepository.findById(
    inputResult.value.riderId,
  );
  if (target == null) {
    return errorResponse(
      'rider_not_found',
      'The invited Rider does not exist.',
      404,
      requestId,
    );
  }

  const existing = await dependencies.clubRideRepository.findRideMembership(
    rideId,
    target.id,
  );
  if (
    existing != null &&
    existing.status !== 'invited' &&
    existing.status !== 'left'
  ) {
    return errorResponse(
      'ride_membership_conflict',
      'The Rider already participates in this Ride.',
      409,
      requestId,
    );
  }

  const membership = await dependencies.clubRideRepository.inviteRideMember(
    rideId,
    target.id,
    inputResult.value.role,
  );

  return jsonResponse({ membership }, 200, requestId);
}

async function joinRide(
  requestId: string,
  rideId: string,
  rider: RiderProfile,
  dependencies: ClubRideHandlerDependencies,
): Promise<Response> {
  const ride = await dependencies.clubRideRepository.findRide(rideId);
  if (ride == null) {
    return errorResponse(
      'ride_not_found',
      'The Ride does not exist.',
      404,
      requestId,
    );
  }

  if (ride.status === 'completed' || ride.status === 'cancelled') {
    return errorResponse(
      'ride_state_conflict',
      'This Ride no longer accepts participants.',
      409,
      requestId,
    );
  }

  const existing = await dependencies.clubRideRepository.findRideMembership(
    rideId,
    rider.id,
  );

  if (existing == null || existing.status === 'left') {
    return errorResponse(
      'ride_invitation_required',
      'An active Ride invitation is required to join.',
      409,
      requestId,
    );
  }

  if (existing.status !== 'invited') {
    return jsonResponse({ membership: existing }, 200, requestId);
  }

  const membership = await dependencies.clubRideRepository.acceptRideInvite(
    rideId,
    rider.id,
  );

  if (membership == null || membership.status === 'invited') {
    return errorResponse(
      'ride_invitation_required',
      'An active Ride invitation is required to join.',
      409,
      requestId,
    );
  }

  return jsonResponse({ membership }, 200, requestId);
}

async function transitionRide(
  requestId: string,
  rideId: string,
  rider: RiderProfile,
  dependencies: ClubRideHandlerDependencies,
  expectedStatus: RideStatus,
  nextStatus: RideStatus,
): Promise<Response> {
  const leaderAuthorization = await requireRideLeader(
    rideId,
    rider.id,
    dependencies.clubRideRepository,
  );
  if (leaderAuthorization != null) {
    return errorResponse(
      leaderAuthorization.code,
      leaderAuthorization.message,
      leaderAuthorization.status,
      requestId,
    );
  }

  const current = await dependencies.clubRideRepository.findRide(rideId);
  if (current == null) {
    return errorResponse(
      'ride_not_found',
      'The Ride does not exist.',
      404,
      requestId,
    );
  }

  if (current.status === nextStatus) {
    return jsonResponse({ ride: current }, 200, requestId);
  }

  if (current.status !== expectedStatus) {
    return errorResponse(
      'ride_state_conflict',
      `Ride must be ${expectedStatus} before it can become ${nextStatus}.`,
      409,
      requestId,
    );
  }

  const timestamp = (dependencies.now?.() ?? new Date()).toISOString();
  const updated = await dependencies.clubRideRepository.transitionRideStatus(
    rideId,
    expectedStatus,
    nextStatus,
    timestamp,
  );

  if (updated == null) {
    return errorResponse(
      'ride_not_found',
      'The Ride does not exist.',
      404,
      requestId,
    );
  }

  if (updated.status !== nextStatus) {
    return errorResponse(
      'ride_state_conflict',
      'The Ride changed state before this operation completed.',
      409,
      requestId,
    );
  }

  return jsonResponse({ ride: updated }, 200, requestId);
}

type AuthorizationFailure = {
  readonly code: 'club_admin_required' | 'ride_leader_required';
  readonly message: string;
  readonly status: 403;
};

async function requireClubAdmin(
  clubId: string,
  riderId: string,
  repository: ClubRideRepository,
): Promise<AuthorizationFailure | null> {
  const membership = await repository.findClubMembership(clubId, riderId);
  const authorized =
    membership?.status === 'active' &&
    (membership.role === 'owner' || membership.role === 'admin');

  if (authorized) {
    return null;
  }

  return {
    code: 'club_admin_required',
    message: 'An active Club owner or admin role is required.',
    status: 403,
  };
}

async function requireRideLeader(
  rideId: string,
  riderId: string,
  repository: ClubRideRepository,
): Promise<AuthorizationFailure | null> {
  const membership = await repository.findRideMembership(rideId, riderId);
  const authorized =
    membership?.role === 'leader' &&
    membership.status !== 'invited' &&
    membership.status !== 'left';

  if (authorized) {
    return null;
  }

  return {
    code: 'ride_leader_required',
    message: 'The active Ride Leader role is required.',
    status: 403,
  };
}

async function readClubInput(
  request: Request,
): Promise<{ value: ClubInput } | { error: string }> {
  const bodyResult = await readJsonObject(request);
  if ('error' in bodyResult) {
    return bodyResult;
  }

  const name = requiredString(bodyResult.value.name, 100);
  if (name == null) {
    return { error: 'name must be between 1 and 100 characters.' };
  }

  const slug = requiredString(bodyResult.value.slug, 60);
  if (slug == null || !/^[a-z0-9][a-z0-9-]{1,59}$/.test(slug)) {
    return {
      error:
        'slug must use 2-60 lowercase letters, numbers, or hyphens.',
    };
  }

  const homeArea = optionalString(bodyResult.value.homeArea, 120);
  if (homeArea === undefined) {
    return { error: 'homeArea must be null or at most 120 characters.' };
  }

  const visibility = bodyResult.value.visibility ?? 'private';
  if (
    visibility !== 'private' &&
    visibility !== 'unlisted' &&
    visibility !== 'public'
  ) {
    return {
      error: 'visibility must be private, unlisted, or public.',
    };
  }

  return {
    value: {
      name,
      slug,
      homeArea,
      visibility,
    },
  };
}

async function readClubInvitationInput(
  request: Request,
): Promise<{ value: ClubInvitationInput } | { error: string }> {
  const bodyResult = await readJsonObject(request);
  if ('error' in bodyResult) {
    return bodyResult;
  }

  const riderId = requiredString(bodyResult.value.riderId, 128);
  if (riderId == null) {
    return { error: 'riderId is required.' };
  }

  const role = bodyResult.value.role ?? 'member';
  if (role !== 'admin' && role !== 'member') {
    return { error: 'role must be admin or member.' };
  }

  return { value: { riderId, role } };
}

async function readRideInput(
  request: Request,
): Promise<{ value: RideInput } | { error: string }> {
  const bodyResult = await readJsonObject(request);
  if ('error' in bodyResult) {
    return bodyResult;
  }

  const title = requiredString(bodyResult.value.title, 120);
  if (title == null) {
    return { error: 'title must be between 1 and 120 characters.' };
  }

  const notes = optionalString(bodyResult.value.notes, 4000);
  if (notes === undefined) {
    return { error: 'notes must be null or at most 4000 characters.' };
  }

  const scheduledStartResult = optionalIsoDate(
    bodyResult.value.scheduledStartAt,
  );
  if ('error' in scheduledStartResult) {
    return { error: scheduledStartResult.error };
  }

  return {
    value: {
      title,
      notes,
      scheduledStartAt: scheduledStartResult.value,
    },
  };
}

async function readRideInvitationInput(
  request: Request,
): Promise<{ value: RideInvitationInput } | { error: string }> {
  const bodyResult = await readJsonObject(request);
  if ('error' in bodyResult) {
    return bodyResult;
  }

  const riderId = requiredString(bodyResult.value.riderId, 128);
  if (riderId == null) {
    return { error: 'riderId is required.' };
  }

  const role = bodyResult.value.role ?? 'member';
  if (role !== 'member' && role !== 'sweeper' && role !== 'navigator') {
    return {
      error: 'role must be member, sweeper, or navigator.',
    };
  }

  return { value: { riderId, role } };
}

async function readJsonObject(
  request: Request,
): Promise<
  { value: Record<string, unknown> } | { error: string }
> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { error: 'Request body must be valid JSON.' };
  }

  if (typeof body !== 'object' || body == null || Array.isArray(body)) {
    return { error: 'Request body must be a JSON object.' };
  }

  return { value: body as Record<string, unknown> };
}

function requiredString(
  value: unknown,
  maxLength: number,
): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maxLength) {
    return null;
  }

  return normalized;
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

function optionalIsoDate(
  value: unknown,
): { value: string | null } | { error: string } {
  if (value == null) {
    return { value: null };
  }

  if (typeof value !== 'string') {
    return { error: 'scheduledStartAt must be an ISO-8601 timestamp or null.' };
  }

  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) {
    return { error: 'scheduledStartAt must be a valid ISO-8601 timestamp.' };
  }

  return { value: parsed.toISOString() };
}

function makeId(dependencies: ClubRideHandlerDependencies): string {
  return dependencies.idFactory?.() ?? crypto.randomUUID();
}

type MatchedRoute =
  | { readonly kind: 'create_club' }
  | { readonly kind: 'invite_club_member'; readonly clubId: string }
  | { readonly kind: 'join_club'; readonly clubId: string }
  | { readonly kind: 'create_ride'; readonly clubId: string }
  | { readonly kind: 'invite_ride_member'; readonly rideId: string }
  | { readonly kind: 'join_ride'; readonly rideId: string }
  | { readonly kind: 'publish_ride'; readonly rideId: string }
  | { readonly kind: 'start_ride'; readonly rideId: string }
  | { readonly kind: 'end_ride'; readonly rideId: string };

function matchRoute(pathname: string): MatchedRoute | null {
  if (pathname === '/v1/clubs') {
    return { kind: 'create_club' };
  }

  const clubInvite = /^\/v1\/clubs\/([^/]+)\/members\/invite$/.exec(
    pathname,
  );
  if (clubInvite?.[1] != null) {
    return {
      kind: 'invite_club_member',
      clubId: decodeURIComponent(clubInvite[1]),
    };
  }

  const clubJoin = /^\/v1\/clubs\/([^/]+)\/join$/.exec(pathname);
  if (clubJoin?.[1] != null) {
    return {
      kind: 'join_club',
      clubId: decodeURIComponent(clubJoin[1]),
    };
  }

  const createRide = /^\/v1\/clubs\/([^/]+)\/rides$/.exec(pathname);
  if (createRide?.[1] != null) {
    return {
      kind: 'create_ride',
      clubId: decodeURIComponent(createRide[1]),
    };
  }

  const rideInvite = /^\/v1\/rides\/([^/]+)\/members\/invite$/.exec(
    pathname,
  );
  if (rideInvite?.[1] != null) {
    return {
      kind: 'invite_ride_member',
      rideId: decodeURIComponent(rideInvite[1]),
    };
  }

  const rideAction = /^\/v1\/rides\/([^/]+)\/(join|publish|start|end)$/.exec(
    pathname,
  );
  if (rideAction?.[1] == null || rideAction[2] == null) {
    return null;
  }

  const rideId = decodeURIComponent(rideAction[1]);
  switch (rideAction[2]) {
    case 'join':
      return { kind: 'join_ride', rideId };
    case 'publish':
      return { kind: 'publish_ride', rideId };
    case 'start':
      return { kind: 'start_ride', rideId };
    case 'end':
      return { kind: 'end_ride', rideId };
    default:
      return null;
  }
}
