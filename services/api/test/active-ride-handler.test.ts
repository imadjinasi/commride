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
  RideStatus,
} from '../src/clubs-rides/models';
import type { ClubRideRepository } from '../src/clubs-rides/repository';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import { handleRequest } from '../src/router';

const rider: RiderProfile = {
  id: 'rider-1',
  authSubject: 'auth-rider-1',
  displayName: 'Rider One',
  callsign: 'Sweep',
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

class TestIdentityVerifier implements IdentityVerifier {
  async verify(_token: string): Promise<AuthenticatedIdentity> {
    return { subject: rider.authSubject };
  }
}

class TestRiderRepository implements RiderRepository {
  async findByAuthSubject(subject: string): Promise<RiderProfile | null> {
    return subject === rider.authSubject ? rider : null;
  }

  async findById(riderId: string): Promise<RiderProfile | null> {
    return riderId === rider.id ? rider : null;
  }

  async upsertProfile(
    _input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    throw new Error('Not used.');
  }
}

class RecordingActiveRideGateway implements ActiveRideGateway {
  connects: Array<{
    rideId: string;
    participant: ActiveRideParticipant;
  }> = [];
  ends: Array<{ rideId: string; endedAt: string }> = [];

  async connect(
    _request: Request,
    rideId: string,
    participant: ActiveRideParticipant,
  ): Promise<Response> {
    this.connects.push({ rideId, participant });
    return new Response('connected', { status: 200 });
  }

  async endRide(rideId: string, endedAt: string): Promise<void> {
    this.ends.push({ rideId, endedAt });
  }
}

function ride(status: RideStatus): Ride {
  return {
    id: 'ride-1',
    clubId: 'club-1',
    createdByRiderId: rider.id,
    title: 'Active Ride',
    status,
    scheduledStartAt: null,
    actualStartAt:
      status === 'active' || status === 'completed'
        ? '2026-09-18T09:00:00Z'
        : null,
    endedAt:
      status === 'completed' ? '2026-09-18T10:00:00Z' : null,
    notes: null,
    createdAt: '2026-09-18T00:00:00Z',
    updatedAt: '2026-09-18T00:00:00Z',
  };
}

function membership(
  status: RideMembership['status'] = 'active',
  role: RideMembership['role'] = 'sweeper',
): RideMembership {
  return {
    rideId: 'ride-1',
    riderId: rider.id,
    role,
    status,
  };
}

function repository(
  initialStatus: RideStatus,
  membershipStatus: RideMembership['status'] = 'active',
  membershipRole: RideMembership['role'] = 'sweeper',
): ClubRideRepository {
  let currentRide = ride(initialStatus);

  return {
    async findRide(rideId: string) {
      return rideId === currentRide.id ? currentRide : null;
    },
    async findRideMembership(rideId: string, riderId: string) {
      return rideId === currentRide.id && riderId === rider.id
        ? membership(membershipStatus, membershipRole)
        : null;
    },
    async transitionRideStatus(
      rideId: string,
      expectedStatus: RideStatus,
      nextStatus: RideStatus,
      timestamp: string,
    ) {
      if (
        rideId !== currentRide.id ||
        currentRide.status !== expectedStatus
      ) {
        return currentRide;
      }

      currentRide = {
        ...currentRide,
        status: nextStatus,
        endedAt:
          nextStatus === 'completed' ? timestamp : currentRide.endedAt,
        actualStartAt:
          nextStatus === 'active'
            ? timestamp
            : currentRide.actualStartAt,
      };
      return currentRide;
    },
  } as unknown as ClubRideRepository;
}

function liveRequest(version = '1'): Request {
  return new Request(
    `https://commride.invalid/v1/rides/ride-1/live?v=${version}`,
    {
      method: 'GET',
      headers: {
        authorization: 'Bearer test-token',
        upgrade: 'websocket',
      },
    },
  );
}

function overrides(
  clubRideRepository: ClubRideRepository,
  gateway: ActiveRideGateway,
) {
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository,
    activeRideGateway: gateway,
    now: () => new Date('2026-09-18T10:00:00Z'),
  };
}

describe('Active Ride public boundary', () => {
  it('forwards an authorized Active Ride participant to the room', async () => {
    const gateway = new RecordingActiveRideGateway();

    const response = await handleRequest(
      liveRequest(),
      {},
      overrides(repository('active'), gateway),
    );

    expect(response.status).toBe(200);
    expect(gateway.connects).toEqual([
      {
        rideId: 'ride-1',
        participant: {
          riderId: rider.id,
          displayName: rider.displayName,
          role: 'sweeper',
        },
      },
    ]);
  });

  it('rejects a non-Active Ride before any realtime data is disclosed', async () => {
    const gateway = new RecordingActiveRideGateway();

    const response = await handleRequest(
      liveRequest(),
      {},
      overrides(repository('published'), gateway),
    );

    expect(response.status).toBe(409);
    expect(gateway.connects).toHaveLength(0);
  });

  it('rejects invited-only Ride membership', async () => {
    const gateway = new RecordingActiveRideGateway();

    const response = await handleRequest(
      liveRequest(),
      {},
      overrides(repository('active', 'invited'), gateway),
    );

    expect(response.status).toBe(403);
    expect(gateway.connects).toHaveLength(0);
  });

  it('rejects unsupported protocol version before gateway connection', async () => {
    const gateway = new RecordingActiveRideGateway();

    const response = await handleRequest(
      liveRequest('2'),
      {},
      overrides(repository('active'), gateway),
    );

    expect(response.status).toBe(400);
    expect(gateway.connects).toHaveLength(0);
  });

  it('signals the realtime room after End Ride becomes authoritative', async () => {
    const gateway = new RecordingActiveRideGateway();

    const response = await handleRequest(
      new Request(
        'https://commride.invalid/v1/rides/ride-1/end',
        {
          method: 'POST',
          headers: {
            authorization: 'Bearer test-token',
          },
        },
      ),
      {},
      overrides(repository('active', 'active', 'leader'), gateway),
    );

    expect(response.status).toBe(200);
    expect(gateway.ends).toEqual([
      {
        rideId: 'ride-1',
        endedAt: '2026-09-18T10:00:00.000Z',
      },
    ]);
  });

  it('retries room termination for an idempotent repeated End Ride', async () => {
    const gateway = new RecordingActiveRideGateway();

    const response = await handleRequest(
      new Request(
        'https://commride.invalid/v1/rides/ride-1/end',
        {
          method: 'POST',
          headers: {
            authorization: 'Bearer test-token',
          },
        },
      ),
      {},
      overrides(repository('completed', 'active', 'leader'), gateway),
    );

    expect(response.status).toBe(200);
    expect(gateway.ends).toHaveLength(1);
    expect(gateway.ends[0]?.rideId).toBe('ride-1');
  });
});
