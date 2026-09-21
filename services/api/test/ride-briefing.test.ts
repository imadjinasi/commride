import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type {
  BriefingReadiness,
  BriefingRoleSnapshot,
  PublishRideBriefingInput,
  RideBriefing,
  RideBriefingView,
} from '../src/briefings/models';
import type { RideBriefingRepository } from '../src/briefings/repository';
import type {
  Ride,
  RideMembership,
} from '../src/clubs-rides/models';
import type { ClubRideRepository } from '../src/clubs-rides/repository';
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
  displayName: 'Leader One',
  callsign: 'Lead',
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

const member: RiderProfile = {
  id: 'rider-member',
  authSubject: 'auth-member',
  displayName: 'Member One',
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
      (item) => item.authSubject === subject,
    ) ?? null;
  }

  async findById(riderId: string): Promise<RiderProfile | null> {
    return [leader, member].find((item) => item.id === riderId) ?? null;
  }

  async upsertProfile(
    _input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    throw new Error('Not used.');
  }
}

class MemoryRoutePlanRepository implements RoutePlanRepository {
  constructor(initial: RoutePlan) {
    this.history.push(initial);
    this.current = initial;
  }

  readonly history: RoutePlan[] = [];
  private current: RoutePlan;

  async findCurrent(rideId: string): Promise<RoutePlan | null> {
    return this.current.rideId === rideId ? this.current : null;
  }

  async findById(routePlanId: string): Promise<RoutePlan | null> {
    return this.history.find((item) => item.id === routePlanId) ?? null;
  }

  async replaceCurrent(_input: SaveRoutePlanInput): Promise<RoutePlan> {
    throw new Error('Not used.');
  }

  setCurrent(next: RoutePlan): void {
    const previousIndex = this.history.findIndex(
      (item) => item.id === this.current.id,
    );
    if (previousIndex >= 0) {
      this.history[previousIndex] = {
        ...this.history[previousIndex],
        isCurrent: false,
      };
    }
    this.current = next;
    this.history.push(next);
  }
}

class MemoryBriefingRepository implements RideBriefingRepository {
  constructor(
    private readonly expectedRiders: readonly string[],
  ) {}

  readonly history: RideBriefing[] = [];
  readonly acknowledgements = new Map<string, Set<string>>();
  private current: RideBriefing | null = null;

  async findCurrent(rideId: string): Promise<RideBriefing | null> {
    return this.current?.rideId === rideId ? this.current : null;
  }

  async resolveRoleSnapshot(
    _rideId: string,
  ): Promise<BriefingRoleSnapshot | null> {
    return {
      leader: {
        riderId: leader.id,
        displayName: leader.displayName,
      },
      sweeper: null,
    };
  }

  async publish(input: PublishRideBriefingInput): Promise<RideBriefing> {
    if (this.current != null) {
      const previousIndex = this.history.findIndex(
        (item) => item.id === this.current?.id,
      );
      if (previousIndex >= 0) {
        this.history[previousIndex] = {
          ...this.history[previousIndex],
          isCurrent: false,
        };
      }
    }

    const briefing: RideBriefing = {
      id: input.id,
      rideId: input.rideId,
      revision: this.history.length + 1,
      routePlanId: input.routePlanId,
      createdByRiderId: input.createdByRiderId,
      scheduledStartAt: input.scheduledStartAt,
      leader: input.roles.leader,
      sweeper: input.roles.sweeper,
      notes: input.notes,
      isCurrent: true,
      publishedAt: input.publishedAt,
    };

    this.current = briefing;
    this.history.push(briefing);
    return briefing;
  }

  async acknowledge(
    briefingId: string,
    riderId: string,
    _timestamp: string,
  ): Promise<void> {
    const riders =
      this.acknowledgements.get(briefingId) ?? new Set<string>();
    riders.add(riderId);
    this.acknowledgements.set(briefingId, riders);
  }

  async getReadiness(
    _rideId: string,
    briefingId: string,
    currentRiderId: string,
  ): Promise<BriefingReadiness> {
    const riders =
      this.acknowledgements.get(briefingId) ?? new Set<string>();
    const ready = this.expectedRiders.filter((riderId) =>
      riders.has(riderId)
    );

    return {
      expectedCount: this.expectedRiders.length,
      readyCount: ready.length,
      currentRiderAcknowledged: riders.has(currentRiderId),
    };
  }
}

