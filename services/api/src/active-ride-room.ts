import type { Env } from './env';
import { resolveRidePushNotifier } from './push/runtime';
import { errorResponse, jsonResponse } from './http/json';
import { resolveRequestId } from './request-id';
import type { RideRole } from './clubs-rides/models';
import type { RideMessage } from './ride-comms/models';
import type { RideSos } from './ride-sos/models';
import {
  evaluateConvoySeparation,
  separationStateMeaningfullyChanged,
  type ConvoySeparationState,
} from './active-ride/separation';
import { realtimeRateLimited } from './active-ride/rate-limit';
import {
  ACTIVE_RIDE_PROTOCOL_VERSION,
  type ConnectionAttachment,
  parseClientEvent,
  presenceView,
  quickActionRaisedPayload,
  shouldAcceptPresence,
  type StoredPresence,
} from './active-ride/protocol';

const RIDE_STATUS_CHECK_INTERVAL_MS = 60_000;
const LOCATION_SAMPLE_INTERVAL_MS = 60_000;
const PRESENCE_MIN_INTERVAL_MS = 750;
const QUICK_ACTION_MIN_INTERVAL_MS = 2_000;
const QUICK_ACTION_DEDUP_LIMIT = 128;
const ENDED_AT_KEY = 'room.endedAt';
const QUICK_ACTION_IDS_KEY = 'room.quickActionIds';
const SEPARATION_STATE_KEY = 'room.separationState';
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
  private readonly lastPersistedSampleAt = new Map<string, number>();

  constructor(
    private readonly state: DurableObjectState,
    private readonly env: Env,
  ) {}

  async fetch(request: Request): Promise<Response> {
    const requestId = resolveRequestId(request);
    const url = new URL(request.url);

    if (
      url.pathname === '/connect' ||
      request.headers.get('x-commride-internal-action') === 'connect'
    ) {
      return this.connect(request, requestId);
    }

    if (url.pathname === '/presence-context') {
      if (request.method !== 'GET') {
        return errorResponse(
          'method_not_allowed',
          'Only GET is supported for this endpoint.',
          405,
          requestId,
        );
      }

      const rideId = requiredHeader(request, 'x-commride-ride-id');
      const riderId = requiredHeader(request, 'x-commride-rider-id');
      if (rideId == null || riderId == null) {
        return errorResponse(
          'invalid_internal_request',
          'Ride and Rider identity are required.',
          400,
          requestId,
        );
      }

      const presence = (await this.presenceState()).find(
        (item) => item.riderId === riderId,
      );
      if (presence == null) {
        return jsonResponse({ presence: null }, 200, requestId);
      }

      const view = presenceView(presence, new Date());
      return jsonResponse(
        {
          presence: {
            latitude: view.latitude,
            longitude: view.longitude,
            observedAt: view.observedAt,
            receivedAt: view.receivedAt,
            freshness: view.freshness,
            movement: view.movement,
          },
        },
        200,
        requestId,
      );
    }

    if (url.pathname === '/sos') {
      if (request.method !== 'POST') {
        return errorResponse(
          'method_not_allowed',
          'Only POST is supported for this endpoint.',
          405,
          requestId,
        );
      }

      const rideId = requiredHeader(request, 'x-commride-ride-id');
      if (rideId == null) {
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
          'SOS broadcast payload must be valid JSON.',
          400,
          requestId,
        );
      }

      const parsed = parseInternalRideSosEvent(body, rideId);
      if (parsed == null) {
        return errorResponse(
          'invalid_internal_request',
          'Persisted SOS broadcast payload is invalid.',
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

      this.broadcast(serverEvent(parsed.type, parsed.sos));
      return jsonResponse({ broadcast: true }, 200, requestId);
    }

    if (url.pathname === '/route-plan') {
      if (request.method !== 'POST') {
        return errorResponse(
          'method_not_allowed',
          'Only POST is supported for this endpoint.',
          405,
          requestId,
        );
      }

      const rideId = requiredHeader(request, 'x-commride-ride-id');
      if (rideId == null) {
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
          'RoutePlan broadcast payload must be valid JSON.',
          400,
          requestId,
        );
      }

      const update = parseInternalRoutePlanUpdate(body, rideId);
      if (update == null) {
        return errorResponse(
          'invalid_internal_request',
          'RoutePlan broadcast payload is invalid.',
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

      this.broadcast(serverEvent('ride.route_plan_updated', update));
      return jsonResponse({ broadcast: true }, 200, requestId);
    }

    if (url.pathname === '/message') {
      if (request.method !== 'POST') {
        return errorResponse(
          'method_not_allowed',
          'Only POST is supported for this endpoint.',
          405,
          requestId,
        );
      }

      const rideId = requiredHeader(request, 'x-commride-ride-id');
      if (rideId == null) {
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
          'Ride message payload must be valid JSON.',
          400,
          requestId,
        );
      }

      const message = parseInternalRideMessage(body, rideId);
      if (message == null) {
        return errorResponse(
          'invalid_internal_request',
          'Persisted Ride message payload is invalid.',
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

      this.broadcast(serverEvent('ride.message_created', message));
      return jsonResponse({ broadcast: true }, 200, requestId);
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

    await this.handleQuickAction(socket, attachment, parsed);
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

    await this.evaluateSeparation(attachment.rideId);
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

    const separation = await this.evaluateSeparation(rideId);
    const snapshot = await this.snapshot();
    server.send(
      serverEvent('ride.snapshot', {
        rideId,
        protocolVersion: ACTIVE_RIDE_PROTOCOL_VERSION,
        presences: snapshot,
        separation,
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
    const acceptedAt = new Date();
    if (
      realtimeRateLimited(
        attachment.lastPresenceAcceptedAt,
        acceptedAt,
        PRESENCE_MIN_INTERVAL_MS,
      )
    ) {
      socket.send(
        serverEvent('error', {
          code: 'presence_rate_limited',
          message: 'Presence updates are arriving too quickly.',
          eventId: event.eventId,
        }),
      );
      return;
    }

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
      receivedAt: acceptedAt.toISOString(),
      movement: event.payload.movement,
      connected: true,
    };

    socket.serializeAttachment({
      ...attachment,
      lastPresenceAcceptedAt: acceptedAt.toISOString(),
      lastPresence: next,
    } satisfies ConnectionAttachment);

    await this.persistJourneySample(attachment.rideId, next);

    this.broadcast(
      serverEvent('presence.updated', {
        eventId: event.eventId,
        presence: presenceView(next, new Date()),
      }),
    );

    await this.evaluateSeparation(attachment.rideId);
  }

  private async persistJourneySample(
    rideId: string,
    presence: StoredPresence,
  ): Promise<void> {
    if (this.env.DB == null) {
      return;
    }

    const observedAtMs = Date.parse(presence.observedAt);
    if (!Number.isFinite(observedAtMs)) {
      return;
    }

    const previous = this.lastPersistedSampleAt.get(presence.riderId);
    if (
      previous != null &&
      observedAtMs - previous < LOCATION_SAMPLE_INTERVAL_MS
    ) {
      return;
    }

    try {
      await this.env.DB
        .prepare(
          `
          INSERT INTO ride_location_samples(
            id,
            ride_id,
            rider_id,
            latitude,
            longitude,
            observed_at,
            received_at,
            movement
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(ride_id, rider_id, observed_at) DO NOTHING
          `,
        )
        .bind(
          crypto.randomUUID(),
          rideId,
          presence.riderId,
          presence.latitude,
          presence.longitude,
          presence.observedAt,
          presence.receivedAt,
          presence.movement,
        )
        .run();

      this.lastPersistedSampleAt.set(presence.riderId, observedAtMs);
    } catch {
      // Recap sampling is best-effort and must never interrupt realtime.
    }
  }

  private async handleQuickAction(
    socket: WebSocket,
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

    const acceptedAt = new Date();
    if (
      realtimeRateLimited(
        attachment.lastQuickActionAcceptedAt,
        acceptedAt,
        QUICK_ACTION_MIN_INTERVAL_MS,
      )
    ) {
      socket.send(
        serverEvent('error', {
          code: 'quick_action_rate_limited',
          message: 'Quick Actions are arriving too quickly.',
          eventId: event.eventId,
        }),
      );
      return;
    }

    const nextRecent = [...recent, event.eventId].slice(
      -QUICK_ACTION_DEDUP_LIMIT,
    );
    await this.state.storage.put(QUICK_ACTION_IDS_KEY, nextRecent);

    socket.serializeAttachment({
      ...attachment,
      lastQuickActionAcceptedAt: acceptedAt.toISOString(),
    } satisfies ConnectionAttachment);

    const raisedAt = acceptedAt;

    this.broadcast(
      serverEvent(
        'quick_action.raised',
        quickActionRaisedPayload(attachment, event, raisedAt),
      ),
    );

    if (
      event.payload.kind === 'need_help' ||
      event.payload.kind === 'left_behind'
    ) {
      await this.notifyQuickActionBestEffort(attachment, event);
    }
  }

  private async snapshot(): Promise<readonly ReturnType<typeof presenceView>[]> {
    const now = new Date();
    const presences = await this.presenceState();
    return presences.map((presence) => presenceView(presence, now));
  }

  private async presenceState(): Promise<StoredPresence[]> {
    const byRider = new Map<string, StoredPresence>();

    const offline =
      await this.state.storage.list<StoredPresence>({
        prefix: OFFLINE_PRESENCE_PREFIX,
      });
    for (const presence of offline.values()) {
      byRider.set(presence.riderId, presence);
    }

    for (const socket of this.state.getWebSockets()) {
      if (socket.readyState !== 1) {
        continue;
      }

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

    return [...byRider.values()];
  }

  private async evaluateSeparation(
    rideId?: string,
  ): Promise<ConvoySeparationState> {
    const previous =
      await this.state.storage.get<ConvoySeparationState>(
        SEPARATION_STATE_KEY,
      ) ?? null;
    const next = evaluateConvoySeparation(
      previous,
      await this.presenceState(),
      new Date(),
    );

    if (separationStateMeaningfullyChanged(previous, next)) {
      await this.state.storage.put(SEPARATION_STATE_KEY, next);
      this.broadcast(
        serverEvent('convoy.separation_updated', {
          separation: next,
        }),
      );

      if (
        rideId != null &&
        previous?.phase !== 'separated_attention' &&
        next.phase === 'separated_attention'
      ) {
        await this.notifySeparationBestEffort(rideId, next.confirmedAt);
      }
    }

    return next;
  }

  private async notifyQuickActionBestEffort(
    attachment: ConnectionAttachment,
    event: Extract<
      ReturnType<typeof parseClientEvent>,
      { type: 'quick_action.raise' }
    >,
  ): Promise<void> {
    const notifier = resolveRidePushNotifier(this.env);
    if (notifier == null) {
      return;
    }

    const isHelp = event.payload.kind === 'need_help';
    const kindLabel = isHelp ? 'Butuh bantuan' : 'Tertinggal';
    try {
      await notifier.notify({
        eventKey: `quick-action:${attachment.rideId}:${event.eventId}`,
        rideId: attachment.rideId,
        kind: event.payload.kind,
        title: `${kindLabel} · ${attachment.displayName}`,
        body:
          event.payload.reason ??
          (isHelp
            ? 'Rider meminta bantuan pada Ride aktif.'
            : 'Rider melaporkan tertinggal dari rombongan.'),
        data: {
          type: 'quick_action.raised',
          rideId: attachment.rideId,
          eventId: event.eventId,
          kind: event.payload.kind,
        },
        excludeRiderId: attachment.riderId,
      });
    } catch {
      // Realtime action remains authoritative even when push fails.
    }
  }

  private async notifySeparationBestEffort(
    rideId: string,
    confirmedAt: string | null,
  ): Promise<void> {
    const notifier = resolveRidePushNotifier(this.env);
    if (notifier == null) {
      return;
    }

    try {
      await notifier.notify({
        eventKey:
          `separation:${rideId}:${confirmedAt ?? new Date().toISOString()}`,
        rideId,
        kind: 'convoy_separation',
        title: 'Perhatian rombongan terpisah',
        body:
          'CommRide mendeteksi pemisahan rombongan yang sudah melewati ambang konfirmasi.',
        data: {
          type: 'convoy.separation_updated',
          rideId,
          phase: 'separated_attention',
        },
        leaderOnly: true,
      });
    } catch {
      // Convoy state remains realtime/server-derived even when push fails.
    }
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
    await this.state.storage.delete(SEPARATION_STATE_KEY);
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

function parseInternalRoutePlanUpdate(
  value: unknown,
  rideId: string,
): {
  rideId: string;
  revision: number;
  updatedByRiderId: string;
  updatedByRole: RideRole;
} | null {
  if (!isRecord(value)) {
    return null;
  }

  const role = parseRideRole(value.updatedByRole);
  if (
    value.rideId !== rideId ||
    typeof value.revision !== 'number' ||
    !Number.isInteger(value.revision) ||
    value.revision <= 0 ||
    typeof value.updatedByRiderId !== 'string' ||
    value.updatedByRiderId.length === 0 ||
    role == null
  ) {
    return null;
  }

  return {
    rideId,
    revision: value.revision,
    updatedByRiderId: value.updatedByRiderId,
    updatedByRole: role,
  };
}

function parseInternalRideMessage(
  value: unknown,
  rideId: string,
): RideMessage | null {
  if (!isRecord(value)) {
    return null;
  }

  const role = parseRideRole(value.senderRideRole);
  const kind =
    value.kind === 'chat' || value.kind === 'announcement'
      ? value.kind
      : null;
  const createdAt =
    typeof value.createdAt === 'string'
      ? normalizeIsoDate(value.createdAt)
      : null;

  if (
    value.rideId !== rideId ||
    typeof value.id !== 'string' ||
    value.id.length === 0 ||
    typeof value.senderRiderId !== 'string' ||
    value.senderRiderId.length === 0 ||
    typeof value.senderDisplayName !== 'string' ||
    value.senderDisplayName.length === 0 ||
    role == null ||
    kind == null ||
    typeof value.body !== 'string' ||
    value.body.length === 0 ||
    typeof value.clientMessageId !== 'string' ||
    value.clientMessageId.length === 0 ||
    createdAt == null
  ) {
    return null;
  }

  return {
    id: value.id,
    rideId,
    senderRiderId: value.senderRiderId,
    senderDisplayName: value.senderDisplayName,
    senderRideRole: role,
    kind,
    body: value.body,
    clientMessageId: value.clientMessageId,
    createdAt,
  };
}

function parseInternalRideSosEvent(
  value: unknown,
  rideId: string,
): {
  type: 'ride.sos_raised' | 'ride.sos_cancelled' | 'ride.sos_resolved';
  sos: RideSos;
} | null {
  if (!isRecord(value)) {
    return null;
  }

  const type = value.type;
  if (
    type !== 'ride.sos_raised' &&
    type !== 'ride.sos_cancelled' &&
    type !== 'ride.sos_resolved'
  ) {
    return null;
  }

  const rawSos = value.sos;
  if (!isRecord(rawSos) || rawSos.rideId !== rideId) {
    return null;
  }

  const role = parseRideRole(rawSos.riderRideRole);
  const state =
    rawSos.state === 'active' ||
    rawSos.state === 'cancelled' ||
    rawSos.state === 'resolved'
      ? rawSos.state
      : null;
  const raisedAt =
    typeof rawSos.raisedAt === 'string'
      ? normalizeIsoDate(rawSos.raisedAt)
      : null;

  if (
    typeof rawSos.id !== 'string' ||
    rawSos.id.length === 0 ||
    typeof rawSos.riderId !== 'string' ||
    rawSos.riderId.length === 0 ||
    typeof rawSos.riderDisplayName !== 'string' ||
    rawSos.riderDisplayName.length === 0 ||
    role == null ||
    state == null ||
    typeof rawSos.clientCommandId !== 'string' ||
    rawSos.clientCommandId.length === 0 ||
    (rawSos.reason !== null && typeof rawSos.reason !== 'string') ||
    raisedAt == null ||
    (rawSos.cancelledAt !== null &&
      (typeof rawSos.cancelledAt !== 'string' ||
        normalizeIsoDate(rawSos.cancelledAt) == null)) ||
    (rawSos.resolvedAt !== null &&
      (typeof rawSos.resolvedAt !== 'string' ||
        normalizeIsoDate(rawSos.resolvedAt) == null)) ||
    (rawSos.resolvedByRiderId !== null &&
      typeof rawSos.resolvedByRiderId !== 'string')
  ) {
    return null;
  }

  const presence = parseSosPresence(rawSos.presence);
  if (rawSos.presence != null && presence == null) {
    return null;
  }

  const sos: RideSos = {
    id: rawSos.id,
    rideId,
    riderId: rawSos.riderId,
    riderDisplayName: rawSos.riderDisplayName,
    riderRideRole: role,
    state,
    clientCommandId: rawSos.clientCommandId,
    reason: rawSos.reason as string | null,
    raisedAt,
    cancelledAt:
      rawSos.cancelledAt == null
        ? null
        : normalizeIsoDate(rawSos.cancelledAt as string),
    resolvedAt:
      rawSos.resolvedAt == null
        ? null
        : normalizeIsoDate(rawSos.resolvedAt as string),
    resolvedByRiderId:
      rawSos.resolvedByRiderId == null
        ? null
        : rawSos.resolvedByRiderId as string,
    presence,
  };

  const expectedState =
    type === 'ride.sos_raised'
      ? 'active'
      : type === 'ride.sos_cancelled'
        ? 'cancelled'
        : 'resolved';
  return sos.state === expectedState ? { type, sos } : null;
}

function parseSosPresence(
  value: unknown,
): RideSos['presence'] | null {
  if (value == null) {
    return null;
  }
  if (!isRecord(value)) {
    return null;
  }

  const observedAt =
    typeof value.observedAt === 'string'
      ? normalizeIsoDate(value.observedAt)
      : null;
  const receivedAt =
    typeof value.receivedAt === 'string'
      ? normalizeIsoDate(value.receivedAt)
      : null;

  if (
    typeof value.latitude !== 'number' ||
    !Number.isFinite(value.latitude) ||
    value.latitude < -90 ||
    value.latitude > 90 ||
    typeof value.longitude !== 'number' ||
    !Number.isFinite(value.longitude) ||
    value.longitude < -180 ||
    value.longitude > 180 ||
    observedAt == null ||
    receivedAt == null ||
    (value.freshness !== 'live' &&
      value.freshness !== 'stale' &&
      value.freshness !== 'offline') ||
    (value.movement !== 'moving' &&
      value.movement !== 'stopped' &&
      value.movement !== 'unknown')
  ) {
    return null;
  }

  return {
    latitude: value.latitude,
    longitude: value.longitude,
    observedAt,
    receivedAt,
    freshness: value.freshness,
    movement: value.movement,
  };
}

function normalizeIsoDate(value: string): string | null {
  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
