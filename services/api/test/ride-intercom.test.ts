import { decodeJwt, decodeProtectedHeader, jwtVerify } from 'jose';
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
  type IntercomJoinInput,
  type IntercomRoomProvider,
  LiveKitRoomProvider,
  liveKitRoomName,
} from '../src/intercom/provider';
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
  readonly name = 'livekit' as const;
  readonly clientUrl = 'wss://commride.livekit.cloud';
  joins: IntercomJoinInput[] = [];
  mutes: Array<{ rideId: string; riderId: string }> = [];

  constructor(
    private readonly failing = false,
    private readonly publishing = true,
  ) {}

  async mintJoinToken(input: IntercomJoinInput): Promise<string> {
    if (this.failing) throw new IntercomProviderError('down', 500);
    this.joins.push(input);
    return `token-${this.joins.length}`;
  }

  async muteRider(rideId: string, riderId: string): Promise<boolean> {
    if (this.failing) throw new IntercomProviderError('down', 500);
    this.mutes.push({ rideId, riderId });
    return this.publishing;
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

function intercomRequest(
  action: 'token' | 'mute' = 'token',
  options: { method?: string; rideId?: string; body?: unknown } = {},
): Request {
  return new Request(
    `https://commride.invalid/v1/rides/${options.rideId ?? 'ride-1'}/intercom/${action}`,
    {
      method: options.method ?? 'POST',
      headers: { authorization: 'Bearer test-token' },
      body:
        options.body === undefined ? undefined : JSON.stringify(options.body),
    },
  );
}

function overrides(
  clubRideRepository: ClubRideRepository,
  provider: IntercomRoomProvider | null = new RecordingProvider(),
) {
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository,
    intercomRoomProvider: provider,
  };
}

async function errorCode(response: Response): Promise<string> {
  const body = (await response.json()) as { error: { code: string } };
  return body.error.code;
}

