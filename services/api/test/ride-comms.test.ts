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
import {
  type CreateRideMessageInput,
  type RideMessage,
  type RideMessageCursor,
  type RideMessagePage,
} from '../src/ride-comms/models';
import type { RideMessageRepository } from '../src/ride-comms/repository';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
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

class MemoryRideMessageRepository implements RideMessageRepository {
  readonly messages: RideMessage[] = [];

  async findByClientMessageId(
    rideId: string,
    senderRiderId: string,
    clientMessageId: string,
  ): Promise<RideMessage | null> {
    return (
      this.messages.find(
        (message) =>
          message.rideId === rideId &&
          message.senderRiderId === senderRiderId &&
          message.clientMessageId === clientMessageId,
      ) ?? null
    );
  }

  async create(input: CreateRideMessageInput): Promise<RideMessage> {
    const existing = await this.findByClientMessageId(
      input.rideId,
      input.senderRiderId,
      input.clientMessageId,
    );
    if (existing != null) {
      return existing;
    }

    this.messages.push(input);
    return input;
  }

  async list(
    rideId: string,
    limit: number,
    cursor: RideMessageCursor | null,
  ): Promise<RideMessagePage> {
    const ordered = this.messages
      .filter((message) => message.rideId === rideId)
      .sort((a, b) => {
        const time = b.createdAt.localeCompare(a.createdAt);
        return time !== 0 ? time : b.id.localeCompare(a.id);
      })
      .filter((message) => {
        if (cursor == null) {
          return true;
        }
        return (
          message.createdAt < cursor.createdAt ||
          (message.createdAt === cursor.createdAt && message.id < cursor.id)
        );
      });

    const page = ordered.slice(0, limit);
    return {
      messages: [...page].reverse(),
      nextCursor:
        ordered.length > limit && page.length > 0
          ? {
              createdAt: page[page.length - 1].createdAt,
              id: page[page.length - 1].id,
            }
          : null,
    };
  }
}

class RecordingGateway implements ActiveRideGateway {
  readonly messages: RideMessage[] = [];
  failMessageBroadcast = false;

  async connect(
    _request: Request,
    _rideId: string,
    _participant: ActiveRideParticipant,
  ): Promise<Response> {
    throw new Error('Not used.');
  }

  async endRide(_rideId: string, _endedAt: string): Promise<void> {
    throw new Error('Not used.');
  }

