import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type {
  CheckpointCheckIn,
  CheckpointRelease,
  RideCheckpointView,
} from '../src/checkpoints/models';
import type {
  CheckpointParticipantRecord,
  CheckpointRepository,
} from '../src/checkpoints/repository';
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
  constructor(private readonly current: RoutePlan | null) {}

  async findCurrent(rideId: string): Promise<RoutePlan | null> {
    return this.current?.rideId === rideId ? this.current : null;
  }

  async findById(routePlanId: string): Promise<RoutePlan | null> {
    return this.current?.id === routePlanId ? this.current : null;
  }

  async replaceCurrent(_input: SaveRoutePlanInput): Promise<RoutePlan> {
    throw new Error('Not used.');
  }
}

class MemoryCheckpointRepository implements CheckpointRepository {
  constructor(
    readonly participants: readonly CheckpointParticipantRecord[],
    checkpointSequences: ReadonlyMap<string, number>,
  ) {
    this.checkpointSequences = checkpointSequences;
  }

  private readonly checkpointSequences: ReadonlyMap<string, number>;
  readonly checkIns = new Map<string, CheckpointCheckIn>();
  readonly releases = new Map<string, CheckpointRelease>();

  async listParticipants(
    _rideId: string,
  ): Promise<readonly CheckpointParticipantRecord[]> {
    return this.participants;
  }

  async listCheckIns(
    rideId: string,
    routePlanId: string,
  ): Promise<readonly CheckpointCheckIn[]> {
    return [...this.checkIns.values()].filter(
      (item) =>
        item.routePlanId === routePlanId &&
        item.checkpointId.startsWith(rideId === 'ride-1' ? 'cp-' : 'never-'),
    );
  }

  async listReleases(
    _rideId: string,
    routePlanId: string,
  ): Promise<readonly CheckpointRelease[]> {
    return [...this.releases.values()].filter(
      (item) => item.routePlanId === routePlanId,
    );
  }

  async checkIn(
    _rideId: string,
    routePlanId: string,
    checkpointId: string,
    riderId: string,
    checkedInAt: string,
  ): Promise<void> {
    const key = `${routePlanId}:${checkpointId}:${riderId}`;
    if (this.checkIns.has(key)) {
      return;
    }

    this.checkIns.set(key, {
      routePlanId,
      checkpointId,
      riderId,
      checkedInAt,
      method: 'manual',
    });
  }

  async release(
    _rideId: string,
    routePlanId: string,
    checkpointId: string,
    checkpointSequence: number,
    releasedByRiderId: string,
    releasedAt: string,
  ): Promise<boolean> {
    const existing = this.releases.get(checkpointId);
    if (existing != null) {
      return true;
    }

    const earlierCheckpointIds = [...this.checkpointSequences.entries()]
      .filter(([, sequence]) => sequence < checkpointSequence)
      .map(([id]) => id);
    if (
      earlierCheckpointIds.some(
        (id) => !this.releases.has(id),
      )
    ) {
      return false;
    }

    this.releases.set(checkpointId, {
      routePlanId,
      checkpointId,
      releasedByRiderId,
      releasedAt,
    });
    return true;
  }
}

function routePlan(): RoutePlan {
  return {
    id: 'plan-2',
    rideId: 'ride-1',
    revision: 2,
    createdByRiderId: leader.id,
    travelMode: 'drive',
    originLabel: 'Cirebon',
    origin: { latitude: -6.732, longitude: 108.552 },
    destinationLabel: 'Bandung',
    destination: { latitude: -6.917, longitude: 107.619 },
    distanceMeters: 130000,
    durationSeconds: 9000,
    encodedPolyline: 'polyline-v2',
    isCurrent: true,
    createdAt: '2026-09-18T00:00:00Z',
    stops: [
      {
        id: 'cp-fuel',
        sequence: 0,
        label: 'Fuel One',
        formattedAddress: 'SPBU One',
        location: { latitude: -6.8, longitude: 108.0 },
        stopType: 'fuel',
        checkpointType: 'fuel',
        plannedDurationMinutes: 15,
      },
      {
        id: 'stop-food',
        sequence: 1,
        label: 'Food Stop',
        formattedAddress: null,
        location: { latitude: -6.82, longitude: 107.95 },
        stopType: 'meal',
        checkpointType: null,
        plannedDurationMinutes: 30,
      },
      {
        id: 'cp-regroup',
        sequence: 2,
        label: 'Regroup Point',
        formattedAddress: 'Rest Area',
        location: { latitude: -6.85, longitude: 107.9 },
        stopType: 'rest',
        checkpointType: 'mandatory_regroup',
        plannedDurationMinutes: 20,
      },
    ],
  };
}

