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
import {
  IntercomProviderError,
  type IntercomParticipantInput,
  type IntercomRoomProvider,
  RealtimeKitRoomProvider,
} from '../src/intercom/provider';
import {
  D1IntercomRoomRepository,
  type IntercomRoomRecord,
  type IntercomRoomRepository,
} from '../src/intercom/repository';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import { handleRequest } from '../src/router';
import { createSqliteD1 } from './support/sqlite-d1';

const rider: RiderProfile = {
  id: 'rider-1',
  authSubject: 'auth-rider-1',
  displayName: 'Rider One',
  callsign: 'Sweep',
  homeArea: 'Cirebon',
  createdAt: '2026-10-16T00:00:00Z',
  updatedAt: '2026-10-16T00:00:00Z',
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

class RecordingProvider implements IntercomRoomProvider {
  readonly name = 'cloudflare_realtimekit' as const;
  readonly clientBaseDomain = 'realtime.cloudflare.com';
  rooms: string[] = [];
  participants: IntercomParticipantInput[] = [];

  constructor(private readonly failing = false) {}

  async createRoom(title: string): Promise<string> {
    if (this.failing) throw new IntercomProviderError('down', 500);
    this.rooms.push(title);
    return `meeting-${this.rooms.length}`;
  }

  async addParticipant(input: IntercomParticipantInput): Promise<string> {
    this.participants.push(input);
    return `token-${this.participants.length}`;
  }
}

class MemoryRoomRepository implements IntercomRoomRepository {
  records = new Map<string, IntercomRoomRecord>();

  async find(rideId: string): Promise<IntercomRoomRecord | null> {
    return this.records.get(rideId) ?? null;
  }

  async insertIfAbsent(
    record: IntercomRoomRecord,
  ): Promise<IntercomRoomRecord> {
    if (!this.records.has(record.rideId)) {
      this.records.set(record.rideId, record);
    }
    return this.records.get(record.rideId)!;
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
    actualStartAt: status === 'active' ? '2026-10-16T09:00:00Z' : null,
    endedAt: null,
    notes: null,
    createdAt: '2026-10-16T00:00:00Z',
    updatedAt: '2026-10-16T00:00:00Z',
  };
}

function rides(
  status: RideStatus,
  membershipStatus: RideMembership['status'] | null = 'joined',
  role: RideMembership['role'] = 'member',
): ClubRideRepository {
  return {
    async findRide(rideId: string) {
      return rideId === 'ride-1' ? ride(status) : null;
    },
    async findRideMembership(rideId: string, riderId: string) {
      return rideId === 'ride-1' &&
        riderId === rider.id &&
        membershipStatus != null
        ? { rideId, riderId, role, status: membershipStatus }
        : null;
    },
  } as unknown as ClubRideRepository;
}

function tokenRequest(method = 'POST', rideId = 'ride-1'): Request {
  return new Request(
    `https://commride.invalid/v1/rides/${rideId}/intercom/token`,
    { method, headers: { authorization: 'Bearer test-token' } },
  );
}

function overrides(
  clubRideRepository: ClubRideRepository,
  provider: IntercomRoomProvider | null = new RecordingProvider(),
  roomRepository: IntercomRoomRepository = new MemoryRoomRepository(),
) {
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository,
    intercomRoomProvider: provider,
    intercomRoomRepository: roomRepository,
    now: () => new Date('2026-10-16T10:00:00Z'),
  };
}

async function errorCode(response: Response): Promise<string> {
  const body = (await response.json()) as { error: { code: string } };
  return body.error.code;
}

