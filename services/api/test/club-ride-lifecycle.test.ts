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
  RideRole,
  RideStatus,
} from '../src/clubs-rides/models';
import type {
  ClubRideRepository,
  CreateClubInput,
  CreateRideInput,
} from '../src/clubs-rides/repository';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import { handleRequest } from '../src/router';

const riderOne: RiderProfile = {
  id: 'rider-1',
  authSubject: 'auth-rider-1',
  displayName: 'Leader One',
  callsign: 'Lead',
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

const riderTwo: RiderProfile = {
  id: 'rider-2',
  authSubject: 'auth-rider-2',
  displayName: 'Rider Two',
  callsign: 'Sweep',
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

class TokenIdentityVerifier implements IdentityVerifier {
  async verify(token: string): Promise<AuthenticatedIdentity> {
    if (token === 'token-1') {
      return { subject: riderOne.authSubject };
    }

    if (token === 'token-2') {
      return { subject: riderTwo.authSubject };
    }

    throw new Error('Unexpected token in lifecycle test.');
  }
}

class MemoryRiderRepository implements RiderRepository {
  private readonly riders = [riderOne, riderTwo];

  async findByAuthSubject(
    authSubject: string,
  ): Promise<RiderProfile | null> {
    return (
      this.riders.find((rider) => rider.authSubject === authSubject) ?? null
    );
  }

  async findById(riderId: string): Promise<RiderProfile | null> {
    return this.riders.find((rider) => rider.id === riderId) ?? null;
  }

  async upsertProfile(
    _input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    throw new Error('Not used in lifecycle tests.');
  }
}

class MemoryClubRideRepository implements ClubRideRepository {
  readonly clubs = new Map<string, Club>();
  readonly clubMemberships = new Map<string, ClubMembership>();
  readonly rides = new Map<string, Ride>();
  readonly rideMemberships = new Map<string, RideMembership>();

  async createClubWithOwner(input: CreateClubInput): Promise<Club> {
    const club: Club = {
      id: input.clubId,
      createdByRiderId: input.creatorRiderId,
      name: input.name,
      slug: input.slug,
      homeArea: input.homeArea,
      description: null,
      visibility: input.visibility,
      createdAt: '2026-09-18T00:00:00Z',
      updatedAt: '2026-09-18T00:00:00Z',
    };
    this.clubs.set(club.id, club);
    this.clubMemberships.set(
      membershipKey(club.id, input.creatorRiderId),
      {
        clubId: club.id,
        riderId: input.creatorRiderId,
        role: 'owner',
        status: 'active',
      },
    );
    return club;
  }

  async findClubMembership(
    clubId: string,
    riderId: string,
  ): Promise<ClubMembership | null> {
    return this.clubMemberships.get(membershipKey(clubId, riderId)) ?? null;
  }

  async inviteClubMember(
    clubId: string,
    riderId: string,
    role: 'admin' | 'member',
  ): Promise<ClubMembership> {
    const membership: ClubMembership = {
      clubId,
      riderId,
      role,
      status: 'invited',
    };
    this.clubMemberships.set(membershipKey(clubId, riderId), membership);
    return membership;
  }

  async acceptClubInvite(
    clubId: string,
    riderId: string,
  ): Promise<ClubMembership | null> {
    const existing = await this.findClubMembership(clubId, riderId);
    if (existing?.status !== 'invited') {
      return existing;
    }

    const membership: ClubMembership = {
      ...existing,
      status: 'active',
    };
    this.clubMemberships.set(membershipKey(clubId, riderId), membership);
    return membership;
  }

  async createRideWithLeader(input: CreateRideInput): Promise<Ride> {
    const ride: Ride = {
      id: input.rideId,
      clubId: input.clubId,
      createdByRiderId: input.creatorRiderId,
      title: input.title,
      status: 'draft',
      scheduledStartAt: input.scheduledStartAt,
      actualStartAt: null,
      endedAt: null,
      notes: input.notes,
      createdAt: '2026-09-18T00:00:00Z',
      updatedAt: '2026-09-18T00:00:00Z',
    };
    this.rides.set(ride.id, ride);
    this.rideMemberships.set(
      membershipKey(ride.id, input.creatorRiderId),
      {
        rideId: ride.id,
        riderId: input.creatorRiderId,
        role: 'leader',
        status: 'joined',
      },
    );
    return ride;
  }

  async findRide(rideId: string): Promise<Ride | null> {
    return this.rides.get(rideId) ?? null;
  }

  async findRideMembership(
    rideId: string,
    riderId: string,
  ): Promise<RideMembership | null> {
    return this.rideMemberships.get(membershipKey(rideId, riderId)) ?? null;
  }

  async inviteRideMember(
    rideId: string,
    riderId: string,
    role: Exclude<RideRole, 'leader'>,
  ): Promise<RideMembership> {
    const membership: RideMembership = {
      rideId,
      riderId,
      role,
      status: 'invited',
    };
    this.rideMemberships.set(membershipKey(rideId, riderId), membership);
    return membership;
  }

  async acceptRideInvite(
    rideId: string,
    riderId: string,
  ): Promise<RideMembership | null> {
    const existing = await this.findRideMembership(rideId, riderId);
    if (existing?.status !== 'invited') {
      return existing;
    }

    const membership: RideMembership = {
      ...existing,
      status: 'joined',
    };
    this.rideMemberships.set(membershipKey(rideId, riderId), membership);
    return membership;
  }

  async transitionRideStatus(
    rideId: string,
    expectedStatus: RideStatus,
    nextStatus: RideStatus,
    timestamp: string,
  ): Promise<Ride | null> {
    const existing = await this.findRide(rideId);
    if (existing == null || existing.status !== expectedStatus) {
      return existing;
    }

    const ride: Ride = {
      ...existing,
      status: nextStatus,
      actualStartAt:
        nextStatus === 'active' ? timestamp : existing.actualStartAt,
      endedAt:
        nextStatus === 'completed' ? timestamp : existing.endedAt,
      updatedAt: timestamp,
    };
    this.rides.set(ride.id, ride);
    return ride;
  }
}

function membershipKey(containerId: string, riderId: string): string {
  return `${containerId}:${riderId}`;
}

function request(
  path: string,
  token: 'token-1' | 'token-2',
  body?: unknown,
): Request {
  return new Request(`https://commride.invalid${path}`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      ...(body == null ? {} : { 'content-type': 'application/json' }),
    },
    ...(body == null ? {} : { body: JSON.stringify(body) }),
  });
}

