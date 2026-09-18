import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import type { ActiveRideGateway } from '../active-ride/gateway';
import type { ClubRideRepository } from '../clubs-rides/repository';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type {
  CreateRideMessageInput,
  RideMessage,
  RideMessageCursor,
  RideMessageKind,
} from './models';
import type { RideMessageRepository } from './repository';

const DEFAULT_PAGE_SIZE = 50;
const MAX_PAGE_SIZE = 100;
const MAX_BODY_CHARACTERS = 1000;
const MAX_CLIENT_MESSAGE_ID_CHARACTERS = 128;

export interface RideCommsHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly clubRideRepository: ClubRideRepository;
  readonly messageRepository: RideMessageRepository;
  readonly activeRideGateway?: ActiveRideGateway;
  readonly idFactory?: () => string;
  readonly now?: () => Date;
}

type RideCommsAction = 'list' | 'chat' | 'announcement';

interface RideCommsPathMatch {
  readonly rideId: string;
  readonly action: RideCommsAction;
}

export function isRideCommsPath(pathname: string): boolean {
  return matchPath(pathname) != null;
}

export async function handleRideCommsRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: RideCommsHandlerDependencies,
): Promise<Response | null> {
  const path = matchPath(url.pathname);
  if (path == null) {
    return null;
  }

  const expectedMethod = path.action === 'list' ? 'GET' : 'POST';
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
  if (
    membership == null ||
    membership.status === 'invited' ||
    membership.status === 'left'
  ) {
    return errorResponse(
      'ride_membership_required',
      'A participating Ride membership is required for private communication.',
      403,
      requestId,
    );
  }

  if (path.action === 'list') {
    if (ride.status !== 'active' && ride.status !== 'completed') {
      return errorResponse(
        'ride_state_conflict',
        'Ride communication history is available only for Active or Completed Rides.',
        409,
        requestId,
      );
    }

    const pagination = parsePagination(url);
    if ('error' in pagination) {
      return errorResponse(
        'invalid_message_cursor',
        pagination.error,
        400,
        requestId,
      );
    }

    const page = await dependencies.messageRepository.list(
      path.rideId,
      pagination.limit,
      pagination.cursor,
    );

    return jsonResponse(
      {
        messages: page.messages,
        nextCursor:
          page.nextCursor == null ? null : encodeCursor(page.nextCursor),
      },
      200,
      requestId,
    );
  }

  if (ride.status !== 'active') {
    return errorResponse(
      'ride_state_conflict',
      'Messages can only be sent while the Ride is Active.',
      409,
      requestId,
    );
  }

  if (path.action === 'announcement' && membership.role !== 'leader') {
    return errorResponse(
      'ride_leader_required',
      'The Ride Leader role is required to publish an announcement.',
      403,
      requestId,
    );
  }

  const input = await readMessageInput(request);
  if ('error' in input) {
    return errorResponse(
      'invalid_ride_message',
      input.error,
      400,
      requestId,
    );
  }

  const kind: RideMessageKind =
    path.action === 'announcement' ? 'announcement' : 'chat';

  const existing =
    await dependencies.messageRepository.findByClientMessageId(
      path.rideId,
      rider.id,
      input.clientMessageId,
    );

  if (existing != null) {
    if (existing.kind !== kind || existing.body !== input.body) {
      return errorResponse(
        'message_idempotency_conflict',
        'clientMessageId was already used for different message content.',
        409,
        requestId,
      );
    }

    return jsonResponse({ message: existing }, 200, requestId);
  }

  const createdAt = (dependencies.now?.() ?? new Date()).toISOString();
  const messageInput: CreateRideMessageInput = {
    id: dependencies.idFactory?.() ?? crypto.randomUUID(),
    rideId: path.rideId,
    senderRiderId: rider.id,
    senderDisplayName: rider.displayName,
    senderRideRole: membership.role,
    kind,
    body: input.body,
    clientMessageId: input.clientMessageId,
    createdAt,
  };

  const persisted = await dependencies.messageRepository.create(messageInput);

  if (
    persisted.kind !== kind ||
    persisted.body !== input.body ||
    persisted.senderRiderId !== rider.id
  ) {
    return errorResponse(
      'message_idempotency_conflict',
      'clientMessageId resolved to different persisted message content.',
      409,
      requestId,
    );
  }

  await broadcastBestEffort(path.rideId, persisted, dependencies);

  return jsonResponse({ message: persisted }, 201, requestId);
}