describe('Ride intercom token endpoint', () => {
  it('mints a Rider token in the Ride room for an Active participant', async () => {
    const provider = new RecordingProvider();
    const response = await handleRequest(
      tokenRequest(),
      {},
      overrides(rides('active'), provider),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(await response.json()).toEqual({
      intercom: {
        provider: 'cloudflare_realtimekit',
        authToken: 'token-1',
        baseDomain: 'realtime.cloudflare.com',
        role: 'rider',
        canModerate: false,
      },
    });
    expect(provider.participants).toEqual([
      {
        roomId: 'meeting-1',
        riderId: rider.id,
        displayName: 'Sweep',
        preset: 'rider',
      },
    ]);
  });

  it('gives the Leader the moderator preset', async () => {
    const provider = new RecordingProvider();
    const response = await handleRequest(
      tokenRequest(),
      {},
      overrides(rides('active', 'ready', 'leader'), provider),
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      intercom: { role: string; canModerate: boolean };
    };
    expect(body.intercom.role).toBe('leader');
    expect(body.intercom.canModerate).toBe(true);
    expect(provider.participants[0]?.preset).toBe('leader');
  });

  it.each(['sweeper', 'navigator'] as const)(
    'keeps the %s on the Rider preset',
    async (role) => {
      const provider = new RecordingProvider();
      await handleRequest(
        tokenRequest(),
        {},
        overrides(rides('active', 'joined', role), provider),
      );
      expect(provider.participants[0]?.preset).toBe('rider');
    },
  );

  it('reuses one provider room per Ride', async () => {
    const provider = new RecordingProvider();
    const rooms = new MemoryRoomRepository();
    const deps = overrides(rides('active'), provider, rooms);

    await handleRequest(tokenRequest(), {}, deps);
    await handleRequest(tokenRequest(), {}, deps);

    expect(provider.rooms).toHaveLength(1);
    expect(provider.participants.map((p) => p.roomId)).toEqual([
      'meeting-1',
      'meeting-1',
    ]);
    expect(rooms.records.get('ride-1')).toEqual({
      rideId: 'ride-1',
      provider: 'cloudflare_realtimekit',
      providerRoomId: 'meeting-1',
      createdAt: '2026-10-16T10:00:00.000Z',
    });
  });

  it.each(['published', 'completed', 'draft'] as const)(
    'refuses a %s Ride',
    async (status) => {
      const provider = new RecordingProvider();
      const response = await handleRequest(
        tokenRequest(),
        {},
        overrides(rides(status), provider),
      );
      expect(response.status).toBe(409);
      expect(await errorCode(response)).toBe('active_ride_required');
      expect(provider.participants).toHaveLength(0);
    },
  );

  it.each([null, 'invited', 'left', 'finished'] as const)(
    'refuses a Rider whose membership is %s',
    async (membershipStatus) => {
      const provider = new RecordingProvider();
      const response = await handleRequest(
        tokenRequest(),
        {},
        overrides(rides('active', membershipStatus), provider),
      );
      expect(response.status).toBe(403);
      expect(await errorCode(response)).toBe('ride_membership_required');
      expect(provider.rooms).toHaveLength(0);
    },
  );

  it('returns 404 for an unknown Ride', async () => {
    const response = await handleRequest(
      tokenRequest('POST', 'ride-x'),
      {},
      overrides(rides('active')),
    );
    expect(response.status).toBe(404);
  });

  it('requires authentication', async () => {
    const response = await handleRequest(
      new Request('https://commride.invalid/v1/rides/ride-1/intercom/token', {
        method: 'POST',
      }),
      {},
      overrides(rides('active')),
    );
    expect(response.status).toBe(401);
  });

  it('rejects GET', async () => {
    const response = await handleRequest(
      tokenRequest('GET'),
      {},
      overrides(rides('active')),
    );
    expect(response.status).toBe(405);
  });

  it('reports a missing provider configuration as 503', async () => {
    const response = await handleRequest(
      tokenRequest(),
      {},
      overrides(rides('active'), null),
    );
    expect(response.status).toBe(503);
    expect(await errorCode(response)).toBe('intercom_not_configured');
  });

  it('is unconfigured when the Worker has no RealtimeKit secrets', async () => {
    const response = await handleRequest(tokenRequest(), {}, {
      ...overrides(rides('active')),
      intercomRoomProvider: undefined,
    });
    expect(response.status).toBe(503);
    expect(await errorCode(response)).toBe('intercom_not_configured');
  });

  it('maps provider failure to 502 without leaking details', async () => {
    const response = await handleRequest(
      tokenRequest(),
      {},
      overrides(rides('active'), new RecordingProvider(true)),
    );
    expect(response.status).toBe(502);
    const text = await response.text();
    expect(text).toContain('intercom_provider_unavailable');
    expect(text).not.toContain('down');
  });
});

describe('RealtimeKitRoomProvider', () => {
  const config = {
    accountId: 'acct',
    appId: 'app',
    apiToken: 'secret-token',
    riderPreset: 'commride_rider',
    leaderPreset: 'commride_leader',
  };

  function recordingFetch(body: unknown, status = 200) {
    const calls: Array<{ url: string; init: RequestInit | undefined }> = [];
    const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
      calls.push({ url: String(input), init });
      return new Response(JSON.stringify(body), { status });
    }) as typeof fetch;
    return { calls, fetcher };
  }

  it('creates a meeting with the API token server-side', async () => {
    const { calls, fetcher } = recordingFetch({
      success: true,
      data: { id: 'meeting-9' },
    });
    const provider = new RealtimeKitRoomProvider(config, fetcher);

    expect(await provider.createRoom('CommRide Ride ride-1')).toBe(
      'meeting-9',
    );
    expect(calls[0]?.url).toBe(
      'https://api.cloudflare.com/client/v4/accounts/acct/realtime/kit/app/meetings',
    );
    expect(calls[0]?.init?.method).toBe('POST');
    expect(
      (calls[0]?.init?.headers as Record<string, string>).authorization,
    ).toBe('Bearer secret-token');
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      title: 'CommRide Ride ride-1',
    });
  });

  it('adds a participant with the role preset and returns its token', async () => {
    const { calls, fetcher } = recordingFetch({
      success: true,
      data: { id: 'p-1', token: 'auth-token' },
    });
    const provider = new RealtimeKitRoomProvider(config, fetcher);

    const token = await provider.addParticipant({
      roomId: 'meeting-9',
      riderId: 'rider-1',
      displayName: 'Sweep',
      preset: 'leader',
    });

    expect(token).toBe('auth-token');
    expect(calls[0]?.url).toBe(
      'https://api.cloudflare.com/client/v4/accounts/acct/realtime/kit/app/meetings/meeting-9/participants',
    );
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      name: 'Sweep',
      custom_participant_id: 'rider-1',
      preset_name: 'commride_leader',
    });
  });

  it('throws a provider error on HTTP failure or a rejected envelope', async () => {
    const failing = new RealtimeKitRoomProvider(
      config,
      recordingFetch({}, 401).fetcher,
    );
    await expect(failing.createRoom('x')).rejects.toBeInstanceOf(
      IntercomProviderError,
    );

    const rejected = new RealtimeKitRoomProvider(
      config,
      recordingFetch({ success: false }).fetcher,
    );
    await expect(rejected.createRoom('x')).rejects.toBeInstanceOf(
      IntercomProviderError,
    );
  });
});

