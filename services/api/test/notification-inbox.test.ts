import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import {
  handleNotificationRequest,
} from '../src/notifications/handler';
import type {
  CreateNotificationInput,
  NotificationScope,
  RiderNotification,
} from '../src/notifications/models';
import type {
  NotificationRepository,
} from '../src/notifications/repository';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';

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

class MemoryNotificationRepository implements NotificationRepository {
  readonly items: RiderNotification[] = [
    {
      id: 'notification-1',
      riderId: rider.id,
      scope: 'account',
      clubId: 'club-1',
      rideId: null,
      eventKey: 'club-invite:club-1:rider-1',
      kind: 'club_invite',
      title: 'Undangan Club',
      body: 'Anda diundang.',
      data: { type: 'club.invite' },
      createdAt: '2026-09-23T10:00:00Z',
      readAt: null,
    },
  ];

  async createForRider(
    _riderId: string,
    _input: CreateNotificationInput,
  ): Promise<void> {}

  async createForClubMembers(
    _clubId: string,
    _input: CreateNotificationInput,
  ): Promise<void> {}

  async createForRideParticipants(
    _rideId: string,
    _input: CreateNotificationInput,
  ): Promise<void> {}

  async listForRider(
    riderId: string,
    options: {
      readonly scope?: NotificationScope;
      readonly clubId?: string;
      readonly limit?: number;
    } = {},
  ): Promise<readonly RiderNotification[]> {
    return this.items.filter(
      (item) =>
        item.riderId === riderId &&
        (options.scope == null || item.scope === options.scope) &&
        (options.clubId == null || item.clubId === options.clubId),
    );
  }

  async markRead(
    riderId: string,
    notificationId: string,
    readAt: string,
  ): Promise<boolean> {
    const index = this.items.findIndex(
      (item) => item.id === notificationId && item.riderId === riderId,
    );
    if (index < 0) {
      return false;
    }
    const item = this.items[index];
    this.items[index] = { ...item, readAt: item.readAt ?? readAt };
    return true;
  }
}

function authRequest(url: string, method = 'GET'): Request {
  return new Request(url, {
    method,
    headers: { authorization: 'Bearer valid-token' },
  });
}

describe('notification inbox', () => {
  it('lists Account notifications for the authenticated Rider', async () => {
    const repository = new MemoryNotificationRepository();
    const response = await handleNotificationRequest(
      authRequest(
        'https://commride.invalid/v1/me/notifications?scope=account',
      ),
      new URL(
        'https://commride.invalid/v1/me/notifications?scope=account',
      ),
      'request-1',
      {
        identityVerifier: new TestIdentityVerifier(),
        riderRepository: new TestRiderRepository(),
        notificationRepository: repository,
      },
    );

    expect(response?.status).toBe(200);
    const body = await response!.json() as {
      notifications: RiderNotification[];
    };
    expect(body.notifications).toHaveLength(1);
    expect(body.notifications[0].scope).toBe('account');
  });

  it('marks only the authenticated Riders notification as read', async () => {
    const repository = new MemoryNotificationRepository();
    const response = await handleNotificationRequest(
      authRequest(
        'https://commride.invalid/v1/me/notifications/notification-1/read',
        'POST',
      ),
      new URL(
        'https://commride.invalid/v1/me/notifications/notification-1/read',
      ),
      'request-2',
      {
        identityVerifier: new TestIdentityVerifier(),
        riderRepository: new TestRiderRepository(),
        notificationRepository: repository,
        now: () => new Date('2026-09-23T11:00:00Z'),
      },
    );

    expect(response?.status).toBe(200);
    expect(repository.items[0].readAt).toBe('2026-09-23T11:00:00.000Z');
  });
});
