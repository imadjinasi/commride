import type { Env } from './env';
import { errorResponse, jsonResponse } from './http/json';
import { resolveRequestId } from './request-id';
import type { RideRole } from './clubs-rides/models';
import {
  ACTIVE_RIDE_PROTOCOL_VERSION,
  type ConnectionAttachment,
  parseClientEvent,
  presenceView,
  shouldAcceptPresence,
  type StoredPresence,
} from './active-ride/protocol';

const RIDE_STATUS_CHECK_INTERVAL_MS = 60_000;
const QUICK_ACTION_DEDUP_LIMIT = 128;
const ENDED_AT_KEY = 'room.endedAt';
const QUICK_ACTION_IDS_KEY = 'room.quickActionIds';
const OFFLINE_PRESENCE_PREFIX = 'presence:';

interface RideStatusRow {
  readonly status: string;
}

/**
 * One Durable Object instance coordinates one Active Ride.
 *
 * Authorization happens at the public Worker boundary and is repeated here
 * against authoritative Ride state before accepting the socket. Rider identity
 * is passed only through internal headers from the Worker.
 */
export class ActiveRideRoom {
  private lastRideStatusCheckAt = 0;

  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    const requestId = resolveRequestId(request);
    const url = new URL(request.url);

    if (url.pathname === '/connect') {
      return this.connect(request, requestId);
    }

    if (url.pathname === '/end') {
      if (request.method !== 'POST') {
        return errorResponse(
          'method_not_allowed',
          'Only POST is supported for this endpoint.',
          405,
          requestId,
        );
      }

      const rideId = request.headers.get('x-commride-ride-id');
      if (rideId == null || rideId.length === 0) {
        return errorResponse(
          'invalid_internal_request',
          'Ride identity is required.',
          400,
          requestId,
        );
      }

      let body: unknown;
      try {
        body = await request.json();
      } catch {
        return errorResponse(
          'invalid_internal_request',
          'Ride end payload must be valid JSON.',
          400,
          requestId,
        );
      }

      const endedAt =
        isRecord(body) && typeof body.endedAt === 'string'
          ? normalizeIsoDate(body.endedAt)
          : null;
      if (endedAt == null) {
        return errorResponse(
          'invalid_internal_request',
          'Ride end timestamp is required.',
          400,
          requestId,
        );
      }

      await this.endRoom(rideId, endedAt);
      return jsonResponse({ ended: true }, 200, requestId);
    }

