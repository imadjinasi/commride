import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type { RiderProfile, UpsertRiderProfileInput } from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import { handlePushTokenRequest } from '../src/push/handler';
import {
  BestEffortRidePushNotifier,
} from '../src/push/notifier';
import type {
  PushDeliveryResult,
  RiderPushToken,
} from '../src/push/models';
import type { PushRepository } from '../src/push/repository';
import type { PushTransport } from '../src/push/fcm';

const rider: RiderProfile = {
  id: 'rider-1',
  authSubject: 'auth-rider-1',
  displayName: 'Rider One',
  callsign: null,
  homeArea: null,
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

class TestIdentityVerifier implements IdentityVerifier {
  async verify(token: string): Promise<AuthenticatedIdentity> {
    if (token !== 'valid-token') {
      throw new Error('Unknown token.');
    }
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

class MemoryPushRepository implements PushRepository {
  readonly tokens: RiderPushToken[] = [];
  readonly claimed = new Set<string>();
  readonly directClaimed = new Set<string>();

  async registerToken(input: {
    readonly id: string;
    readonly riderId: string;
    readonly token: string;
    readonly platform: 'android' | 'ios';
    readonly now: string;
  }): Promise<RiderPushToken> {
    const existing = this.tokens.find((item) => item.token === input.token);
    if (existing != null) {
      this.tokens.splice(this.tokens.indexOf(existing), 1);
    }
    const token: RiderPushToken = {
      id: input.id,
      riderId: input.riderId,
      token: input.token,
      platform: input.platform,
      createdAt: input.now,
      updatedAt: input.now,
    };
    this.tokens.push(token);
    return token;
  }

  async unregisterToken(riderId: string, token: string): Promise<void> {
    const index = this.tokens.findIndex(
      (item) => item.riderId === riderId && item.token === token,
    );
    if (index >= 0) {
      this.tokens.splice(index, 1);
    }
  }

  async listRideTokens(): Promise<readonly RiderPushToken[]> {
    return this.tokens;
  }

  async listRiderTokens(
    riderId: string,
  ): Promise<readonly RiderPushToken[]> {
    return this.tokens.filter((item) => item.riderId === riderId);
  }

  async claimRiderEvent(input: {
    readonly eventKey: string;
    readonly riderId: string;
    readonly kind: string;
    readonly createdAt: string;
  }): Promise<boolean> {
    if (this.directClaimed.has(input.eventKey)) {
      return false;
    }
    this.directClaimed.add(input.eventKey);
    return true;
  }

  async claimEvent(input: {
    readonly eventKey: string;
    readonly rideId: string;
    readonly kind: string;
    readonly createdAt: string;
  }): Promise<boolean> {
    if (this.claimed.has(input.eventKey)) {
      return false;
    }
    this.claimed.add(input.eventKey);
    return true;
  }

  async deleteToken(token: string): Promise<void> {
    const index = this.tokens.findIndex((item) => item.token === token);
    if (index >= 0) {
      this.tokens.splice(index, 1);
    }
  }
}

class RecordingTransport implements PushTransport {
  calls = 0;
  fail = false;

  async sendToTokens(
    tokens: readonly RiderPushToken[],
    _message: {
      readonly title: string;
      readonly body: string;
      readonly data: Readonly<Record<string, string>>;
    },
  ): Promise<PushDeliveryResult> {
    this.calls += 1;
    if (this.fail) {
      throw new Error('FCM unavailable.');
    }
    return { delivered: tokens.length, failed: 0 };
  }
}

function request(
  method: 'POST' | 'DELETE',
  body: Record<string, unknown>,
): Request {
  return new Request('https://commride.invalid/v1/me/push-tokens', {
    method,
    headers: {
      authorization: 'Bearer valid-token',
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
}

describe('push notifications', () => {
  it('registers and unregisters a token for the authenticated Rider', async () => {
    const repository = new MemoryPushRepository();
    const dependencies = {
      identityVerifier: new TestIdentityVerifier(),
      riderRepository: new TestRiderRepository(),
      pushRepository: repository,
      idFactory: () => 'push-1',
      now: () => new Date('2026-09-18T10:00:00Z'),
    };

    const registered = await handlePushTokenRequest(
      request('POST', {
        token: 'device-token',
        platform: 'android',
        riderId: 'spoofed-rider',
      }),
      'request-1',
      dependencies,
    );

    expect(registered.status).toBe(200);
    expect(repository.tokens).toHaveLength(1);
    expect(repository.tokens[0].riderId).toBe(rider.id);

    const removed = await handlePushTokenRequest(
      request('DELETE', {
        token: 'device-token',
        platform: 'android',
      }),
      'request-2',
      dependencies,
    );

    expect(removed.status).toBe(200);
    expect(repository.tokens).toHaveLength(0);
  });

  it('deduplicates the same notification event', async () => {
    const repository = new MemoryPushRepository();
    await repository.registerToken({
      id: 'push-1',
      riderId: rider.id,
      token: 'device-token',
      platform: 'android',
      now: '2026-09-18T10:00:00Z',
    });
    const transport = new RecordingTransport();
    const notifier = new BestEffortRidePushNotifier(
      repository,
      transport,
      () => new Date('2026-09-18T10:00:00Z'),
    );

    const message = {
      eventKey: 'sos:sos-1:raised',
      rideId: 'ride-1',
      kind: 'sos_raised',
      title: 'SOS',
      body: 'Need help',
      data: { type: 'ride.sos_raised' },
    };

    await notifier.notify(message);
    await notifier.notify(message);

    expect(transport.calls).toBe(1);
  });

  it('keeps push transport failure non-authoritative', async () => {
    const repository = new MemoryPushRepository();
    const transport = new RecordingTransport();
    transport.fail = true;
    const notifier = new BestEffortRidePushNotifier(
      repository,
      transport,
    );

    const result = await notifier.notify({
      eventKey: 'announcement:1',
      rideId: 'ride-1',
      kind: 'leader_announcement',
      title: 'Leader',
      body: 'Regroup',
      data: { type: 'ride.message_created' },
    });

    expect(result).toEqual({ delivered: 0, failed: 0 });
  });

  it('targets and deduplicates direct Rider notifications', async () => {
    const repository = new MemoryPushRepository();
    await repository.registerToken({
      id: 'push-rider-1',
      riderId: rider.id,
      token: 'device-token',
      platform: 'android',
      now: '2026-09-18T10:00:00Z',
    });
    await repository.registerToken({
      id: 'push-rider-2',
      riderId: 'rider-2',
      token: 'other-device-token',
      platform: 'android',
      now: '2026-09-18T10:00:00Z',
    });
    const transport = new RecordingTransport();
    const notifier = new BestEffortRidePushNotifier(repository, transport);

    const message = {
      eventKey: 'club-invite:club-1:rider-1:member',
      riderId: rider.id,
      kind: 'club_invitation',
      title: 'Undangan Club',
      body: 'Buka Club untuk melihat undangan.',
      data: { type: 'club.invited', clubId: 'club-1' },
    };

    const first = await notifier.notifyRider(message);
    const repeated = await notifier.notifyRider(message);

    expect(first).toEqual({ delivered: 1, failed: 0 });
    expect(repeated).toEqual({ delivered: 0, failed: 0 });
    expect(transport.calls).toBe(1);
  });

});
