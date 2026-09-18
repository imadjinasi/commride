import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import { handleRequest } from '../src/router';

class FakeIdentityVerifier implements IdentityVerifier {
  async verify(token: string): Promise<AuthenticatedIdentity> {
    if (token !== 'valid-token') {
      throw new Error('Unexpected token in test.');
    }

    return { subject: 'firebase-user-1' };
  }
}

class MemoryRiderRepository implements RiderRepository {
  private profile: RiderProfile | null = null;

  async findByAuthSubject(authSubject: string): Promise<RiderProfile | null> {
    if (this.profile?.authSubject !== authSubject) {
      return null;
    }

    return this.profile;
  }

  async upsertProfile(
    input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    const existing = this.profile;

    this.profile = {
      id: existing?.id ?? input.newRiderId,
      authSubject: input.authSubject,
      displayName: input.displayName,
      callsign: input.callsign,
      homeArea: input.homeArea,
      createdAt: existing?.createdAt ?? '2026-09-18T00:00:00Z',
      updatedAt: '2026-09-18T00:00:00Z',
    };

    return this.profile;
  }
}

describe('Rider profile API', () => {
  it('requires authentication', async () => {
    const response = await handleRequest(
      new Request('https://commride.invalid/v1/me'),
      {},
      {
        identityVerifier: new FakeIdentityVerifier(),
        riderRepository: new MemoryRiderRepository(),
      },
    );

    expect(response.status).toBe(401);
  });

  it('creates a profile for the authenticated subject', async () => {
    const repository = new MemoryRiderRepository();

    const response = await handleRequest(
      new Request('https://commride.invalid/v1/me', {
        method: 'PUT',
        headers: {
          authorization: 'Bearer valid-token',
          'content-type': 'application/json',
          'x-request-id': 'profile-test-1',
        },
        body: JSON.stringify({
          displayName: '  Rider One  ',
          callsign: '  Sweep  ',
          homeArea: '  Cirebon  ',
        }),
      }),
      {},
      {
        identityVerifier: new FakeIdentityVerifier(),
        riderRepository: repository,
        idFactory: () => 'rider-generated-1',
      },
    );

    expect(response.status).toBe(200);

    await expect(response.json()).resolves.toEqual({
      rider: {
        id: 'rider-generated-1',
        authSubject: 'firebase-user-1',
        displayName: 'Rider One',
        callsign: 'Sweep',
        homeArea: 'Cirebon',
        createdAt: '2026-09-18T00:00:00Z',
        updatedAt: '2026-09-18T00:00:00Z',
      },
    });
  });

  it('returns 404 when onboarding profile does not exist yet', async () => {
    const response = await handleRequest(
      new Request('https://commride.invalid/v1/me', {
        headers: {
          authorization: 'Bearer valid-token',
        },
      }),
      {},
      {
        identityVerifier: new FakeIdentityVerifier(),
        riderRepository: new MemoryRiderRepository(),
      },
    );

    expect(response.status).toBe(404);
  });

  it('rejects invalid profile input', async () => {
    const response = await handleRequest(
      new Request('https://commride.invalid/v1/me', {
        method: 'PUT',
        headers: {
          authorization: 'Bearer valid-token',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          displayName: '',
        }),
      }),
      {},
      {
        identityVerifier: new FakeIdentityVerifier(),
        riderRepository: new MemoryRiderRepository(),
      },
    );

    expect(response.status).toBe(400);
  });
});
