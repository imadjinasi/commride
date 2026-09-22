import { ACTIVE_RIDE_PROTOCOL_VERSION } from './protocol';
import type { RideRole } from '../clubs-rides/models';
import type { RideMessage } from '../ride-comms/models';
import type { RideSos, TrustedRidePresenceSnapshot } from '../ride-sos/models';

export interface ActiveRideParticipant {
  readonly riderId: string;
  readonly displayName: string;
  readonly role: RideRole;
}

export interface ActiveRideRoutePlanUpdate {
  readonly rideId: string;
  readonly revision: number;
  readonly updatedByRiderId: string;
  readonly updatedByRole: RideRole;
}

export interface ActiveRideGateway {
  connect(
    request: Request,
    rideId: string,
    participant: ActiveRideParticipant,
  ): Promise<Response>;

  endRide(rideId: string, endedAt: string): Promise<void>;

  messageCreated?(
    rideId: string,
    message: RideMessage,
  ): Promise<void>;

  trustedPresence?(
    rideId: string,
    riderId: string,
  ): Promise<TrustedRidePresenceSnapshot | null>;

  sosChanged?(
    rideId: string,
    type: 'ride.sos_raised' | 'ride.sos_cancelled' | 'ride.sos_resolved',
    sos: RideSos,
  ): Promise<void>;

  routePlanUpdated?(
    update: ActiveRideRoutePlanUpdate,
  ): Promise<void>;
}

export class DurableObjectActiveRideGateway
  implements ActiveRideGateway
{
  constructor(private readonly namespace: DurableObjectNamespace) {}

  async connect(
    request: Request,
    rideId: string,
    participant: ActiveRideParticipant,
  ): Promise<Response> {
    const stub = this.namespace.get(
      this.namespace.idFromName(rideId),
    );
    const headers = new Headers(request.headers);
    headers.delete('authorization');
    headers.set('x-commride-ride-id', rideId);
    headers.set('x-commride-rider-id', participant.riderId);
    headers.set(
      'x-commride-rider-display-name',
      participant.displayName,
    );
    headers.set('x-commride-ride-role', participant.role);
    headers.set(
      'x-commride-protocol-version',
      String(ACTIVE_RIDE_PROTOCOL_VERSION),
    );
    headers.set('x-commride-internal-action', 'connect');

    return stub.fetch(
      new Request(request, {
        headers,
      }),
    );
  }

  async endRide(rideId: string, endedAt: string): Promise<void> {
    const stub = this.namespace.get(
      this.namespace.idFromName(rideId),
    );

    const response = await stub.fetch(
      new Request('https://active-ride.internal/end', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-commride-ride-id': rideId,
        },
        body: JSON.stringify({ endedAt }),
      }),
    );

    if (!response.ok) {
      throw new Error('Active Ride room did not acknowledge Ride end.');
    }
  }

  async trustedPresence(
    rideId: string,
    riderId: string,
  ): Promise<TrustedRidePresenceSnapshot | null> {
    const stub = this.namespace.get(
      this.namespace.idFromName(rideId),
    );

    const response = await stub.fetch(
      new Request('https://active-ride.internal/presence-context', {
        method: 'GET',
        headers: {
          'x-commride-ride-id': rideId,
          'x-commride-rider-id': riderId,
        },
      }),
    );

    if (!response.ok) {
      throw new Error(
        'Active Ride room did not return trusted Rider presence.',
      );
    }

    const decoded: unknown = await response.json();
    if (!isRecord(decoded)) {
      throw new Error('Active Ride room returned invalid presence context.');
    }

    if (decoded.presence == null) {
      return null;
    }

    const presence = parseTrustedPresence(decoded.presence);
    if (presence == null) {
      throw new Error('Active Ride room returned invalid presence context.');
    }
    return presence;
  }

  async sosChanged(
    rideId: string,
    type: 'ride.sos_raised' | 'ride.sos_cancelled' | 'ride.sos_resolved',
    sos: RideSos,
  ): Promise<void> {
    const stub = this.namespace.get(
      this.namespace.idFromName(rideId),
    );

    const response = await stub.fetch(
      new Request('https://active-ride.internal/sos', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-commride-ride-id': rideId,
        },
        body: JSON.stringify({ type, sos }),
      }),
    );

    if (!response.ok) {
      throw new Error(
        'Active Ride room did not acknowledge persisted SOS broadcast.',
      );
    }
  }

  async routePlanUpdated(
    update: ActiveRideRoutePlanUpdate,
  ): Promise<void> {
    const stub = this.namespace.get(
      this.namespace.idFromName(update.rideId),
    );

    const response = await stub.fetch(
      new Request('https://active-ride.internal/route-plan', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-commride-ride-id': update.rideId,
        },
        body: JSON.stringify(update),
      }),
    );

    if (!response.ok) {
      throw new Error(
        'Active Ride room did not acknowledge RoutePlan update.',
      );
    }
  }

  async messageCreated(
    rideId: string,
    message: RideMessage,
  ): Promise<void> {
    const stub = this.namespace.get(
      this.namespace.idFromName(rideId),
    );

    const response = await stub.fetch(
      new Request('https://active-ride.internal/message', {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'x-commride-ride-id': rideId,
        },
        body: JSON.stringify(message),
      }),
    );

    if (!response.ok) {
      throw new Error(
        'Active Ride room did not acknowledge persisted message broadcast.',
      );
    }
  }
}


function parseTrustedPresence(
  value: unknown,
): TrustedRidePresenceSnapshot | null {
  if (!isRecord(value)) {
    return null;
  }

  const latitude = value.latitude;
  const longitude = value.longitude;
  const observedAt = normalizeIsoDate(value.observedAt);
  const receivedAt = normalizeIsoDate(value.receivedAt);
  const freshness = value.freshness;
  const movement = value.movement;

  if (
    typeof latitude !== 'number' ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    typeof longitude !== 'number' ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180 ||
    observedAt == null ||
    receivedAt == null ||
    (freshness !== 'live' &&
      freshness !== 'stale' &&
      freshness !== 'offline') ||
    (movement !== 'moving' &&
      movement !== 'stopped' &&
      movement !== 'unknown')
  ) {
    return null;
  }

  return {
    latitude,
    longitude,
    observedAt,
    receivedAt,
    freshness,
    movement,
  };
}

function normalizeIsoDate(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.valueOf()) ? null : parsed.toISOString();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