describe('D1IntercomRoomRepository', () => {
  it('keeps the first stored room when two first joins race', async () => {
    const db = await createSqliteD1();
    db.exec(`
      INSERT INTO riders(id, auth_subject, display_name) VALUES
        ('rider-a', 'firebase-a', 'Rider A');
      INSERT INTO clubs(id, created_by_rider_id, name, slug) VALUES
        ('club-x', 'rider-a', 'Club X', 'club-x');
      INSERT INTO rides(id, club_id, created_by_rider_id, title, status,
                        actual_start_at) VALUES
        ('ride-1', 'club-x', 'rider-a', 'R1', 'active', '2026-10-16T09:00:00Z');
    `);
    const repository = new D1IntercomRoomRepository(db.d1);

    expect(await repository.find('ride-1')).toBeNull();
    const first = await repository.insertIfAbsent({
      rideId: 'ride-1',
      provider: 'cloudflare_realtimekit',
      providerRoomId: 'meeting-a',
      createdAt: '2026-10-16T10:00:00Z',
    });
    const second = await repository.insertIfAbsent({
      rideId: 'ride-1',
      provider: 'cloudflare_realtimekit',
      providerRoomId: 'meeting-b',
      createdAt: '2026-10-16T10:00:01Z',
    });

    expect(first.providerRoomId).toBe('meeting-a');
    expect(second.providerRoomId).toBe('meeting-a');
  });
});