  async messageCreated(
    _rideId: string,
    message: RideMessage,
  ): Promise<void> {
    if (this.failMessageBroadcast) {
      throw new Error('Room unavailable.');
    }
    this.messages.push(message);
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

function clubRideRepository(
  currentRide: Ride,
  memberStatus: RideMembershipStatus = 'active',
): ClubRideRepository {
  const memberships = new Map<string, RideMembership>([
    [leader.id, membership(leader.id, 'leader')],
    [member.id, membership(member.id, 'member', memberStatus)],
  ]);

  return {
    async findRide(rideId: string) {
      return rideId === currentRide.id ? currentRide : null;
    },
    async findRideMembership(rideId: string, riderId: string) {
      return rideId === currentRide.id
        ? memberships.get(riderId) ?? null
        : null;
    },
  } as unknown as ClubRideRepository;
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
  currentRide: Ride,
  messages: RideMessageRepository,
  gateway: ActiveRideGateway,
  memberStatus: RideMembershipStatus = 'active',
) {
  let idCounter = 0;
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    clubRideRepository: clubRideRepository(currentRide, memberStatus),
    rideMessageRepository: messages,
    activeRideGateway: gateway,
    idFactory: () => `message-${++idCounter}`,
    now: () => new Date('2026-09-18T10:00:00Z'),
  };
}

async function bodyOf(response: Response) {
  return response.json() as Promise<Record<string, unknown>>;
}

describe('Ride communication API', () => {
  it('persists participant chat with server-derived sender identity', async () => {
    const messages = new MemoryRideMessageRepository();
    const gateway = new RecordingGateway();

    const response = await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'client-1',
        body: ' Tunggu di SPBU depan. ',
        senderRiderId: 'spoofed-rider',
        senderRideRole: 'leader',
      }),
      {},
      dependencies(ride(), messages, gateway),
    );

    expect(response.status).toBe(201);
    expect(messages.messages).toHaveLength(1);
    expect(messages.messages[0]).toMatchObject({
      senderRiderId: member.id,
      senderDisplayName: member.displayName,
      senderRideRole: 'member',
      kind: 'chat',
      body: 'Tunggu di SPBU depan.',
      clientMessageId: 'client-1',
    });
    expect(gateway.messages).toHaveLength(1);
  });

  it('returns the existing message for an identical idempotent retry', async () => {
    const messages = new MemoryRideMessageRepository();
    const gateway = new RecordingGateway();
    const deps = dependencies(ride(), messages, gateway);

    const first = await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'client-1',
        body: 'Tunggu.',
      }),
      {},
      deps,
    );
    expect(first.status).toBe(201);

    const repeated = await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'client-1',
        body: 'Tunggu.',
      }),
      {},
      deps,
    );

    expect(repeated.status).toBe(200);
    expect(messages.messages).toHaveLength(1);
    expect(gateway.messages).toHaveLength(1);
  });

  it('rejects reuse of clientMessageId for different content', async () => {
    const messages = new MemoryRideMessageRepository();
    const deps = dependencies(ride(), messages, new RecordingGateway());

    await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'client-1',
        body: 'First',
      }),
      {},
      deps,
    );

    const conflict = await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'client-1',
        body: 'Changed',
      }),
      {},
      deps,
    );

    expect(conflict.status).toBe(409);
    expect(messages.messages).toHaveLength(1);
  });

  it('allows only the Ride Leader to publish announcements', async () => {
    const messages = new MemoryRideMessageRepository();
    const gateway = new RecordingGateway();
    const deps = dependencies(ride(), messages, gateway);

    const rejected = await handleRequest(
      request('/v1/rides/ride-1/announcements', 'POST', 'member-token', {
        clientMessageId: 'announcement-member',
        body: 'Regroup.',
      }),
      {},
      deps,
    );
    expect(rejected.status).toBe(403);

    const accepted = await handleRequest(
      request('/v1/rides/ride-1/announcements', 'POST', 'leader-token', {
        clientMessageId: 'announcement-leader',
        body: 'Regroup di checkpoint berikutnya.',
      }),
      {},
      deps,
    );

    expect(accepted.status).toBe(201);
    expect(messages.messages).toHaveLength(1);
    expect(messages.messages[0]).toMatchObject({
      senderRiderId: leader.id,
      senderRideRole: 'leader',
      kind: 'announcement',
    });
  });

  it('rejects invited-only Riders from private communication', async () => {
    const messages = new MemoryRideMessageRepository();
    const deps = dependencies(
      ride(),
      messages,
      new RecordingGateway(),
      'invited',
    );

    const read = await handleRequest(
      request('/v1/rides/ride-1/messages', 'GET', 'member-token'),
      {},
      deps,
    );
    expect(read.status).toBe(403);

    const send = await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'client-1',
        body: 'Should not send',
      }),
      {},
      deps,
    );
    expect(send.status).toBe(403);
  });

  it('keeps Completed Ride history readable but read-only', async () => {
    const messages = new MemoryRideMessageRepository();
    messages.messages.push({
      id: 'message-old',
      rideId: 'ride-1',
      senderRiderId: member.id,
      senderDisplayName: member.displayName,
      senderRideRole: 'member',
      kind: 'chat',
      body: 'Archived Ride message',
      clientMessageId: 'old-client',
      createdAt: '2026-09-18T10:00:00Z',
    });

    const deps = dependencies(
      ride('completed'),
      messages,
      new RecordingGateway(),
      'finished',
    );

    const read = await handleRequest(
      request('/v1/rides/ride-1/messages', 'GET', 'member-token'),
      {},
      deps,
    );
    expect(read.status).toBe(200);

    const send = await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'late',
        body: 'Too late',
      }),
      {},
      deps,
    );
    expect(send.status).toBe(409);
  });

  it('keeps persisted success when realtime broadcast fails', async () => {
    const messages = new MemoryRideMessageRepository();
    const gateway = new RecordingGateway();
    gateway.failMessageBroadcast = true;

    const response = await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'client-offline-room',
        body: 'Persist me',
      }),
      {},
      dependencies(ride(), messages, gateway),
    );

    expect(response.status).toBe(201);
    expect(messages.messages).toHaveLength(1);
  });

  it('returns stable chronological pages with a next cursor', async () => {
    const messages = new MemoryRideMessageRepository();
    for (let index = 1; index <= 3; index += 1) {
      messages.messages.push({
        id: `message-${index}`,
        rideId: 'ride-1',
        senderRiderId: member.id,
        senderDisplayName: member.displayName,
        senderRideRole: 'member',
        kind: 'chat',
        body: `Message ${index}`,
        clientMessageId: `client-${index}`,
        createdAt: `2026-09-18T10:00:0${index}Z`,
      });
    }

    const deps = dependencies(ride(), messages, new RecordingGateway());
    const first = await handleRequest(
      request('/v1/rides/ride-1/messages?limit=2', 'GET', 'member-token'),
      {},
      deps,
    );
    expect(first.status).toBe(200);

    const firstBody = await bodyOf(first) as {
      messages: RideMessage[];
      nextCursor: string | null;
    };
    expect(firstBody.messages.map((message) => message.id)).toEqual([
      'message-2',
      'message-3',
    ]);
    expect(firstBody.nextCursor).not.toBeNull();

    const second = await handleRequest(
      request(
        `/v1/rides/ride-1/messages?limit=2&cursor=${encodeURIComponent(
          firstBody.nextCursor!,
        )}`,
        'GET',
        'member-token',
      ),
      {},
      deps,
    );
    expect(second.status).toBe(200);

    const secondBody = await bodyOf(second) as {
      messages: RideMessage[];
      nextCursor: string | null;
    };
    expect(secondBody.messages.map((message) => message.id)).toEqual([
      'message-1',
    ]);
    expect(secondBody.nextCursor).toBeNull();
  });

  it('rejects oversized message bodies', async () => {
    const response = await handleRequest(
      request('/v1/rides/ride-1/messages', 'POST', 'member-token', {
        clientMessageId: 'too-long',
        body: 'a'.repeat(1001),
      }),
      {},
      dependencies(
        ride(),
        new MemoryRideMessageRepository(),
        new RecordingGateway(),
      ),
    );

    expect(response.status).toBe(400);
  });
});
