import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { ClubOwnershipRepository } from './repository';

export interface ClubOwnershipHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubOwnershipRepository: ClubOwnershipRepository;
  readonly now?: () => Date;
}

const MEMBERS_PATH = /^\/v1\/clubs\/([^/]+)\/members$/;
const OWNER_PATH = /^\/v1\/clubs\/([^/]+)\/owner$/;

export function isClubOwnershipPath(pathname: string): boolean {
  return MEMBERS_PATH.test(pathname) || OWNER_PATH.test(pathname);
}

export async function handleClubOwnershipRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: ClubOwnershipHandlerDependencies,
): Promise<Response> {
  const membersMatch = MEMBERS_PATH.exec(url.pathname);
  const ownerMatch = OWNER_PATH.exec(url.pathname);
  const expectedMethod = membersMatch != null ? 'GET' : 'POST';
  if (request.method !== expectedMethod) {
    return errorResponse(
      'method_not_allowed',
      `Only ${expectedMethod} is supported for this endpoint.`,
      405,
      requestId,
    );
  }

  const authenticated = await authenticateRider(
    request,
    dependencies.identityVerifier,
    dependencies.riderRepository,
  );
  if ('error' in authenticated) {
    return errorResponse(
      authenticated.error,
      authenticated.message,
      authenticated.status,
      requestId,
    );
  }

  const rider = authenticated.rider;
  const clubId = decodeURIComponent((membersMatch ?? ownerMatch)![1]!);
  const repository = dependencies.clubOwnershipRepository;
  const requesterRole = await repository.findActiveRole(clubId, rider.id);

  if (membersMatch != null) {
    if (requesterRole == null) {
      return errorResponse(
        'club_membership_required',
        'An active Club membership is required.',
        403,
        requestId,
      );
    }

    const members = await repository.listActiveMembers(clubId);
    return jsonResponse({ members }, 200, requestId);
  }

  if (requesterRole !== 'owner') {
    return errorResponse(
      'club_owner_required',
      'Only the active Club owner can transfer ownership.',
      403,
      requestId,
    );
  }

  const targetRiderId = await readTargetRiderId(request);
  if (targetRiderId == null) {
    return errorResponse(
      'invalid_club_owner',
      'riderId must be a non-empty string.',
      400,
      requestId,
    );
  }
  if (targetRiderId === rider.id) {
    return errorResponse(
      'invalid_club_owner',
      'Choose another active member as the new owner.',
      400,
      requestId,
    );
  }

  const targetRole = await repository.findActiveRole(clubId, targetRiderId);
  if (targetRole == null) {
    return errorResponse(
      'club_member_not_found',
      'The new owner must be an active member of this Club.',
      404,
      requestId,
    );
  }

  await repository.transferOwnership(
    clubId,
    rider.id,
    targetRiderId,
    (dependencies.now?.() ?? new Date()).toISOString(),
  );

  const members = await repository.listActiveMembers(clubId);
  return jsonResponse({ members }, 200, requestId);
}

async function readTargetRiderId(request: Request): Promise<string | null> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return null;
  }

  if (typeof body !== 'object' || body == null) {
    return null;
  }

  const riderId = (body as Record<string, unknown>).riderId;
  return typeof riderId === 'string' && riderId.trim().length > 0
    ? riderId.trim()
    : null;
}