describe('Ride intercom token endpoint', () => {
  it('mints a Rider token for an Active participant', async () => {
    const provider = new RecordingProvider();
    const response = await handleRequest(
      intercomRequest(),
      {},
      overrides(rides('active'), provider),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(await response.json()).toEqual({
      intercom: {
        provider: 'livekit',
        serverUrl: 'wss://commride.livekit.cloud',
        authToken: 'token-1',
        role: 'rider',
        canModerate: false,
      },
    });
    expect(provider.joins).toEqual([
      { rideId: 'ride-1', riderId: rider.id, displayName: 'Sweep' },
    ]);
  });

  it('marks the Leader as moderator', async () => {
    const response = await handleRequest(
      intercomRequest(),
      {},
      overrides(rides('active', 'ready', 'leader')),
    );
    const body = (await response.json()) as {
      intercom: { role: string; canModerate: boolean };
    };
    expect(body.intercom).toMatchObject({ role: 'leader', canModerate: true });
  });

  it.each(['published', 'completed', 'draft'] as const)(
    'refuses a %s Ride',
    async (status) => {
      const provider = new RecordingProvider();
      const response = await handleRequest(
        intercomRequest(),
        {},
        overrides(rides(status), provider),
      );
      expect(response.status).toBe(409);
      expect(await errorCode(response)).toBe('active_ride_required');
      expect(provider.joins).toHaveLength(0);
    },
  );

  it.each([null, 'invited', 'left', 'finished'] as const)(
    'refuses a Rider whose membership is %s',
    async (membershipStatus) => {
      const provider = new RecordingProvider();
      const response = await handleRequest(
        intercomRequest(),
        {},
        overrides(rides('active', membershipStatus), provider),
      );
      expect(response.status).toBe(403);
      expect(await errorCode(response)).toBe('ride_membership_required');
      expect(provider.joins).toHaveLength(0);
    },
  );

  it('returns 404 for an unknown Ride', async () => {
    const response = await handleRequest(
      intercomRequest('token', { rideId: 'ride-x' }),
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
      intercomRequest('token', { method: 'GET' }),
      {},
      overrides(rides('active')),
    );
    expect(response.status).toBe(405);
  });

  it('reports a missing provider configuration as 503', async () => {
    const response = await handleRequest(
      intercomRequest(),
      {},
      overrides(rides('active'), null),
    );
    expect(response.status).toBe(503);
    expect(await errorCode(response)).toBe('intercom_not_configured');
  });

  it('is unconfigured when the Worker has no LiveKit secrets', async () => {
    const response = await handleRequest(
      intercomRequest(),
      { LIVEKIT_URL: 'wss://x.livekit.cloud', LIVEKIT_API_KEY: 'key' },
      { ...overrides(rides('active')), intercomRoomProvider: undefined },
    );
    expect(response.status).toBe(503);
    expect(await errorCode(response)).toBe('intercom_not_configured');
  });

  it('maps provider failure to 502 without leaking details', async () => {
    const response = await handleRequest(
      intercomRequest(),
      {},
      overrides(rides('active'), new RecordingProvider(true)),
    );
    expect(response.status).toBe(502);
    const text = await response.text();
    expect(text).toContain('intercom_provider_unavailable');
    expect(text).not.toContain('down');
  });
});

describe('Ride intercom Leader mute endpoint', () => {
  it('lets the Leader mute a Rider for everyone', async () => {
    const provider = new RecordingProvider();
    const response = await handleRequest(
      intercomRequest('mute', { body: { riderId: 'rider-2' } }),
      {},
      overrides(rides('active', 'joined', 'leader'), provider),
    );
    expect(response.status).toBe(200);
    expect(provider.mutes).toEqual([{ rideId: 'ride-1', riderId: 'rider-2' }]);
  });

  it.each(['member', 'sweeper', 'navigator'] as const)(
    'refuses a %s',
    async (role) => {
      const provider = new RecordingProvider();
      const response = await handleRequest(
        intercomRequest('mute', { body: { riderId: 'rider-2' } }),
        {},
        overrides(rides('active', 'joined', role), provider),
      );
      expect(response.status).toBe(403);
      expect(await errorCode(response)).toBe('ride_leader_required');
      expect(provider.mutes).toHaveLength(0);
    },
  );

  it('refuses once the Ride is no longer Active', async () => {
    const response = await handleRequest(
      intercomRequest('mute', { body: { riderId: 'rider-2' } }),
      {},
      overrides(rides('completed', 'joined', 'leader')),
    );
    expect(response.status).toBe(409);
  });

  it('validates the body', async () => {
    const response = await handleRequest(
      intercomRequest('mute', { body: { riderId: '' } }),
      {},
      overrides(rides('active', 'joined', 'leader')),
    );
    expect(response.status).toBe(400);
  });

  it('reports a Rider who is not talking as 404', async () => {
    const response = await handleRequest(
      intercomRequest('mute', { body: { riderId: 'rider-9' } }),
      {},
      overrides(
        rides('active', 'joined', 'leader'),
        new RecordingProvider(false, false),
      ),
    );
    expect(response.status).toBe(404);
    expect(await errorCode(response)).toBe('intercom_participant_not_found');
  });
});

describe('LiveKitRoomProvider', () => {
  const config = {
    url: 'wss://commride.livekit.cloud',
    apiKey: 'APIkey123',
    apiSecret: 'secret-secret-secret-secret-secret',
  };
  const now = () => new Date('2026-10-16T10:00:00Z');

  function recordingFetch(responses: unknown[], status = 200) {
    const calls: Array<{ url: string; init: RequestInit | undefined }> = [];
    const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
      calls.push({ url: String(input), init });
      return new Response(JSON.stringify(responses.shift() ?? {}), {
        status,
      });
    }) as typeof fetch;
    return { calls, fetcher };
  }

  it('signs a microphone-only join token for the Ride room', async () => {
    const provider = new LiveKitRoomProvider(
      config,
      recordingFetch([]).fetcher,
      now,
    );
    const token = await provider.mintJoinToken({
      rideId: 'ride-1',
      riderId: 'rider-1',
      displayName: 'Sweep',
    });

    expect(decodeProtectedHeader(token).alg).toBe('HS256');
    const { payload } = await jwtVerify(
      token,
      new TextEncoder().encode(config.apiSecret),
      { currentDate: now() },
    );
    expect(payload.iss).toBe('APIkey123');
    expect(payload.sub).toBe('rider-1');
    expect(payload.name).toBe('Sweep');
    expect(payload.exp! - payload.nbf!).toBe(6 * 60 * 60);
    expect(payload.video).toEqual({
      room: 'commride-ride-ride-1',
      roomJoin: true,
      canSubscribe: true,
      canPublish: true,
      canPublishData: false,
      canPublishSources: ['microphone'],
    });
  });

  it('mutes the microphone track through the room service', async () => {
    const { calls, fetcher } = recordingFetch([
      {
        participants: [
          { identity: 'rider-3', tracks: [{ sid: 'TR_x', source: 'MICROPHONE' }] },
          {
            identity: 'rider-2',
            tracks: [
              { sid: 'TR_cam', source: 'CAMERA', type: 'VIDEO' },
              { sid: 'TR_mic', source: 'MICROPHONE' },
            ],
          },
        ],
      },
      {},
    ]);
    const provider = new LiveKitRoomProvider(config, fetcher, now);

    expect(await provider.muteRider('ride-1', 'rider-2')).toBe(true);
    expect(calls.map((call) => call.url)).toEqual([
      'https://commride.livekit.cloud/twirp/livekit.RoomService/ListParticipants',
      'https://commride.livekit.cloud/twirp/livekit.RoomService/MutePublishedTrack',
    ]);
    expect(JSON.parse(String(calls[1]?.init?.body))).toEqual({
      room: liveKitRoomName('ride-1'),
      identity: 'rider-2',
      track_sid: 'TR_mic',
      muted: true,
    });
    const auth = (calls[0]?.init?.headers as Record<string, string>)
      .authorization;
    const admin = decodeJwt(auth.replace('Bearer ', ''));
    expect(admin.video).toEqual({
      room: 'commride-ride-ride-1',
      roomAdmin: true,
    });
  });

  it('reports a Rider without a microphone track', async () => {
    const { calls, fetcher } = recordingFetch([
      { participants: [{ identity: 'rider-2', tracks: [] }] },
    ]);
    const provider = new LiveKitRoomProvider(config, fetcher, now);
    expect(await provider.muteRider('ride-1', 'rider-2')).toBe(false);
    expect(calls).toHaveLength(1);
  });

  it('throws a provider error on HTTP failure', async () => {
    const provider = new LiveKitRoomProvider(
      config,
      recordingFetch([], 401).fetcher,
      now,
    );
    await expect(provider.muteRider('ride-1', 'rider-2')).rejects.toBeInstanceOf(
      IntercomProviderError,
    );
  });
});