    return errorResponse(
      'not_found',
      'The requested Active Ride room endpoint does not exist.',
      404,
      requestId,
    );
  }

  async webSocketMessage(
    socket: WebSocket,
    message: string | ArrayBuffer,
  ): Promise<void> {
    const attachment = readAttachment(socket);
    if (attachment == null) {
      socket.send(
        serverEvent('error', {
          code: 'invalid_connection_state',
          message: 'Realtime connection state is unavailable.',
        }),
      );
      socket.close(1011, 'Invalid connection state');
      return;
    }

    if (!(await this.ensureRideActive(attachment.rideId))) {
      await this.endRoom(
        attachment.rideId,
        new Date().toISOString(),
      );
      return;
    }

    if (typeof message !== 'string') {
      socket.send(
        serverEvent('error', {
          code: 'binary_event_not_supported',
          message: 'Active Ride protocol accepts JSON text events only.',
        }),
      );
      return;
    }

    const parsed = parseClientEvent(message, new Date());
    if ('code' in parsed) {
      socket.send(serverEvent('error', parsed));
      return;
    }

    if (parsed.type === 'presence.update') {
      await this.handlePresenceUpdate(socket, attachment, parsed);
      return;
    }

    await this.handleQuickAction(attachment, parsed);
  }

  async webSocketClose(
    socket: WebSocket,
    _code: number,
    _reason: string,
    _wasClean: boolean,
  ): Promise<void> {
    if (await this.state.storage.get<string>(ENDED_AT_KEY)) {
      return;
    }

    const attachment = readAttachment(socket);
    if (attachment?.lastPresence == null) {
      return;
    }

    const others = this.state
      .getWebSockets(`rider:${attachment.riderId}`)
      .filter(
        (candidate) =>
          candidate !== socket && candidate.readyState === 1,
      );

    if (others.length > 0) {
      return;
    }

    const offline: StoredPresence = {
      ...attachment.lastPresence,
      connected: false,
    };

    await this.state.storage.put(
      offlinePresenceKey(attachment.riderId),
      offline,
    );

    this.broadcast(
      serverEvent('presence.updated', {
        presence: presenceView(offline, new Date()),
      }),
    );
  }

  async webSocketError(
    socket: WebSocket,
    _error: unknown,
  ): Promise<void> {
    await this.webSocketClose(socket, 1011, 'WebSocket error', false);
  }

  private async connect(
    request: Request,
    requestId: string,
  ): Promise<Response> {
    if (request.method !== 'GET') {
      return errorResponse(
        'method_not_allowed',
        'Only GET is supported for this endpoint.',
        405,
        requestId,
      );
    }

    if (request.headers.get('upgrade')?.toLowerCase() !== 'websocket') {
      return errorResponse(
        'websocket_upgrade_required',
        'Active Ride room requires a WebSocket upgrade.',
        426,
        requestId,
      );
    }

    const rideId = requiredHeader(request, 'x-commride-ride-id');
    const riderId = requiredHeader(request, 'x-commride-rider-id');
    const displayName = requiredHeader(
      request,
      'x-commride-rider-display-name',
    );
    const role = parseRideRole(
      request.headers.get('x-commride-ride-role'),
    );
    const protocolVersion = request.headers.get(
      'x-commride-protocol-version',
    );

    if (
      rideId == null ||
      riderId == null ||
      displayName == null ||
      role == null
    ) {
      return errorResponse(
        'invalid_internal_request',
        'Verified Ride and Rider identity are required.',
        400,
        requestId,
      );
    }

    if (protocolVersion !== String(ACTIVE_RIDE_PROTOCOL_VERSION)) {
      return errorResponse(
        'unsupported_protocol_version',
        'Unsupported Active Ride protocol version.',
        400,
        requestId,
      );
    }

    if (await this.state.storage.get<string>(ENDED_AT_KEY)) {
      return errorResponse(
        'active_ride_ended',
        'This Active Ride room has already ended.',
        409,
        requestId,
      );
    }

    if (!(await this.ensureRideActive(rideId, true))) {
      return errorResponse(
        'active_ride_required',
        'Realtime room is available only while the Ride is Active.',
        409,
        requestId,
      );
    }

    let inheritedPresence: StoredPresence | undefined;
    for (const existing of this.state.getWebSockets(`rider:${riderId}`)) {
      const existingAttachment = readAttachment(existing);
      if (
        existingAttachment?.lastPresence != null &&
        (
          inheritedPresence == null ||
          Date.parse(existingAttachment.lastPresence.observedAt) >
            Date.parse(inheritedPresence.observedAt)
        )
      ) {
        inheritedPresence = existingAttachment.lastPresence;
      }
      existing.close(4001, 'Replaced by a newer Rider connection');
    }

    const offlinePresence =
      await this.state.storage.get<StoredPresence>(
        offlinePresenceKey(riderId),
      );
    if (
      offlinePresence != null &&
      (
        inheritedPresence == null ||
        Date.parse(offlinePresence.observedAt) >
          Date.parse(inheritedPresence.observedAt)
      )
    ) {
      inheritedPresence = {
        ...offlinePresence,
        connected: true,
      };
    }

    await this.state.storage.delete(offlinePresenceKey(riderId));

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [
      WebSocket,
      WebSocket,
    ];

    this.state.acceptWebSocket(server, [
      `ride:${rideId}`,
      `rider:${riderId}`,
    ]);

    const attachment: ConnectionAttachment = {
      protocolVersion: ACTIVE_RIDE_PROTOCOL_VERSION,
      rideId,
      riderId,
      displayName,
      role,
      sessionId: crypto.randomUUID(),
      joinedAt: new Date().toISOString(),
      ...(inheritedPresence == null
        ? {}
        : {
            lastPresence: {
              ...inheritedPresence,
              connected: true,
            },
          }),
    };
    server.serializeAttachment(attachment);

    const snapshot = await this.snapshot();
    server.send(
      serverEvent('ride.snapshot', {
        rideId,
        protocolVersion: ACTIVE_RIDE_PROTOCOL_VERSION,
        presences: snapshot,
      }),
    );

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  private async handlePresenceUpdate(
    socket: WebSocket,
    attachment: ConnectionAttachment,
    event: Extract<
      ReturnType<typeof parseClientEvent>,
      { type: 'presence.update' }
    >,
  ): Promise<void> {
    const current =
      attachment.lastPresence ??
      await this.state.storage.get<StoredPresence>(
        offlinePresenceKey(attachment.riderId),
      ) ??
      null;

    if (!shouldAcceptPresence(current, event.payload.observedAt)) {
      socket.send(
        serverEvent('error', {
          code: 'presence_out_of_order',
          message: 'Older presence observation was ignored.',
          eventId: event.eventId,
        }),
      );
      return;
    }

    const next: StoredPresence = {
      riderId: attachment.riderId,
      displayName: attachment.displayName,
      role: attachment.role,
      latitude: event.payload.latitude,
      longitude: event.payload.longitude,
      observedAt: event.payload.observedAt,
      receivedAt: new Date().toISOString(),
      movement: event.payload.movement,
      connected: true,
    };

    socket.serializeAttachment({
      ...attachment,
      lastPresence: next,
    } satisfies ConnectionAttachment);

    this.broadcast(
      serverEvent('presence.updated', {
        eventId: event.eventId,
        presence: presenceView(next, new Date()),
      }),
    );
  }

  private async handleQuickAction(
    attachment: ConnectionAttachment,
    event: Extract<
      ReturnType<typeof parseClientEvent>,
      { type: 'quick_action.raise' }
    >,
  ): Promise<void> {
    const recent =
      await this.state.storage.get<string[]>(QUICK_ACTION_IDS_KEY) ?? [];
    if (recent.includes(event.eventId)) {
      return;
    }

    const nextRecent = [...recent, event.eventId].slice(
      -QUICK_ACTION_DEDUP_LIMIT,
    );
    await this.state.storage.put(QUICK_ACTION_IDS_KEY, nextRecent);

    this.broadcast(
      serverEvent('quick_action.raised', {
        eventId: event.eventId,
        rider: {
          riderId: attachment.riderId,
          displayName: attachment.displayName,
          role: attachment.role,
        },
        kind: event.payload.kind,
        reason: event.payload.reason,
        raisedAt: new Date().toISOString(),
      }),
    );
  }

  private async snapshot(): Promise<readonly ReturnType<typeof presenceView>[]> {
    const byRider = new Map<string, StoredPresence>();

    const offline =
      await this.state.storage.list<StoredPresence>({
        prefix: OFFLINE_PRESENCE_PREFIX,
      });
    for (const presence of offline.values()) {
      byRider.set(presence.riderId, presence);
    }

    for (const socket of this.state.getWebSockets()) {
      const attachment = readAttachment(socket);
      const presence = attachment?.lastPresence;
      if (presence == null) {
        continue;
      }

      const existing = byRider.get(presence.riderId);
      if (
        existing == null ||
        Date.parse(presence.observedAt) >
          Date.parse(existing.observedAt)
      ) {
        byRider.set(presence.riderId, {
          ...presence,
          connected: true,
        });
      }
    }

    const now = new Date();
    return [...byRider.values()].map((presence) =>
      presenceView(presence, now)
    );
  }

  private async ensureRideActive(
    rideId: string,
    force = false,
  ): Promise<boolean> {
    const now = Date.now();
    if (
      !force &&
      now - this.lastRideStatusCheckAt <
        RIDE_STATUS_CHECK_INTERVAL_MS
    ) {
      return true;
    }

    if (this.env.DB == null) {
      return false;
    }

    const row = await this.env.DB
      .prepare('SELECT status FROM rides WHERE id = ? LIMIT 1')
      .bind(rideId)
      .first<RideStatusRow>();

    this.lastRideStatusCheckAt = now;
    return row?.status === 'active';
  }

  private async endRoom(
    rideId: string,
    endedAt: string,
  ): Promise<void> {
    const existingEndedAt =
      await this.state.storage.get<string>(ENDED_AT_KEY);
    const effectiveEndedAt = existingEndedAt ?? endedAt;

    if (existingEndedAt == null) {
      await this.state.storage.put(ENDED_AT_KEY, effectiveEndedAt);
    }

    this.broadcast(
      serverEvent('ride.ended', {
        rideId,
        endedAt: effectiveEndedAt,
      }),
    );

    for (const socket of this.state.getWebSockets()) {
      socket.close(1000, 'Ride ended');
    }

    const stored =
      await this.state.storage.list<StoredPresence>({
        prefix: OFFLINE_PRESENCE_PREFIX,
      });
    if (stored.size > 0) {
      await this.state.storage.delete([...stored.keys()]);
    }
  }

  private broadcast(message: string): void {
    for (const socket of this.state.getWebSockets()) {
      try {
        socket.send(message);
      } catch {
        // A closing socket will disappear from getWebSockets eventually.
      }
    }
  }
}

