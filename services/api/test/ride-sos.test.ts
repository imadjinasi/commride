import { describe, expect, it } from 'vitest';

import type {
  ActiveRideGateway,
  ActiveRideParticipant,
} from '../src/active-ride/gateway';
import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type {
  Ride,
  RideMembership,
  RideMembershipStatus,
  RideRole,
  RideStatus,
} from '../src/clubs-rides/models';
import type { ClubRideRepository } from '../src/clubs-rides/repository';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import type {
  CreateRideSosInput,
  RideSos,
  TrustedRidePresenceSnapshot,
} from '../src/ride-sos/models';
import type { RideSosRepository } from '../src/ride-sos/repository';
import { handleRequest } from '../src/router';

const leader: RiderProfile = {
  id: 'leader-1',
  authSubject: 'auth-leader',
  displayName: 'Leader One',
  callsign: 'Lead',
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

const member: RiderProfile = {
  id: 'member-1',
  authSubject: 'auth-member',
  displayName: 'Member One',
  callsign: 'M1',
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

class TestIdentityVerifier implements IdentityVerifier {
  async verify(token: string): Promise<AuthenticatedIdentity> {
    if (token === 'leader-token') {
      return { subject: leader.authSubject };
    }
    if (token === 'member-token') {
      return { subject: member.authSubject };
    }
    throw new Error('Unknown test token.');
  }
}

class TestRiderRepository implements RiderRepository {
  async findByAuthSubject(subject: string): Promise<RiderProfile | null> {
    return [leader, member].find((rider) => rider.authSubject === subject) ?? null;
  }

  async findById(riderId: string): Promise<RiderProfile | null> {
    return [leader, member].find((rider) => rider.id === riderId) ?? null;
  }

  async upsertProfile(
    _input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    throw new Error('Not used.');
  }
}

class MemoryRideSosRepository implements RideSosRepository {
  readonly records: RideSos[] = [];

  async findByClientCommandId(
    rideId: string,
    riderId: string,
    clientCommandId: string,
  ): Promise<RideSos | null> {
    return this.records.find(
      (sos) =>
        sos.rideId === rideId &&
        sos.riderId === riderId &&
        sos.clientCommandId === clientCommandId,
    ) ?? null;
  }

  async findById(rideId: string, sosId: string): Promise<RideSos | null> {
    return this.records.find(
      (sos) => sos.rideId === rideId && sos.id === sosId,
    ) ?? null;
  }

  async create(input: CreateRideSosInput): Promise<RideSos> {
    const existing = await this.findByClientCommandId(
      input.rideId,
      input.riderId,
      input.clientCommandId,
    );
    if (existing != null) {
      return existing;
    }
    this.records.push(input);
    return input;
  }

  async list(rideId: string): Promise<readonly RideSos[]> {
    return this.records.filter((sos) => sos.rideId === rideId);
  }

  async hasActiveForRide(rideId: string): Promise<boolean> {
    return this.records.some(
      (sos) => sos.rideId === rideId && sos.state === 'active',
    );
  }

  async cancel(
    rideId: string,
    sosId: string,
    cancelledAt: string,
  ): Promise<RideSos | null> {
    const index = this.records.findIndex(
      (sos) => sos.rideId === rideId && sos.id === sosId,
    );
    if (index < 0) {
      return null;
    }
    const current = this.records[index];
    if (current.state !== 'active') {
      return current;
    }
    const next: RideSos = {
      ...current,
      state: 'cancelled',
      cancelledAt,
    };
    this.records[index] = next;
    return next;
  }

  async resolve(
    rideId: string,
    sosId: string,
    resolvedAt: string,
    resolvedByRiderId: string,
  ): Promise<RideSos | null> {
    const index = this.records.findIndex(
      (sos) => sos.rideId === rideId && sos.id === sosId,
    );
    if (index < 0) {
      return null;
    }
    const current = this.records[index];
    if (current.state !== 'active') {
      return current;
    }
    const next: RideSos = {
      ...current,
      state: 'resolved',
      resolvedAt,
      resolvedByRiderId,
    };
    this.records[index] = next;
    return next;
  }
}

class MemoryClubRideRepository {
  currentRide: Ride;
  readonly memberships: Map<string, RideMembership>;

  constructor(
    status: RideStatus = 'active',
    memberStatus: RideMembershipStatus = 'active',
  ) {
    this.currentRide = ride(status);
    this.memberships = new Map<string, RideMembership>([
      [leader.id, membership(leader.id, 'leader')],
      [member.id, membership(member.id, 'member', memberStatus)],
    ]);
  }

  async findRide(rideId: string): Promise<Ride | null> {
    return rideId === this.currentRide.id ? this.currentRide : null;
  }

  async findRideMembership(
    rideId: string,
    riderId: string,
  ): Promise<RideMembership | null> {
    return rideId === this.currentRide.id
      ? this.memberships.get(riderId) ?? null
      : null;
  }

  async transitionRideStatus(
    rideId: string,
    expectedStatus: RideStatus,
    nextStatus: RideStatus,
    timestamp: string,
  ): Promise<Ride | null> {
    if (
      rideId !== this.currentRide.id ||
      this.currentRide.status !== expectedStatus
    ) {
      return this.currentRide;
    }
    this.currentRide = {
      ...this.currentRide,
      status: nextStatus,
      endedAt:
        nextStatus === 'completed' ? timestamp : this.currentRide.endedAt,
      updatedAt: timestamp,
    };
    return this.currentRide;
  }
}

class RecordingGateway implements ActiveRideGateway {
  presence: TrustedRidePresenceSnapshot | null = null;
  readonly events: Array<{ type: string; sos: RideSos }> = [];
  failBroadcast = false;

  async connect(
    _request: Request,
    _rideId: string,
    _participant: ActiveRideParticipant,
  ): Promise<Response> {
    throw new Error('Not used.');
  }

  async endRide(_rideId: string, _endedAt: string): Promise<void> {}

  async trustedPresence(
    _rideId: string,
    _riderId: string,
  ): Promise<TrustedRidePresenceSnapshot | null> {
    return this.presence;
  }

  async sosChanged(
    _rideId: string,
    type: 'ride.sos_raised' | 'ride.sos_cancelled' | 'ride.sos_resolved',
    sos: RideSos,
  ): Promise<void> {
    if (this.failBroadcast) {
      throw new Error('Room unavailable.');
    }
    this.events.push({ type, sos });
  }
}

function ride(status: RideStatus = 'active'): Ride {
  return {
    id: 'ride-1',
    clubId: 'club-1',
    createdByRiderId: leader.id,
    title: 'Sunday Ride',
    status,
    scheduledStartAt: null,
    actualStartAt:
      status === 'active' || status === 'completed'
        ? '2026-09-18T09:00:00Z'
        : null,
    endedAt: status === 'completed' ? '2026-09-18T12:00:00Z' : null,
    notes: null,
    createdAt: '2026-09-18T00:00:00Z',
    updatedAt: '2026-09-18T00:00:00Z',
  };
}

function membership(
  riderId: string,
  role: RideRole,
  status: RideMembershipStatus = 'active',
): RideMembership {
  return {
    rideId: 'ride-1',
    riderId,
    role,
    status,
  };
}

function request(
  path: string,
  method: 'GET' | 'POST',
  token: 'leader-token' | 'member-token',
  body?: Record<string, unknown>,
): Request {
  return new Request(`https://commride.invalid${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body == null ? {} : { 'content-type': 'application/json' }),
    },
    ...(body == null ? {} : { body: JSON.stringify(body) }),
  });
}

function dependencies(
  sos: RideSosRepository,
  gateway: ActiveRideGateway,
  clubRide = new MemoryClubRideRepository(),
) {
  let idCounter = 0;
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository: clubRide as unknown as ClubRideRepository,
    rideSosRepository: sos,
    activeRideGateway: gateway,
    idFactory: () => `sos-${++idCounter}`,
    now: () => new Date('2026-09-18T10:00:00Z'),
  };
}

async function bodyOf(response: Response) {
  return response.json() as Promise<Record<string, unknown>>;
}

describe('Ride SOS API', () => {
  it('raises SOS with server-derived identity and trusted presence', async () => {
    const sos = new MemoryRideSosRepository();
    const gateway = new RecordingGateway();
    gateway.presence = {
      latitude: -6.732,
      longitude: 108.552,
      observedAt: '2026-09-18T09:59:55.000Z',
      receivedAt: '2026-09-18T09:59:56.000Z',
      freshness: 'live',
      movement: 'stopped',
    };

    const response = await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'client-sos-1',
        reason: ' Ban bocor ',
        riderId: 'spoofed-leader',
      }),
      {},
      dependencies(sos, gateway),
    );

    expect(response.status).toBe(201);
    expect(sos.records).toHaveLength(1);
    expect(sos.records[0]).toMatchObject({
      riderId: member.id,
      riderDisplayName: member.displayName,
      riderRideRole: 'member',
      state: 'active',
      reason: 'Ban bocor',
      presence: gateway.presence,
    });
    expect(gateway.events.map((event) => event.type)).toEqual([
      'ride.sos_raised',
    ]);
  });

  it('raises SOS when no trusted GPS presence is available', async () => {
    const sos = new MemoryRideSosRepository();
    const response = await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'client-no-location',
      }),
      {},
      dependencies(sos, new RecordingGateway()),
    );

    expect(response.status).toBe(201);
    expect(sos.records[0].presence).toBeNull();
  });

  it('keeps stale trusted presence explicitly stale', async () => {
    const sos = new MemoryRideSosRepository();
    const gateway = new RecordingGateway();
    gateway.presence = {
      latitude: -6.7,
      longitude: 108.5,
      observedAt: '2026-09-18T09:58:00.000Z',
      receivedAt: '2026-09-18T09:58:01.000Z',
      freshness: 'stale',
      movement: 'unknown',
    };

    await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'client-stale',
      }),
      {},
      dependencies(sos, gateway),
    );

    expect(sos.records[0].presence?.freshness).toBe('stale');
    expect(sos.records[0].presence?.observedAt).toBe(
      '2026-09-18T09:58:00.000Z',
    );
  });

  it('returns the existing SOS for an identical idempotent retry', async () => {
    const sos = new MemoryRideSosRepository();
    const gateway = new RecordingGateway();
    const deps = dependencies(sos, gateway);

    const first = await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'stable-client',
        reason: 'Need help',
      }),
      {},
      deps,
    );
    const repeated = await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'stable-client',
        reason: 'Need help',
      }),
      {},
      deps,
    );

    expect(first.status).toBe(201);
    expect(repeated.status).toBe(200);
    expect(sos.records).toHaveLength(1);
    expect(gateway.events).toHaveLength(1);
  });

  it('keeps persistence successful if realtime broadcast is unavailable', async () => {
    const sos = new MemoryRideSosRepository();
    const gateway = new RecordingGateway();
    gateway.failBroadcast = true;

    const response = await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'broadcast-fails',
      }),
      {},
      dependencies(sos, gateway),
    );

    expect(response.status).toBe(201);
    expect(sos.records).toHaveLength(1);
  });

  it('allows the raising Rider to cancel their own SOS', async () => {
    const sos = new MemoryRideSosRepository();
    const gateway = new RecordingGateway();
    const deps = dependencies(sos, gateway);

    await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'cancel-me',
      }),
      {},
      deps,
    );

    const response = await handleRequest(
      request('/v1/rides/ride-1/sos/sos-1/cancel', 'POST', 'member-token'),
      {},
      deps,
    );

    expect(response.status).toBe(200);
    expect(sos.records[0].state).toBe('cancelled');
    expect(gateway.events.at(-1)?.type).toBe('ride.sos_cancelled');
  });

  it('rejects another ordinary Rider from cancelling someone else SOS', async () => {
    const sos = new MemoryRideSosRepository();
    const deps = dependencies(sos, new RecordingGateway());

    await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'member-sos',
      }),
      {},
      deps,
    );

    const response = await handleRequest(
      request('/v1/rides/ride-1/sos/sos-1/cancel', 'POST', 'leader-token'),
      {},
      deps,
    );

    expect(response.status).toBe(403);
    expect(sos.records[0].state).toBe('active');
  });

  it('allows the Ride Leader to resolve an Active SOS', async () => {
    const sos = new MemoryRideSosRepository();
    const gateway = new RecordingGateway();
    const deps = dependencies(sos, gateway);

    await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'resolve-me',
      }),
      {},
      deps,
    );

    const response = await handleRequest(
      request('/v1/rides/ride-1/sos/sos-1/resolve', 'POST', 'leader-token'),
      {},
      deps,
    );

    expect(response.status).toBe(200);
    expect(sos.records[0]).toMatchObject({
      state: 'resolved',
      resolvedByRiderId: leader.id,
    });
    expect(gateway.events.at(-1)?.type).toBe('ride.sos_resolved');
  });

  it('keeps Completed Ride SOS history readable', async () => {
    const sos = new MemoryRideSosRepository();
    sos.records.push({
      id: 'sos-history',
      rideId: 'ride-1',
      riderId: member.id,
      riderDisplayName: member.displayName,
      riderRideRole: 'member',
      state: 'resolved',
      clientCommandId: 'history',
      reason: null,
      raisedAt: '2026-09-18T10:00:00Z',
      cancelledAt: null,
      resolvedAt: '2026-09-18T10:05:00Z',
      resolvedByRiderId: leader.id,
      presence: null,
    });

    const clubRide = new MemoryClubRideRepository('completed', 'finished');
    const response = await handleRequest(
      request('/v1/rides/ride-1/sos', 'GET', 'member-token'),
      {},
      dependencies(sos, new RecordingGateway(), clubRide),
    );

    expect(response.status).toBe(200);
    const body = await bodyOf(response) as { sos: RideSos[] };
    expect(body.sos).toHaveLength(1);
    expect(body.sos[0].state).toBe('resolved');
  });

  it('blocks End Ride while any SOS remains Active', async () => {
    const sos = new MemoryRideSosRepository();
    const clubRide = new MemoryClubRideRepository();
    const deps = dependencies(sos, new RecordingGateway(), clubRide);

    await handleRequest(
      request('/v1/rides/ride-1/sos', 'POST', 'member-token', {
        clientCommandId: 'active-before-end',
      }),
      {},
      deps,
    );

    const blocked = await handleRequest(
      request('/v1/rides/ride-1/end', 'POST', 'leader-token'),
      {},
      deps,
    );
    expect(blocked.status).toBe(409);
    expect(clubRide.currentRide.status).toBe('active');

    await handleRequest(
      request('/v1/rides/ride-1/sos/sos-1/resolve', 'POST', 'leader-token'),
      {},
      deps,
    );

    const ended = await handleRequest(
      request('/v1/rides/ride-1/end', 'POST', 'leader-token'),
      {},
      deps,
    );
    expect(ended.status).toBe(200);
    expect(clubRide.currentRide.status).toBe('completed');
  });
});
