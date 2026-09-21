import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type {
  Club,
  ClubMembership,
  Ride,
  RideMembership,
} from '../src/clubs-rides/models';
import type {
  ClubListItem,
  RideListItem,
} from '../src/clubs-rides/read-models';
import type { ClubRideReadRepository } from '../src/clubs-rides/read-repository';
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
  callsign: null,
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

const club: Club = {
  id: 'club-1',
  createdByRiderId: rider.id,
  name: 'Cirebon Riders',
  slug: 'cirebon-riders',
  homeArea: 'Cirebon',
  description: null,
  visibility: 'private',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

const ride: Ride = {
  id: 'ride-1',
  clubId: club.id,
  createdByRiderId: rider.id,
  title: 'Sunday Morning Ride',
  status: 'draft',
  scheduledStartAt: '2026-09-20T23:00:00.000Z',
  actualStartAt: null,
  endedAt: null,
  notes: null,
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

class TestReadRepository implements ClubRideReadRepository {
  constructor(
    private readonly clubItem: ClubListItem,
    private readonly rideItems: readonly RideListItem[],
  ) {}

  async listClubsForRider(
    _riderId: string,
  ): Promise<readonly ClubListItem[]> {
    return [this.clubItem];
  }

  async listRidesForClub(
    _clubId: string,
    _riderId: string,
  ): Promise<readonly RideListItem[]> {
    return this.rideItems;
  }
}

function commandRepository(
  membership: ClubMembership,
): ClubRideRepository {
  return {
    async findClubMembership() {
      return membership;
    },
  } as unknown as ClubRideRepository;
}

function request(path: string): Request {
  return new Request(`https://commride.invalid${path}`, {
    headers: {
      authorization: 'Bearer test-token',
      'x-request-id': 'read-test',
    },
  });
}

describe('Club/Ride read model', () => {
  it('lists Clubs with current Rider membership', async () => {
    const membership: ClubMembership = {
      clubId: club.id,
      riderId: rider.id,
      role: 'owner',
      status: 'active',
    };

    const response = await handleRequest(request('/v1/clubs'), {}, {
      identityVerifier: new TestIdentityVerifier(),
      riderRepository: new TestRiderRepository(),
      clubRideRepository: commandRepository(membership),
      clubRideReadRepository: new TestReadRepository(
        { club, membership },
        [],
      ),
    });

    expect(response.status).toBe(200);
    const body = await response.json() as {
      clubs: ClubListItem[];
    };
    expect(body.clubs).toHaveLength(1);
    expect(body.clubs[0]?.club.name).toBe('Cirebon Riders');
    expect(body.clubs[0]?.membership.role).toBe('owner');
  });

  it('rejects Ride listing before Club invitation is accepted', async () => {
    const membership: ClubMembership = {
      clubId: club.id,
      riderId: rider.id,
      role: 'member',
      status: 'invited',
    };

    const response = await handleRequest(
      request('/v1/clubs/club-1/rides'),
      {},
      {
        identityVerifier: new TestIdentityVerifier(),
        riderRepository: new TestRiderRepository(),
        clubRideRepository: commandRepository(membership),
        clubRideReadRepository: new TestReadRepository(
          { club, membership },
          [],
        ),
      },
    );

    expect(response.status).toBe(403);
  });

  it('lists Club Rides and the current Ride membership', async () => {
    const clubMembership: ClubMembership = {
      clubId: club.id,
      riderId: rider.id,
      role: 'owner',
      status: 'active',
    };
    const rideMembership: RideMembership = {
      rideId: ride.id,
      riderId: rider.id,
      role: 'leader',
      status: 'joined',
    };

    const response = await handleRequest(
      request('/v1/clubs/club-1/rides'),
      {},
      {
        identityVerifier: new TestIdentityVerifier(),
        riderRepository: new TestRiderRepository(),
        clubRideRepository: commandRepository(clubMembership),
        clubRideReadRepository: new TestReadRepository(
          { club, membership: clubMembership },
          [
            {
              ride,
              membership: rideMembership,
            },
          ],
        ),
      },
    );

    expect(response.status).toBe(200);
    const body = await response.json() as {
      rides: RideListItem[];
    };
    expect(body.rides).toHaveLength(1);
    expect(body.rides[0]?.ride.status).toBe('draft');
    expect(body.rides[0]?.membership?.role).toBe('leader');
  });
});