function ride(status: Ride['status'] = 'active'): Ride {
  return {
    id: 'ride-1',
    clubId: 'club-1',
    createdByRiderId: leader.id,
    title: 'Sunday Ride',
    status,
    scheduledStartAt: '2026-09-20T00:00:00Z',
    actualStartAt:
      status === 'active' || status === 'completed'
        ? '2026-09-20T00:05:00Z'
        : null,
    endedAt:
      status === 'completed' ? '2026-09-20T05:00:00Z' : null,
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

function participants(): readonly CheckpointParticipantRecord[] {
  return [
    {
      riderId: leader.id,
      displayName: leader.displayName,
      role: 'leader',
      membershipStatus: 'joined',
    },
    {
      riderId: member.id,
      displayName: member.displayName,
      role: 'member',
      membershipStatus: 'joined',
    },
  ];
}

function checkpointRepository(): MemoryCheckpointRepository {
  return new MemoryCheckpointRepository(
    participants(),
    new Map<string, number>([
      ['cp-fuel', 0],
      ['cp-regroup', 2],
    ]),
  );
}

function request(
  path: string,
  method: 'GET' | 'POST',
  token: 'leader-token' | 'member-token',
): Request {
  return new Request(`https://commride.invalid${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
    },
  });
}

function dependencies(
  currentRide: Ride,
  memberships: readonly RideMembership[],
  routes: RoutePlanRepository,
  checkpoints: CheckpointRepository,
) {
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository: clubRideRepository(currentRide, memberships),
    routePlanRepository: routes,
    checkpointRepository: checkpoints,
    now: () => new Date('2026-09-18T10:00:00Z'),
  };
}

function activeMemberships(
  memberStatus: RideMembership['status'] = 'joined',
): readonly RideMembership[] {
  return [
    membership(leader.id, 'leader'),
    membership(member.id, 'member', memberStatus),
  ];
}

async function readView(response: Response): Promise<RideCheckpointView> {
  const body = await response.json() as {
    checkpointView: RideCheckpointView;
  };
  return body.checkpointView;
}

describe('Checkpoint coordination API', () => {
  it('returns ordered current/upcoming Checkpoints with explicit counts', async () => {
    const checkpoints = checkpointRepository();
    const response = await handleRequest(
      request('/v1/rides/ride-1/checkpoints', 'GET', 'member-token'),
      {},
      dependencies(
        ride(),
        activeMemberships(),
        new MemoryRoutePlanRepository(routePlan()),
        checkpoints,
      ),
    );

    expect(response.status).toBe(200);
    const view = await readView(response);

    expect(view.routePlanId).toBe('plan-2');
    expect(view.routePlanRevision).toBe(2);
    expect(view.checkpoints).toHaveLength(2);
    expect(view.checkpoints[0]).toMatchObject({
      checkpointId: 'cp-fuel',
      state: 'current',
      expectedCount: 2,
      checkedInCount: 0,
      missingCount: 2,
      currentRiderCheckedIn: false,
    });
    expect(view.checkpoints[1]).toMatchObject({
      checkpointId: 'cp-regroup',
      state: 'upcoming',
    });
  });

  it('rejects invited-only Riders from private Checkpoint state', async () => {
    const response = await handleRequest(
      request('/v1/rides/ride-1/checkpoints', 'GET', 'member-token'),
      {},
      dependencies(
        ride(),
        activeMemberships('invited'),
        new MemoryRoutePlanRepository(routePlan()),
        checkpointRepository(),
      ),
    );

    expect(response.status).toBe(403);
  });

  it('records only the authenticated Rider manual check-in idempotently', async () => {
    const checkpoints = checkpointRepository();
    const deps = dependencies(
      ride(),
      activeMemberships(),
      new MemoryRoutePlanRepository(routePlan()),
      checkpoints,
    );

    const first = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-fuel/check-in',
        'POST',
        'member-token',
      ),
      {},
      deps,
    );
    expect(first.status).toBe(200);

    const repeated = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-fuel/check-in',
        'POST',
        'member-token',
      ),
      {},
      deps,
    );
    expect(repeated.status).toBe(200);

    expect(checkpoints.checkIns.size).toBe(1);
    const checkIn = [...checkpoints.checkIns.values()][0];
    expect(checkIn).toMatchObject({
      routePlanId: 'plan-2',
      checkpointId: 'cp-fuel',
      riderId: member.id,
      method: 'manual',
      checkedInAt: '2026-09-18T10:00:00.000Z',
    });

    const view = await readView(repeated);
    expect(view.checkpoints[0]).toMatchObject({
      checkedInCount: 1,
      missingCount: 1,
      currentRiderCheckedIn: true,
    });
  });

  it('rejects Checkpoint IDs outside the current immutable RoutePlan', async () => {
    const checkpoints = checkpointRepository();
    const response = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-old/check-in',
        'POST',
        'member-token',
      ),
      {},
      dependencies(
        ride(),
        activeMemberships(),
        new MemoryRoutePlanRepository(routePlan()),
        checkpoints,
      ),
    );

    expect(response.status).toBe(404);
    expect(checkpoints.checkIns.size).toBe(0);
  });

  it('allows Leader release with missing Riders and advances current Checkpoint', async () => {
    const checkpoints = checkpointRepository();
    const response = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-fuel/release',
        'POST',
        'leader-token',
      ),
      {},
      dependencies(
        ride(),
        activeMemberships(),
        new MemoryRoutePlanRepository(routePlan()),
        checkpoints,
      ),
    );

    expect(response.status).toBe(200);
    const view = await readView(response);
    expect(view.checkpoints[0]).toMatchObject({
      state: 'released',
      missingCount: 2,
      releasedAt: '2026-09-18T10:00:00.000Z',
    });
    expect(view.checkpoints[1]).toMatchObject({
      state: 'current',
    });
  });

  it('rejects release by a non-Leader', async () => {
    const checkpoints = checkpointRepository();
    const response = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-fuel/release',
        'POST',
        'member-token',
      ),
      {},
      dependencies(
        ride(),
        activeMemberships(),
        new MemoryRoutePlanRepository(routePlan()),
        checkpoints,
      ),
    );

    expect(response.status).toBe(403);
    expect(checkpoints.releases.size).toBe(0);
  });

  it('enforces release sequence while keeping repeated release idempotent', async () => {
    const checkpoints = checkpointRepository();
    const deps = dependencies(
      ride(),
      activeMemberships(),
      new MemoryRoutePlanRepository(routePlan()),
      checkpoints,
    );

    const earlySecond = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-regroup/release',
        'POST',
        'leader-token',
      ),
      {},
      deps,
    );
    expect(earlySecond.status).toBe(409);

    const first = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-fuel/release',
        'POST',
        'leader-token',
      ),
      {},
      deps,
    );
    expect(first.status).toBe(200);

    const repeatedFirst = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-fuel/release',
        'POST',
        'leader-token',
      ),
      {},
      deps,
    );
    expect(repeatedFirst.status).toBe(200);

    const second = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-regroup/release',
        'POST',
        'leader-token',
      ),
      {},
      deps,
    );
    expect(second.status).toBe(200);
    expect(checkpoints.releases.size).toBe(2);

    const view = await readView(second);
    expect(
      view.checkpoints.map((checkpoint) => checkpoint.state),
    ).toEqual(['released', 'released']);
  });

  it('allows Completed Ride reads but rejects later mutation', async () => {
    const checkpoints = checkpointRepository();
    const deps = dependencies(
      ride('completed'),
      activeMemberships('finished'),
      new MemoryRoutePlanRepository(routePlan()),
      checkpoints,
    );

    const read = await handleRequest(
      request('/v1/rides/ride-1/checkpoints', 'GET', 'member-token'),
      {},
      deps,
    );
    expect(read.status).toBe(200);

    const mutate = await handleRequest(
      request(
        '/v1/rides/ride-1/checkpoints/cp-fuel/check-in',
        'POST',
        'member-token',
      ),
      {},
      deps,
    );
    expect(mutate.status).toBe(409);
    expect(checkpoints.checkIns.size).toBe(0);
  });

  it('requires a saved RoutePlan before operational Checkpoint state exists', async () => {
    const response = await handleRequest(
      request('/v1/rides/ride-1/checkpoints', 'GET', 'leader-token'),
      {},
      dependencies(
        ride(),
        activeMemberships(),
        new MemoryRoutePlanRepository(null),
        checkpointRepository(),
      ),
    );

    expect(response.status).toBe(409);
  });
});