function routePlan(id: string, revision: number): RoutePlan {
  return {
    id,
    rideId: 'ride-1',
    revision,
    createdByRiderId: leader.id,
    travelMode: 'drive',
    originLabel: 'Cirebon',
    origin: { latitude: -6.732, longitude: 108.552 },
    destinationLabel: 'Bandung',
    destination: { latitude: -6.917, longitude: 107.619 },
    distanceMeters: 130000 + revision * 1000,
    durationSeconds: 9000 + revision * 100,
    encodedPolyline: `polyline-${revision}`,
    isCurrent: true,
    createdAt: '2026-09-18T00:00:00Z',
    stops: [],
  };
}

function ride(status: Ride['status'] = 'published'): Ride {
  return {
    id: 'ride-1',
    clubId: 'club-1',
    createdByRiderId: leader.id,
    title: 'Sunday Ride',
    status,
    scheduledStartAt: '2026-09-20T00:00:00Z',
    actualStartAt:
      status === 'active' ? '2026-09-20T00:05:00Z' : null,
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
  path: string,
  method: 'GET' | 'POST',
  token: 'leader-token' | 'member-token',
  body?: unknown,
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
  currentRide: Ride,
  memberships: readonly RideMembership[],
  routes: MemoryRoutePlanRepository,
  briefings: MemoryBriefingRepository,
) {
  let nextId = 1;
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository: clubRideRepository(currentRide, memberships),
    routePlanRepository: routes,
    rideBriefingRepository: briefings,
    idFactory: () => `briefing-${nextId++}`,
    now: () => new Date('2026-09-18T09:00:00Z'),
  };
}

async function publish(
  deps: ReturnType<typeof dependencies>,
): Promise<RideBriefingView> {
  const response = await handleRequest(
    request(
      '/v1/rides/ride-1/briefing/publish',
      'POST',
      'leader-token',
      { notes: 'Meet at 05:30. Fuel before departure.' },
    ),
    {},
    deps,
  );
  expect(response.status).toBe(200);

  const body = await response.json() as {
    briefingView: RideBriefingView;
  };
  return body.briefingView;
}

