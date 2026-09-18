import type { RideRole } from '../clubs-rides/models';

export const ACTIVE_RIDE_PROTOCOL_VERSION = 1 as const;
export const PRESENCE_LIVE_MAX_AGE_MS = 30_000;
export const PRESENCE_MAX_FUTURE_SKEW_MS = 120_000;
export const PRESENCE_MAX_PAST_AGE_MS = 10 * 60_000;

export type PresenceMovement = 'moving' | 'stopped' | 'unknown';
export type PresenceFreshness = 'live' | 'stale' | 'offline';

export interface ConnectionAttachment {
  readonly protocolVersion: 1;
  readonly rideId: string;
  readonly riderId: string;
  readonly displayName: string;
  readonly role: RideRole;
  readonly sessionId: string;
  readonly joinedAt: string;
  readonly lastPresence?: StoredPresence;
}

export interface StoredPresence {
  readonly riderId: string;
  readonly displayName: string;
  readonly role: RideRole;
  readonly latitude: number;
  readonly longitude: number;
  readonly observedAt: string;
  readonly receivedAt: string;
  readonly movement: PresenceMovement;
  readonly connected: boolean;
}

export interface PresenceView extends StoredPresence {
  readonly freshness: PresenceFreshness;
}

export interface PresenceUpdateEvent {
  readonly v: 1;
  readonly type: 'presence.update';
  readonly eventId: string;
  readonly sentAt: string;
  readonly payload: {
    readonly latitude: number;
    readonly longitude: number;
    readonly observedAt: string;
    readonly movement: PresenceMovement;
  };
}

export type QuickActionKind =
  | 'stopping'
  | 'left_behind'
  | 'need_help';

export interface QuickActionRaiseEvent {
  readonly v: 1;
  readonly type: 'quick_action.raise';
  readonly eventId: string;
  readonly sentAt: string;
  readonly payload: {
    readonly kind: QuickActionKind;
    readonly reason: string | null;
  };
}

export type ActiveRideClientEvent =
  | PresenceUpdateEvent
  | QuickActionRaiseEvent;

export interface ProtocolError {
  readonly code: string;
  readonly message: string;
}

export function parseClientEvent(
  raw: string,
  now: Date,
): ActiveRideClientEvent | ProtocolError {
  let decoded: unknown;
  try {
    decoded = JSON.parse(raw);
  } catch {
    return {
      code: 'invalid_json',
      message: 'Realtime event must be valid JSON.',
    };
  }

  if (!isRecord(decoded)) {
    return {
      code: 'invalid_event',
      message: 'Realtime event must be a JSON object.',
    };
  }

  if (decoded.v !== ACTIVE_RIDE_PROTOCOL_VERSION) {
    return {
      code: 'unsupported_protocol_version',
      message: 'Unsupported Active Ride protocol version.',
    };
  }

  const eventId = requiredString(decoded.eventId, 128);
  const sentAt = isoDate(decoded.sentAt);
  if (eventId == null || sentAt == null) {
    return {
      code: 'invalid_event_envelope',
      message: 'eventId and sentAt are required.',
    };
  }

  if (decoded.type === 'presence.update') {
    return parsePresenceEvent(decoded, eventId, sentAt, now);
  }

  if (decoded.type === 'quick_action.raise') {
    return parseQuickActionEvent(decoded, eventId, sentAt);
  }

  return {
    code: 'unsupported_event_type',
    message: 'Unsupported Active Ride event type.',
  };
}

export function shouldAcceptPresence(
  current: StoredPresence | null,
  nextObservedAt: string,
): boolean {
  if (current == null) {
    return true;
  }

  return Date.parse(nextObservedAt) > Date.parse(current.observedAt);
}

export function quickActionPresenceContext(
  presence: StoredPresence | undefined,
  now: Date,
): PresenceView | null {
  return presence == null ? null : presenceView(presence, now);
}