function dependencies(repository: MemoryClubRideRepository) {
  let nextId = 1;

  return {
    identityVerifier: new TokenIdentityVerifier(),
    riderRepository: new MemoryRiderRepository(),
    clubRideRepository: repository,
    idFactory: () => `generated-${nextId++}`,
    now: () => new Date('2026-09-18T08:00:00.000Z'),
  };
}

describe('Club and Ride lifecycle API', () => {
  it('creates a Club and assigns its creator as active owner', async () => {
    const repository = new MemoryClubRideRepository();
    const response = await handleRequest(
      request('/v1/clubs', 'token-1', {
        name: 'Cirebon Riders',
        slug: 'cirebon-riders',
        visibility: 'private',
      }),
      {},
      dependencies(repository),
    );

    expect(response.status).toBe(201);
    const body = await response.json() as { club: Club };

    expect(body.club.id).toBe('generated-1');
    await expect(
      repository.findClubMembership(body.club.id, riderOne.id),
    ).resolves.toMatchObject({
      role: 'owner',
      status: 'active',
    });
  });

  it('requires Club admin authority to create a Ride', async () => {
    const repository = new MemoryClubRideRepository();
    const deps = dependencies(repository);

    const clubResponse = await handleRequest(
      request('/v1/clubs', 'token-1', {
        name: 'Cirebon Riders',
        slug: 'cirebon-riders',
      }),
      {},
      deps,
    );
    const club = (await clubResponse.json() as { club: Club }).club;

    const response = await handleRequest(
      request(`/v1/clubs/${club.id}/rides`, 'token-2', {
        title: 'Sunday Morning Ride',
      }),
      {},
      deps,
    );

    expect(response.status).toBe(403);
  });

  it('supports invite, join, and Leader-only Ride state transitions', async () => {
    const repository = new MemoryClubRideRepository();
    const deps = dependencies(repository);

    const clubResponse = await handleRequest(
      request('/v1/clubs', 'token-1', {
        name: 'Cirebon Riders',
        slug: 'cirebon-riders',
      }),
      {},
      deps,
    );
    const club = (await clubResponse.json() as { club: Club }).club;

    const rideResponse = await handleRequest(
      request(`/v1/clubs/${club.id}/rides`, 'token-1', {
        title: 'Sunday Morning Ride',
        scheduledStartAt: '2026-09-20T05:00:00+07:00',
      }),
      {},
      deps,
    );
    expect(rideResponse.status).toBe(201);
    const ride = (await rideResponse.json() as { ride: Ride }).ride;

    const inviteResponse = await handleRequest(
      request(`/v1/rides/${ride.id}/members/invite`, 'token-1', {
        riderId: riderTwo.id,
        role: 'sweeper',
      }),
      {},
      deps,
    );
    expect(inviteResponse.status).toBe(200);

    const joinResponse = await handleRequest(
      request(`/v1/rides/${ride.id}/join`, 'token-2'),
      {},
      deps,
    );
    expect(joinResponse.status).toBe(200);
    await expect(
      repository.findRideMembership(ride.id, riderTwo.id),
    ).resolves.toMatchObject({
      role: 'sweeper',
      status: 'joined',
    });

    const unauthorizedStart = await handleRequest(
      request(`/v1/rides/${ride.id}/start`, 'token-2'),
      {},
      deps,
    );
    expect(unauthorizedStart.status).toBe(403);

    const publish = await handleRequest(
      request(`/v1/rides/${ride.id}/publish`, 'token-1'),
      {},
      deps,
    );
    expect(publish.status).toBe(200);

    const start = await handleRequest(
      request(`/v1/rides/${ride.id}/start`, 'token-1'),
      {},
      deps,
    );
    expect(start.status).toBe(200);

    const repeatedStart = await handleRequest(
      request(`/v1/rides/${ride.id}/start`, 'token-1'),
      {},
      deps,
    );
    expect(repeatedStart.status).toBe(200);

    const end = await handleRequest(
      request(`/v1/rides/${ride.id}/end`, 'token-1'),
      {},
      deps,
    );
    expect(end.status).toBe(200);

    const repeatedEnd = await handleRequest(
      request(`/v1/rides/${ride.id}/end`, 'token-1'),
      {},
      deps,
    );
    expect(repeatedEnd.status).toBe(200);

    await expect(repository.findRide(ride.id)).resolves.toMatchObject({
      status: 'completed',
      actualStartAt: '2026-09-18T08:00:00.000Z',
      endedAt: '2026-09-18T08:00:00.000Z',
    });
  });

  it('cancels only pre-start Rides and keeps cancellation idempotent', async () => {
    const repository = new MemoryClubRideRepository();
    const deps = dependencies(repository);

    const clubResponse = await handleRequest(
      request('/v1/clubs', 'token-1', {
        name: 'Cirebon Riders',
        slug: 'cirebon-riders',
      }),
      {},
      deps,
    );
    const club = (await clubResponse.json() as { club: Club }).club;

    const draftResponse = await handleRequest(
      request(`/v1/clubs/${club.id}/rides`, 'token-1', {
        title: 'Cancelled Before Start',
      }),
      {},
      deps,
    );
    const draftRide = (await draftResponse.json() as { ride: Ride }).ride;

    const cancelDraft = await handleRequest(
      request(`/v1/rides/${draftRide.id}/cancel`, 'token-1'),
      {},
      deps,
    );
    expect(cancelDraft.status).toBe(200);

    const repeatedCancel = await handleRequest(
      request(`/v1/rides/${draftRide.id}/cancel`, 'token-1'),
      {},
      deps,
    );
    expect(repeatedCancel.status).toBe(200);
    await expect(repository.findRide(draftRide.id)).resolves.toMatchObject({
      status: 'cancelled',
      actualStartAt: null,
      endedAt: null,
    });

    const activeResponse = await handleRequest(
      request(`/v1/clubs/${club.id}/rides`, 'token-1', {
        title: 'Already Started',
      }),
      {},
      deps,
    );
    const activeRide = (await activeResponse.json() as { ride: Ride }).ride;

    await handleRequest(
      request(`/v1/rides/${activeRide.id}/publish`, 'token-1'),
      {},
      deps,
    );
    await handleRequest(
      request(`/v1/rides/${activeRide.id}/start`, 'token-1'),
      {},
      deps,
    );

    const cancelActive = await handleRequest(
      request(`/v1/rides/${activeRide.id}/cancel`, 'token-1'),
      {},
      deps,
    );
    expect(cancelActive.status).toBe(409);
    await expect(repository.findRide(activeRide.id)).resolves.toMatchObject({
      status: 'active',
    });
  });

  it('keeps Club administration separate from Ride leadership', async () => {
    const repository = new MemoryClubRideRepository();
    const deps = dependencies(repository);

    const clubResponse = await handleRequest(
      request('/v1/clubs', 'token-1', {
        name: 'Cirebon Riders',
        slug: 'cirebon-riders',
      }),
      {},
      deps,
    );
    const club = (await clubResponse.json() as { club: Club }).club;

    await handleRequest(
      request(`/v1/clubs/${club.id}/members/invite`, 'token-1', {
        riderId: riderTwo.id,
        role: 'admin',
      }),
      {},
      deps,
    );
    await handleRequest(
      request(`/v1/clubs/${club.id}/join`, 'token-2'),
      {},
      deps,
    );

    const rideResponse = await handleRequest(
      request(`/v1/clubs/${club.id}/rides`, 'token-2', {
        title: 'Admin-created Ride',
      }),
      {},
      deps,
    );

    expect(rideResponse.status).toBe(201);
    const ride = (await rideResponse.json() as { ride: Ride }).ride;

    const riderOneMembership = await repository.findRideMembership(
      ride.id,
      riderOne.id,
    );
    expect(riderOneMembership).toBeNull();

    const riderTwoMembership = await repository.findRideMembership(
      ride.id,
      riderTwo.id,
    );
    expect(riderTwoMembership).toMatchObject({
      role: 'leader',
      status: 'joined',
    });
  });
});