function readAttachment(
  socket: WebSocket,
): ConnectionAttachment | null {
  const value: unknown = socket.deserializeAttachment();
  if (!isRecord(value)) {
    return null;
  }

  if (
    value.protocolVersion !== ACTIVE_RIDE_PROTOCOL_VERSION ||
    typeof value.rideId !== 'string' ||
    typeof value.riderId !== 'string' ||
    typeof value.displayName !== 'string' ||
    parseRideRole(value.role) == null ||
    typeof value.sessionId !== 'string' ||
    typeof value.joinedAt !== 'string'
  ) {
    return null;
  }

  return value as unknown as ConnectionAttachment;
}

function serverEvent(
  type: string,
  payload: unknown,
): string {
  return JSON.stringify({
    v: ACTIVE_RIDE_PROTOCOL_VERSION,
    type,
    sentAt: new Date().toISOString(),
    payload,
  });
}

function requiredHeader(
  request: Request,
  name: string,
): string | null {
  const value = request.headers.get(name)?.trim();
  return value == null || value.length === 0 ? null : value;
}

function parseRideRole(value: unknown): RideRole | null {
  return value === 'leader' ||
    value === 'sweeper' ||
    value === 'navigator' ||
    value === 'member'
    ? value
    : null;
}

function offlinePresenceKey(riderId: string): string {
  return `${OFFLINE_PRESENCE_PREFIX}${riderId}`;
}

function normalizeIsoDate(value: string): string | null {
  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