async function broadcastBestEffort(
  rideId: string,
  message: RideMessage,
  dependencies: RideCommsHandlerDependencies,
): Promise<void> {
  if (dependencies.activeRideGateway?.messageCreated == null) {
    return;
  }

  try {
    await dependencies.activeRideGateway.messageCreated(rideId, message);
  } catch {
    // D1 remains authoritative. Clients recover through message history.
  }
}

async function readMessageInput(
  request: Request,
): Promise<
  { body: string; clientMessageId: string } | { error: string }
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

  const body = boundedRequiredString(
    decoded.body,
    MAX_BODY_CHARACTERS,
  );
  if (body == null) {
    return {
      error: `body must be between 1 and ${MAX_BODY_CHARACTERS} characters.`,
    };
  }

  const clientMessageId = boundedRequiredString(
    decoded.clientMessageId,
    MAX_CLIENT_MESSAGE_ID_CHARACTERS,
  );
  if (clientMessageId == null) {
    return {
      error:
        `clientMessageId must be between 1 and ${MAX_CLIENT_MESSAGE_ID_CHARACTERS} characters.`,
    };
  }

  return { body, clientMessageId };
}

function parsePagination(
  url: URL,
):
  | { limit: number; cursor: RideMessageCursor | null }
  | { error: string } {
  const rawLimit = url.searchParams.get('limit');
  const limit =
    rawLimit == null ? DEFAULT_PAGE_SIZE : Number.parseInt(rawLimit, 10);
  if (
    !Number.isInteger(limit) ||
    limit < 1 ||
    limit > MAX_PAGE_SIZE ||
    (rawLimit != null && String(limit) !== rawLimit)
  ) {
    return {
      error: `limit must be an integer between 1 and ${MAX_PAGE_SIZE}.`,
    };
  }

  const rawCursor = url.searchParams.get('cursor');
  if (rawCursor == null) {
    return { limit, cursor: null };
  }

  const separator = rawCursor.indexOf('|');
  if (separator <= 0 || separator === rawCursor.length - 1) {
    return { error: 'cursor is invalid.' };
  }

  const createdAt = rawCursor.slice(0, separator);
  const parsedDate = new Date(createdAt);
  if (Number.isNaN(parsedDate.valueOf())) {
    return { error: 'cursor timestamp is invalid.' };
  }

  let id: string;
  try {
    id = decodeURIComponent(rawCursor.slice(separator + 1));
  } catch {
    return { error: 'cursor message ID is invalid.' };
  }
  if (id.length === 0) {
    return { error: 'cursor message ID is invalid.' };
  }

  return {
    limit,
    cursor: {
      createdAt: parsedDate.toISOString(),
      id,
    },
  };
}

function encodeCursor(cursor: RideMessageCursor): string {
  return `${cursor.createdAt}|${encodeURIComponent(cursor.id)}`;
}

function boundedRequiredString(
  value: unknown,
  maxCharacters: number,
): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim();
  const characterCount = [...normalized].length;
  return characterCount >= 1 && characterCount <= maxCharacters
    ? normalized
    : null;
}

function matchPath(pathname: string): RideCommsPathMatch | null {
  const messages = /^\/v1\/rides\/([^/]+)\/messages$/.exec(pathname);
  if (messages?.[1] != null) {
    return {
      rideId: decodeURIComponent(messages[1]),
      action: 'list',
    };
  }

  const announcements =
    /^\/v1\/rides\/([^/]+)\/announcements$/.exec(pathname);
  if (announcements?.[1] != null) {
    return {
      rideId: decodeURIComponent(announcements[1]),
      action: 'announcement',
    };
  }

  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