export function quickActionRaisedPayload(
  attachment: Pick<
    ConnectionAttachment,
    'riderId' | 'displayName' | 'role' | 'lastPresence'
  >,
  event: QuickActionRaiseEvent,
  raisedAt: Date,
) {
  return {
    eventId: event.eventId,
    rider: {
      riderId: attachment.riderId,
      displayName: attachment.displayName,
      role: attachment.role,
    },
    kind: event.payload.kind,
    reason: event.payload.reason,
    raisedAt: raisedAt.toISOString(),
    presence: quickActionPresenceContext(
      attachment.lastPresence,
      raisedAt,
    ),
  };
}

export function presenceView(
  presence: StoredPresence,
  now: Date,
): PresenceView {
  const age = Math.max(
    0,
    now.valueOf() - Date.parse(presence.observedAt),
  );

  const freshness: PresenceFreshness = !presence.connected
    ? 'offline'
    : age <= PRESENCE_LIVE_MAX_AGE_MS
      ? 'live'
      : 'stale';

  return {
    ...presence,
    freshness,
  };
}

function parsePresenceEvent(
  decoded: Record<string, unknown>,
  eventId: string,
  sentAt: string,
  now: Date,
): PresenceUpdateEvent | ProtocolError {
  if (!isRecord(decoded.payload)) {
    return {
      code: 'invalid_presence',
      message: 'presence.update requires a payload object.',
    };
  }

  const latitude = coordinate(
    decoded.payload.latitude,
    -90,
    90,
  );
  const longitude = coordinate(
    decoded.payload.longitude,
    -180,
    180,
  );
  const observedAt = isoDate(decoded.payload.observedAt);
  const movement = decoded.payload.movement ?? 'unknown';

  if (
    latitude == null ||
    longitude == null ||
    observedAt == null ||
    (movement !== 'moving' &&
      movement !== 'stopped' &&
      movement !== 'unknown')
  ) {
    return {
      code: 'invalid_presence',
      message: 'presence.update payload is invalid.',
    };
  }

  const observedMs = Date.parse(observedAt);
  const nowMs = now.valueOf();
  if (observedMs > nowMs + PRESENCE_MAX_FUTURE_SKEW_MS) {
    return {
      code: 'presence_from_future',
      message: 'Presence observation is too far in the future.',
    };
  }

  if (observedMs < nowMs - PRESENCE_MAX_PAST_AGE_MS) {
    return {
      code: 'presence_too_old',
      message: 'Presence observation is too old to enter live state.',
    };
  }

  return {
    v: ACTIVE_RIDE_PROTOCOL_VERSION,
    type: 'presence.update',
    eventId,
    sentAt,
    payload: {
      latitude,
      longitude,
      observedAt,
      movement,
    },
  };
}

function parseQuickActionEvent(
  decoded: Record<string, unknown>,
  eventId: string,
  sentAt: string,
): QuickActionRaiseEvent | ProtocolError {
  if (!isRecord(decoded.payload)) {
    return {
      code: 'invalid_quick_action',
      message: 'quick_action.raise requires a payload object.',
    };
  }

  const kind = decoded.payload.kind;
  if (
    kind !== 'stopping' &&
    kind !== 'left_behind' &&
    kind !== 'need_help'
  ) {
    return {
      code: 'invalid_quick_action',
      message: 'Unsupported quick action kind.',
    };
  }

  const reason = optionalString(decoded.payload.reason, 240);
  if (reason === undefined) {
    return {
      code: 'invalid_quick_action',
      message: 'Quick action reason must be null or at most 240 characters.',
    };
  }

  return {
    v: ACTIVE_RIDE_PROTOCOL_VERSION,
    type: 'quick_action.raise',
    eventId,
    sentAt,
    payload: {
      kind,
      reason,
    },
  };
}

function coordinate(
  value: unknown,
  min: number,
  max: number,
): number | null {
  return typeof value === 'number' &&
    Number.isFinite(value) &&
    value >= min &&
    value <= max
    ? value
    : null;
}

function isoDate(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

function requiredString(
  value: unknown,
  maxLength: number,
): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maxLength
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
