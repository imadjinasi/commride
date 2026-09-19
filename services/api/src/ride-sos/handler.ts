import type { ActiveRideGateway } from '../active-ride/gateway';
import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type { RidePushNotifier } from '../push/notifier';
import type {
  CreateRideSosInput,
  RideSos,
  TrustedRidePresenceSnapshot,
} from './models';
import type { RideSosRepository } from './repository';

const MAX_CLIENT_COMMAND_ID_CHARACTERS = 128;
const MAX_REASON_CHARACTERS = 500;

export interface RideSosHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly rideSosRepository: RideSosRepository;
  readonly activeRideGateway?: ActiveRideGateway;
  readonly pushNotifier?: RidePushNotifier;
  readonly idFactory?: () => string;
  readonly now?: () => Date;
}

type RideSosAction =
  | { readonly kind: 'collection'; readonly rideId: string }
  | {
      readonly kind: 'cancel' | 'resolve';
      readonly rideId: string;
      readonly sosId: string;
    };

export function isRideSosPath(pathname: string): boolean {
  return matchPath(pathname) != null;
}

export async function handleRideSosRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: RideSosHandlerDependencies,
): Promise<Response | null> {
  const path = matchPath(url.pathname);
  if (path == null) {
    return null;
  }

  const methodAllowed =
    path.kind === 'collection'
      ? request.method === 'GET' || request.method === 'POST'
      : request.method === 'POST';
  if (!methodAllowed) {
    return errorResponse(
      'method_not_allowed',
      path.kind === 'collection'
        ? 'Only GET or POST is supported for this endpoint.'
        : 'Only POST is supported for this endpoint.',
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
  if (
    membership == null ||
    membership.status === 'invited' ||
    membership.status === 'left' ||
    (ride.status === 'active' && membership.status === 'finished')
  ) {
    return errorResponse(
      'ride_membership_required',
      'A participating Ride membership is required for SOS.',
      403,
      requestId,
    );
  }

  if (path.kind === 'collection' && request.method === 'GET') {
    if (ride.status !== 'active' && ride.status !== 'completed') {
      return errorResponse(
        'ride_state_conflict',
        'SOS history is available only for Active or Completed Rides.',
        409,
        requestId,
      );
    }

    const sos = await dependencies.rideSosRepository.list(path.rideId);
    return jsonResponse({ sos }, 200, requestId);
  }

  if (ride.status !== 'active') {
    return errorResponse(
      'ride_state_conflict',
      'SOS commands are available only while the Ride is Active.',
      409,
      requestId,
    );
  }

  if (path.kind === 'collection') {
    const input = await readRaiseInput(request);
    if ('error' in input) {
      return errorResponse('invalid_sos', input.error, 400, requestId);
    }

    const existing =
      await dependencies.rideSosRepository.findByClientCommandId(
        path.rideId,
        rider.id,
        input.clientCommandId,
      );
    if (existing != null) {
      if (existing.reason !== input.reason) {
        return errorResponse(
          'sos_idempotency_conflict',
          'clientCommandId was already used for different SOS content.',
          409,
          requestId,
        );
      }
      return jsonResponse({ sos: existing }, 200, requestId);
    }

    const raisedAt = (dependencies.now?.() ?? new Date()).toISOString();
    const presence = await trustedPresenceBestEffort(
      path.rideId,
      rider.id,
      dependencies,
    );
    const createInput: CreateRideSosInput = {
      id: dependencies.idFactory?.() ?? crypto.randomUUID(),
      rideId: path.rideId,
      riderId: rider.id,
      riderDisplayName: rider.displayName,
      riderRideRole: membership.role,
      state: 'active',
      clientCommandId: input.clientCommandId,
      reason: input.reason,
      raisedAt,
      cancelledAt: null,
      resolvedAt: null,
      resolvedByRiderId: null,
      presence,
    };

    const persisted = await dependencies.rideSosRepository.create(createInput);
    if (
      persisted.riderId !== rider.id ||
      persisted.reason !== input.reason
    ) {
      return errorResponse(
        'sos_idempotency_conflict',
        'clientCommandId resolved to different persisted SOS content.',
        409,
        requestId,
      );
    }

    const createdNow = persisted.id === createInput.id;
    if (createdNow) {
      await broadcastBestEffort(
        path.rideId,
        'ride.sos_raised',
        persisted,
        dependencies,
      );
      await notifySosBestEffort(
        'raised',
        persisted,
        dependencies,
      );
    }

    return jsonResponse(
      { sos: persisted },
      createdNow ? 201 : 200,
      requestId,
    );
  }

  const existing = await dependencies.rideSosRepository.findById(
    path.rideId,
    path.sosId,
  );
  if (existing == null) {
    return errorResponse(
      'sos_not_found',
      'The SOS does not exist for this Ride.',
      404,
      requestId,
    );
  }

  if (path.kind === 'cancel') {
    if (existing.riderId !== rider.id) {
      return errorResponse(
        'sos_owner_required',
        'Only the Rider who raised this SOS may cancel it.',
        403,
        requestId,
      );
    }

    if (existing.state === 'cancelled') {
      return jsonResponse({ sos: existing }, 200, requestId);
    }
    if (existing.state !== 'active') {
      return errorResponse(
        'sos_state_conflict',
        'Only an Active SOS may be cancelled.',
        409,
        requestId,
      );
    }

    const cancelledAt = (dependencies.now?.() ?? new Date()).toISOString();
    const cancelled = await dependencies.rideSosRepository.cancel(
      path.rideId,
      path.sosId,
      cancelledAt,
    );
    if (cancelled == null) {
      return errorResponse('sos_not_found', 'The SOS does not exist.', 404, requestId);
    }
    if (cancelled.state !== 'cancelled') {
      return errorResponse(
        'sos_state_conflict',
        'The SOS changed state before cancellation completed.',
        409,
        requestId,
      );
    }

    await broadcastBestEffort(
      path.rideId,
      'ride.sos_cancelled',
      cancelled,
      dependencies,
    );
    await notifySosBestEffort('cancelled', cancelled, dependencies);
    return jsonResponse({ sos: cancelled }, 200, requestId);
  }

  if (membership.role !== 'leader') {
    return errorResponse(
      'ride_leader_required',
      'The Ride Leader role is required to resolve an SOS.',
      403,
      requestId,
    );
  }

  if (existing.state === 'resolved') {
    return jsonResponse({ sos: existing }, 200, requestId);
  }
  if (existing.state !== 'active') {
    return errorResponse(
      'sos_state_conflict',
      'Only an Active SOS may be resolved.',
      409,
      requestId,
    );
  }

  const resolvedAt = (dependencies.now?.() ?? new Date()).toISOString();
  const resolved = await dependencies.rideSosRepository.resolve(
    path.rideId,
    path.sosId,
    resolvedAt,
    rider.id,
  );
  if (resolved == null) {
    return errorResponse('sos_not_found', 'The SOS does not exist.', 404, requestId);
  }
  if (resolved.state !== 'resolved') {
    return errorResponse(
      'sos_state_conflict',
      'The SOS changed state before resolution completed.',
      409,
      requestId,
    );
  }

  await broadcastBestEffort(
    path.rideId,
    'ride.sos_resolved',
    resolved,
    dependencies,
  );
  await notifySosBestEffort('resolved', resolved, dependencies);
  return jsonResponse({ sos: resolved }, 200, requestId);
}

async function notifySosBestEffort(
  action: 'raised' | 'cancelled' | 'resolved',
  sos: RideSos,
  dependencies: RideSosHandlerDependencies,
): Promise<void> {
  const notifier = dependencies.pushNotifier;
  if (notifier == null) {
    return;
  }

  const copy = action === 'raised'
    ? {
        title: `SOS · ${sos.riderDisplayName}`,
        body: sos.reason ?? 'Rider membutuhkan bantuan pada Ride aktif.',
      }
    : action === 'resolved'
    ? {
        title: 'SOS selesai',
        body: `SOS ${sos.riderDisplayName} telah ditandai selesai.`,
      }
    : {
        title: 'SOS dibatalkan',
        body: `SOS ${sos.riderDisplayName} telah dibatalkan.`,
      };

  try {
    await notifier.notify({
      eventKey: `sos:${sos.id}:${action}`,
      rideId: sos.rideId,
      kind: `sos_${action}`,
      title: copy.title,
      body: copy.body,
      data: {
        type: `ride.sos_${action}`,
        rideId: sos.rideId,
        sosId: sos.id,
      },
      excludeRiderId: action === 'raised' ? sos.riderId : undefined,
    });
  } catch {
    // Push never changes authoritative SOS state.
  }
}

async function trustedPresenceBestEffort(
  rideId: string,
  riderId: string,
  dependencies: RideSosHandlerDependencies,
): Promise<TrustedRidePresenceSnapshot | null> {
  if (dependencies.activeRideGateway?.trustedPresence == null) {
    return null;
  }

  try {
    return await dependencies.activeRideGateway.trustedPresence(
      rideId,
      riderId,
    );
  } catch {
    return null;
  }
}

async function broadcastBestEffort(
  rideId: string,
  type: 'ride.sos_raised' | 'ride.sos_cancelled' | 'ride.sos_resolved',
  sos: RideSos,
  dependencies: RideSosHandlerDependencies,
): Promise<void> {
  if (dependencies.activeRideGateway?.sosChanged == null) {
    return;
  }

  try {
    await dependencies.activeRideGateway.sosChanged(rideId, type, sos);
  } catch {
    // D1 remains authoritative. Clients recover through GET /sos.
  }
}

async function readRaiseInput(
  request: Request,
): Promise<
  | { clientCommandId: string; reason: string | null }
  | { error: string }
> {
  let decoded: unknown;
  try {
    decoded = await request.json();
  } catch {
    return { error: 'Request body must be valid JSON.' };
  }
  if (!isRecord(decoded)) {
    return { error: 'Request body must be a JSON object.' };
  }

  const clientCommandId = boundedRequiredString(
    decoded.clientCommandId,
    MAX_CLIENT_COMMAND_ID_CHARACTERS,
  );
  if (clientCommandId == null) {
    return {
      error:
        `clientCommandId must be between 1 and ${MAX_CLIENT_COMMAND_ID_CHARACTERS} characters.`,
    };
  }

  const reason = optionalString(decoded.reason, MAX_REASON_CHARACTERS);
  if (reason === undefined) {
    return {
      error: `reason must be null or between 1 and ${MAX_REASON_CHARACTERS} characters.`,
    };
  }

  return { clientCommandId, reason };
}

function matchPath(pathname: string): RideSosAction | null {
  const collection = /^\/v1\/rides\/([^/]+)\/sos$/.exec(pathname);
  if (collection?.[1] != null) {
    return {
      kind: 'collection',
      rideId: decodeURIComponent(collection[1]),
    };
  }

  const command =
    /^\/v1\/rides\/([^/]+)\/sos\/([^/]+)\/(cancel|resolve)$/.exec(
      pathname,
    );
  if (command?.[1] == null || command[2] == null || command[3] == null) {
    return null;
  }

  return {
    kind: command[3] === 'cancel' ? 'cancel' : 'resolve',
    rideId: decodeURIComponent(command[1]),
    sosId: decodeURIComponent(command[2]),
  };
}

function boundedRequiredString(
  value: unknown,
  maxCharacters: number,
): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const normalized = value.trim();
  const count = [...normalized].length;
  return count >= 1 && count <= maxCharacters ? normalized : null;
}

function optionalString(
  value: unknown,
  maxCharacters: number,
): string | null | undefined {
  if (value == null) {
    return null;
  }
  if (typeof value !== 'string') {
    return undefined;
  }

  const normalized = value.trim();
  const count = [...normalized].length;
  return count >= 1 && count <= maxCharacters ? normalized : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
