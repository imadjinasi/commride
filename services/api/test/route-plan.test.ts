import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type {
  ClubRideRepository,
} from '../src/clubs-rides/repository';
import type {
  Ride,
  RideMembership,
} from '../src/clubs-rides/models';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import type {
  RoutePlan,
  SaveRoutePlanInput,
} from '../src/route-plans/models';
import type { RoutePlanRepository } from '../src/route-plans/repository';
import { handleRequest } from '../src/router';

const leader: RiderProfile = {
  id: 'rider-leader',
  authSubject: 'auth-leader',
  displayName: 'Leader',
  callsign: null,
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

const member: RiderProfile = {
  id: 'rider-member',
  authSubject: 'auth-member',
  displayName: 'Member',
  callsign: null,
  homeArea: 'Bandung',
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
    throw new Error('Unexpected token.');
  }
}

class TestRiderRepository implements RiderRepository {
  async findByAuthSubject(subject: string): Promise<RiderProfile | null> {
    return [leader, member].find(
      (rider) => rider.authSubject === subject,
    ) ?? null;
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

class MemoryRoutePlanRepository implements RoutePlanRepository {
  readonly history: RoutePlan[] = [];
  private current: RoutePlan | null = null;

  async findCurrent(rideId: string): Promise<RoutePlan | null> {
    return this.current?.rideId === rideId ? this.current : null;
  }

  async replaceCurrent(input: SaveRoutePlanInput): Promise<RoutePlan> {
    if (this.current != null) {
      const superseded: RoutePlan = {
        ...this.current,
        isCurrent: false,
      };
      this.history[this.history.length - 1] = superseded;
    }

    const routePlan: RoutePlan = {
      id: input.id,
      rideId: input.rideId,
      revision: this.history.length + 1,
      createdByRiderId: input.createdByRiderId,
      travelMode: input.travelMode,
      originLabel: input.originLabel,
      origin: input.origin,
      destinationLabel: input.destinationLabel,
      destination: input.destination,
      distanceMeters: input.distanceMeters,
      durationSeconds: input.durationSeconds,
      encodedPolyline: input.encodedPolyline,
      isCurrent: true,
      createdAt: '2026-09-18T00:00:00Z',
      stops: input.stops.map((stop) => ({ ...stop })),
    };

    this.current = routePlan;
    this.history.push(routePlan);
    return routePlan;
  }
}

function ride(status: Ride['status'] = 'draft'): Ride {
  return {
    id: 'ride-1',
    clubId: 'club-1',
    createdByRiderId: leader.id,
    title: 'Sunday Ride',
    status,
    scheduledStartAt: null,
    actualStartAt: status === 'active'
      ? '2026-09-18T08:00:00Z'
      : null,
    endedAt: null,
    notes: null,
    createdAt: '2026-09-18T00:00:00Z',
    updatedAt: '2026-09-18T00:00:00Z',
  };
}

function membership(
  riderId: string,
  role: RideMembership['role'],
  status: RideMembership['status'] = 'joined',
): RideMembership {
  return {
    rideId: 'ride-1',
    riderId,
    role,
    status,
  };
}

function clubRideRepository(
  currentRide: Ride,
  memberships: readonly RideMembership[],
): ClubRideRepository {
  return {
    async findRide(rideId: string) {
      return rideId === currentRide.id ? currentRide : null;
    },
    async findRideMembership(rideId: string, riderId: string) {
      return memberships.find(
        (item) => item.rideId === rideId && item.riderId === riderId,
      ) ?? null;
    },
  } as unknown as ClubRideRepository;
}

function request(
  method: 'GET' | 'PUT',
  token: 'leader-token' | 'member-token',
  body?: unknown,
): Request {
  return new Request(
    'https://commride.invalid/v1/rides/ride-1/route-plan',
    {
      method,
      headers: {
        authorization: `Bearer ${token}`,
        ...(body == null ? {} : { 'content-type': 'application/json' }),
      },
      ...(body == null ? {} : { body: JSON.stringify(body) }),
    },
  );
}

function routeBody(polyline: string, labels: readonly string[] = ['Fuel']) {
  return {
    travelMode: 'drive',
    origin: {
      label: 'Cirebon',
      location: { latitude: -6.732, longitude: 108.552 },
    },
    destination: {
      label: 'Bandung',
      location: { latitude: -6.917, longitude: 107.619 },
    },
    distanceMeters: 130000,
    durationSeconds: 9000,
    encodedPolyline: polyline,
    stops: labels.map((label, index) => ({
      label,
      formattedAddress: `Stop ${index + 1}`,
      location: {
        latitude: -6.8 - index * 0.01,
        longitude: 108.0 - index * 0.01,
      },
      stopType: index === 0 ? 'fuel' : 'rest',
      checkpointType: index === 0 ? 'fuel' : null,
      plannedDurationMinutes: 15,
    })),
  };
}

function overrides(
  currentRide: Ride,
  memberships: readonly RideMembership[],
  routePlanRepository: RoutePlanRepository,
) {
  let nextId = 1;
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository: clubRideRepository(currentRide, memberships),
    routePlanRepository,
    idFactory: () => `generated-${nextId++}`,
  };
}

describe('RoutePlan API', () => {
  it('saves full immutable revisions with stop order derived from the request', async () => {
    const repository = new MemoryRoutePlanRepository();
    const dependencies = overrides(
      ride('draft'),
      [
        membership(leader.id, 'leader'),
        membership(member.id, 'member'),
      ],
      repository,
    );

    const first = await handleRequest(
      request('PUT', 'leader-token', routeBody('route-v1', ['Fuel', 'Rest'])),
      {},
      dependencies,
    );

    expect(first.status).toBe(200);
    const firstBody = await first.json() as { routePlan: RoutePlan };
    expect(firstBody.routePlan.revision).toBe(1);
    expect(firstBody.routePlan.stops.map((stop) => stop.sequence)).toEqual([
      0,
      1,
    ]);

    const second = await handleRequest(
      request('PUT', 'leader-token', routeBody('route-v2', ['Rest', 'Fuel'])),
      {},
      dependencies,
    );

    expect(second.status).toBe(200);
    const secondBody = await second.json() as { routePlan: RoutePlan };
    expect(secondBody.routePlan.revision).toBe(2);
    expect(secondBody.routePlan.encodedPolyline).toBe('route-v2');
    expect(repository.history[0]?.isCurrent).toBe(false);
    expect(repository.history[1]?.isCurrent).toBe(true);
  });

  it('lets a joined participant read the current plan', async () => {
    const repository = new MemoryRoutePlanRepository();
    const dependencies = overrides(
      ride('published'),
      [
        membership(leader.id, 'leader'),
        membership(member.id, 'member'),
      ],
      repository,
    );

    await handleRequest(
      request('PUT', 'leader-token', routeBody('route-v1')),
      {},
      dependencies,
    );

    const response = await handleRequest(
      request('GET', 'member-token'),
      {},
      dependencies,
    );

    expect(response.status).toBe(200);
    const body = await response.json() as { routePlan: RoutePlan };
    expect(body.routePlan.encodedPolyline).toBe('route-v1');
  });

  it('rejects RoutePlan replacement by a non-Leader', async () => {
    const repository = new MemoryRoutePlanRepository();

    const response = await handleRequest(
      request('PUT', 'member-token', routeBody('forged-route')),
      {},
      overrides(
        ride('draft'),
        [
          membership(leader.id, 'leader'),
          membership(member.id, 'member'),
        ],
        repository,
      ),
    );

    expect(response.status).toBe(403);
    expect(repository.history).toHaveLength(0);
  });

  it('rejects invited Riders from reading a RoutePlan', async () => {
    const repository = new MemoryRoutePlanRepository();

    const response = await handleRequest(
      request('GET', 'member-token'),
      {},
      overrides(
        ride('published'),
        [
          membership(leader.id, 'leader'),
          membership(member.id, 'member', 'invited'),
        ],
        repository,
      ),
    );

    expect(response.status).toBe(403);
  });

  it('does not silently replace the pre-Ride plan after the Ride is Active', async () => {
    const repository = new MemoryRoutePlanRepository();

    const response = await handleRequest(
      request('PUT', 'leader-token', routeBody('active-replan')),
      {},
      overrides(
        ride('active'),
        [membership(leader.id, 'leader', 'active')],
        repository,
      ),
    );

    expect(response.status).toBe(409);
    expect(repository.history).toHaveLength(0);
  });

  it('rejects more than ten intermediate stops', async () => {
    const repository = new MemoryRoutePlanRepository();
    const labels = Array.from({ length: 11 }, (_, index) => `Stop ${index}`);

    const response = await handleRequest(
      request('PUT', 'leader-token', routeBody('too-many', labels)),
      {},
      overrides(
        ride('draft'),
        [membership(leader.id, 'leader')],
        repository,
      ),
    );

    expect(response.status).toBe(400);
    expect(repository.history).toHaveLength(0);
  });
});
