import { describe, expect, it } from 'vitest';

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
import type { RiderProfile, UpsertRiderProfileInput } from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import type { RideRecap } from '../src/ride-recap/models';
import type { RideRecapRepository } from '../src/ride-recap/repository';
import { handleRequest } from '../src/router';

const participant: RiderProfile = {
  id: 'rider-1',
  authSubject: 'auth-rider-1',
  displayName: 'Rider One',
  callsign: 'R1',
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

const outsider: RiderProfile = {
  id: 'rider-outside',
  authSubject: 'auth-outside',
  displayName: 'Outside Rider',
  callsign: null,
  homeArea: null,
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

class TestIdentityVerifier implements IdentityVerifier {
  async verify(token: string): Promise<AuthenticatedIdentity> {
    if (token === 'participant-token') {
      return { subject: participant.authSubject };
    }
    if (token === 'outsider-token') {
      return { subject: outsider.authSubject };
    }
    throw new Error('Unknown token');
  }
}

class TestRiderRepository implements RiderRepository {
  async findByAuthSubject(subject: string): Promise<RiderProfile | null> {
    return [participant, outsider].find(
      (rider) => rider.authSubject === subject,
    ) ?? null;
  }

  async findById(riderId: string): Promise<RiderProfile | null> {
    return [participant, outsider].find(
      (rider) => rider.id === riderId,
    ) ?? null;
  }

  async upsertProfile(
    _input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    throw new Error('Not used.');
  }
}

class MemoryClubRideRepository {
  constructor(private readonly status: RideStatus = 'completed') {}

  async findRide(rideId: string): Promise<Ride | null> {
    if (rideId !== 'ride-1') {
      return null;
    }
    return {
      id: 'ride-1',
      clubId: 'club-1',
      createdByRiderId: participant.id,
      title: 'Sunday Ride',
      status: this.status,
      scheduledStartAt: null,
      actualStartAt:
        this.status === 'active' || this.status === 'completed'
          ? '2026-09-18T09:00:00Z'
          : null,
      endedAt:
        this.status === 'completed' ? '2026-09-18T12:00:00Z' : null,
      notes: null,
      createdAt: '2026-09-18T00:00:00Z',
      updatedAt: '2026-09-18T12:00:00Z',
    };
  }

  async findRideMembership(
    rideId: string,
    riderId: string,
  ): Promise<RideMembership | null> {
    if (rideId !== 'ride-1' || riderId !== participant.id) {
      return null;
    }
    return {
      rideId,
      riderId,
      role: 'leader',
      status: 'active',
    };
  }
}

class MemoryRecapRepository implements RideRecapRepository {
  calls = 0;

  constructor(private readonly value: RideRecap = recap()) {}

  async build(
    rideId: string,
    generatedAt: string,
  ): Promise<RideRecap | null> {
    this.calls += 1;
    return {
      ...this.value,
      rideId,
      generatedAt,
    };
  }
}

function recap(): RideRecap {
  return {
    rideId: 'ride-1',
    title: 'Sunday Ride',
    actualStartAt: '2026-09-18T09:00:00Z',
    endedAt: '2026-09-18T12:00:00Z',
    durationSeconds: 10_800,
    participants: [
      {
        riderId: participant.id,
        displayName: participant.displayName,
        role: 'leader',
        membershipStatus: 'active',
      },
    ],
    plannedRoute: {
      routePlanId: 'plan-1',
      revision: 1,
      originLabel: 'Cirebon',
      destinationLabel: 'Kuningan',
      distanceMeters: 42_000,
      durationSeconds: 3600,
      stopCount: 2,
    },
    journey: {
      sampleCount: 0,
      trackedRiderCount: 0,
      firstObservedAt: null,
      lastObservedAt: null,
      leaderTrackedDistanceMeters: null,
    },
    checkpoints: [],
    incidents: [],
    generatedAt: '2026-09-18T12:00:01Z',
  };
}

function request(
  token: 'participant-token' | 'outsider-token',
): Request {
  return new Request('https://commride.invalid/v1/rides/ride-1/recap', {
    headers: { authorization: `Bearer ${token}` },
  });
}

function dependencies(
  clubRide: MemoryClubRideRepository,
  recapRepository: RideRecapRepository,
) {
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository: clubRide as unknown as ClubRideRepository,
    rideRecapRepository: recapRepository,
    now: () => new Date('2026-09-18T12:00:01Z'),
  };
}

describe('Ride Recap API', () => {
  it('returns a completed Ride recap to a participating Rider', async () => {
    const repository = new MemoryRecapRepository();
    const response = await handleRequest(
      request('participant-token'),
      {},
      dependencies(new MemoryClubRideRepository(), repository),
    );

    expect(response.status).toBe(200);
    const body = await response.json() as {
      recap: RideRecap;
    };
    expect(body.recap).toMatchObject({
      rideId: 'ride-1',
      durationSeconds: 10_800,
      journey: {
        sampleCount: 0,
        trackedRiderCount: 0,
        leaderTrackedDistanceMeters: null,
      },
    });
    expect(repository.calls).toBe(1);
  });

  it('does not fabricate actual journey data when no samples exist', async () => {
    const response = await handleRequest(
      request('participant-token'),
      {},
      dependencies(
        new MemoryClubRideRepository(),
        new MemoryRecapRepository(),
      ),
    );

    const body = await response.json() as { recap: RideRecap };
    expect(body.recap.journey.firstObservedAt).toBeNull();
    expect(body.recap.journey.lastObservedAt).toBeNull();
    expect(body.recap.journey.leaderTrackedDistanceMeters).toBeNull();
  });

  it('rejects a Rider who did not participate', async () => {
    const repository = new MemoryRecapRepository();
    const response = await handleRequest(
      request('outsider-token'),
      {},
      dependencies(new MemoryClubRideRepository(), repository),
    );

    expect(response.status).toBe(403);
    expect(repository.calls).toBe(0);
  });

  it('keeps recap unavailable until End Ride succeeds', async () => {
    const repository = new MemoryRecapRepository();
    const response = await handleRequest(
      request('participant-token'),
      {},
      dependencies(
        new MemoryClubRideRepository('active'),
        repository,
      ),
    );

    expect(response.status).toBe(409);
    expect(repository.calls).toBe(0);
  });
});