describe('Ride Briefing API', () => {
  it('publishes an immutable briefing against the current RoutePlan', async () => {
    const routes = new MemoryRoutePlanRepository(routePlan('plan-1', 1));
    const briefings = new MemoryBriefingRepository([
      leader.id,
      member.id,
    ]);
    const deps = dependencies(
      ride('draft'),
      [
        membership(leader.id, 'leader'),
        membership(member.id, 'member'),
      ],
      routes,
      briefings,
    );

    const view = await publish(deps);

    expect(view.briefing.revision).toBe(1);
    expect(view.briefing.routePlanId).toBe('plan-1');
    expect(view.briefing.notes).toContain('Fuel before departure');
    expect(view.routePlan.id).toBe('plan-1');
    expect(view.routePlanIsCurrent).toBe(true);
    expect(view.readiness).toEqual({
      expectedCount: 2,
      readyCount: 0,
      currentRiderAcknowledged: false,
    });
  });

  it('rejects briefing publication by a non-Leader', async () => {
    const routes = new MemoryRoutePlanRepository(routePlan('plan-1', 1));
    const briefings = new MemoryBriefingRepository([
      leader.id,
      member.id,
    ]);
    const deps = dependencies(
      ride(),
      [
        membership(leader.id, 'leader'),
        membership(member.id, 'member'),
      ],
      routes,
      briefings,
    );

    const response = await handleRequest(
      request(
        '/v1/rides/ride-1/briefing/publish',
        'POST',
        'member-token',
        { notes: 'Forged briefing.' },
      ),
      {},
      deps,
    );

    expect(response.status).toBe(403);
    expect(briefings.history).toHaveLength(0);
  });

  it('rejects an invited-only Rider from reading the briefing', async () => {
    const routes = new MemoryRoutePlanRepository(routePlan('plan-1', 1));
    const briefings = new MemoryBriefingRepository([leader.id]);
    const deps = dependencies(
      ride(),
      [
        membership(leader.id, 'leader'),
        membership(member.id, 'member', 'invited'),
      ],
      routes,
      briefings,
    );

    await publish(deps);

    const response = await handleRequest(
      request(
        '/v1/rides/ride-1/briefing',
        'GET',
        'member-token',
      ),
      {},
      deps,
    );

    expect(response.status).toBe(403);
  });

  it('acknowledges only the current Rider and updates readiness', async () => {
    const routes = new MemoryRoutePlanRepository(routePlan('plan-1', 1));
    const briefings = new MemoryBriefingRepository([
      leader.id,
      member.id,
    ]);
    const deps = dependencies(
      ride(),
      [
        membership(leader.id, 'leader'),
        membership(member.id, 'member'),
      ],
      routes,
      briefings,
    );

    await publish(deps);

    const response = await handleRequest(
      request(
        '/v1/rides/ride-1/briefing/acknowledge',
        'POST',
        'member-token',
      ),
      {},
      deps,
    );

    expect(response.status).toBe(200);
    const body = await response.json() as {
      briefingView: RideBriefingView;
    };
    expect(body.briefingView.readiness).toEqual({
      expectedCount: 2,
      readyCount: 1,
      currentRiderAcknowledged: true,
    });
    expect(
      briefings.acknowledgements
        .get(body.briefingView.briefing.id)
        ?.has(member.id),
    ).toBe(true);
    expect(
      briefings.acknowledgements
        .get(body.briefingView.briefing.id)
        ?.has(leader.id),
    ).toBe(false);
  });

  it('marks the briefing stale after RoutePlan replacement and blocks acknowledgement', async () => {
    const routes = new MemoryRoutePlanRepository(routePlan('plan-1', 1));
    const briefings = new MemoryBriefingRepository([
      leader.id,
      member.id,
    ]);
    const deps = dependencies(
      ride(),
      [
        membership(leader.id, 'leader'),
        membership(member.id, 'member'),
      ],
      routes,
      briefings,
    );

    await publish(deps);
    routes.setCurrent(routePlan('plan-2', 2));

    const readResponse = await handleRequest(
      request('/v1/rides/ride-1/briefing', 'GET', 'member-token'),
      {},
      deps,
    );
    expect(readResponse.status).toBe(200);
    const readBody = await readResponse.json() as {
      briefingView: RideBriefingView;
    };
    expect(readBody.briefingView.routePlanIsCurrent).toBe(false);
    expect(readBody.briefingView.routePlan.id).toBe('plan-1');

    const acknowledgeResponse = await handleRequest(
      request(
        '/v1/rides/ride-1/briefing/acknowledge',
        'POST',
        'member-token',
      ),
      {},
      deps,
    );
    expect(acknowledgeResponse.status).toBe(409);

    const errorBody = await acknowledgeResponse.json() as {
      error: { code: string };
    };
    expect(errorBody.error.code).toBe('briefing_stale');
  });

  it('does not carry old acknowledgements into a new briefing revision', async () => {
    const routes = new MemoryRoutePlanRepository(routePlan('plan-1', 1));
    const briefings = new MemoryBriefingRepository([
      leader.id,
      member.id,
    ]);
    const deps = dependencies(
      ride(),
      [
        membership(leader.id, 'leader'),
        membership(member.id, 'member'),
      ],
      routes,
      briefings,
    );

    const first = await publish(deps);
    await briefings.acknowledge(
      first.briefing.id,
      member.id,
      '2026-09-18T09:01:00Z',
    );

    routes.setCurrent(routePlan('plan-2', 2));
    const second = await publish(deps);

    expect(second.briefing.revision).toBe(2);
    expect(second.briefing.routePlanId).toBe('plan-2');
    expect(second.readiness.readyCount).toBe(0);
    expect(second.readiness.currentRiderAcknowledged).toBe(false);
    expect(briefings.history[0]?.isCurrent).toBe(false);
    expect(briefings.history[1]?.isCurrent).toBe(true);
  });

  it('rejects publishing a new briefing after the Ride is Active', async () => {
    const routes = new MemoryRoutePlanRepository(routePlan('plan-1', 1));
    const briefings = new MemoryBriefingRepository([leader.id]);
    const deps = dependencies(
      ride('active'),
      [membership(leader.id, 'leader', 'active')],
      routes,
      briefings,
    );

    const response = await handleRequest(
      request(
        '/v1/rides/ride-1/briefing/publish',
        'POST',
        'leader-token',
      ),
      {},
      deps,
    );

    expect(response.status).toBe(409);
    expect(briefings.history).toHaveLength(0);
  });
});
