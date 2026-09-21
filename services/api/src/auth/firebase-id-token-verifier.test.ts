import {
  exportJWK,
  generateKeyPair,
  SignJWT,
} from 'jose';
import { describe, expect, it } from 'vitest';

import { FirebaseIdTokenVerifier } from './firebase-id-token-verifier';
import { InvalidIdentityTokenError } from './identity';

const PROJECT_ID = 'commride-pilot';
const KEY_ID = 'pilot-key';
const NOW_MS = Date.UTC(2026, 8, 21, 13, 0, 0);
const NOW_SECONDS = Math.floor(NOW_MS / 1000);

async function fixture() {
  const { publicKey, privateKey } = await generateKeyPair('RS256', {
    extractable: true,
  });
  const publicJwk = await exportJWK(publicKey);
  const jwks = {
    keys: [
      {
        ...publicJwk,
        kid: KEY_ID,
        alg: 'RS256',
        use: 'sig',
      },
    ],
  };

  let fetchCount = 0;
  const fetcher: typeof fetch = async () => {
    fetchCount += 1;
    return new Response(JSON.stringify(jwks), {
      status: 200,
      headers: {
        'content-type': 'application/json',
        'cache-control': 'public, max-age=3600',
      },
    });
  };

  async function token(options?: {
    audience?: string;
    issuer?: string;
    expiresAt?: number;
  }) {
    return new SignJWT({
      auth_time: NOW_SECONDS - 30,
      email: 'pilot@example.test',
      email_verified: true,
    })
      .setProtectedHeader({ alg: 'RS256', kid: KEY_ID })
      .setSubject('firebase-user-123')
      .setAudience(options?.audience ?? PROJECT_ID)
      .setIssuer(
        options?.issuer ?? `https://securetoken.google.com/${PROJECT_ID}`,
      )
      .setIssuedAt(NOW_SECONDS - 10)
      .setExpirationTime(options?.expiresAt ?? NOW_SECONDS + 3600)
      .sign(privateKey);
  }

  return {
    fetcher,
    fetchCount: () => fetchCount,
    token,
  };
}

describe('FirebaseIdTokenVerifier', () => {
  it('accepts a correctly signed Firebase-shaped ID token and caches JWKS', async () => {
    const setup = await fixture();
    const verifier = new FirebaseIdTokenVerifier(
      PROJECT_ID,
      setup.fetcher,
      () => NOW_MS,
    );
    const idToken = await setup.token();

    await expect(verifier.verify(idToken)).resolves.toEqual({
      subject: 'firebase-user-123',
      email: 'pilot@example.test',
      emailVerified: true,
    });
    await expect(verifier.verify(idToken)).resolves.toMatchObject({
      subject: 'firebase-user-123',
    });
    expect(setup.fetchCount()).toBe(1);
  });

  it('rejects a valid signature when the Firebase audience is wrong', async () => {
    const setup = await fixture();
    const verifier = new FirebaseIdTokenVerifier(
      PROJECT_ID,
      setup.fetcher,
      () => NOW_MS,
    );

    await expect(
      verifier.verify(await setup.token({ audience: 'another-project' })),
    ).rejects.toBeInstanceOf(InvalidIdentityTokenError);
  });

  it('rejects an expired Firebase ID token', async () => {
    const setup = await fixture();
    const verifier = new FirebaseIdTokenVerifier(
      PROJECT_ID,
      setup.fetcher,
      () => NOW_MS,
    );

    await expect(
      verifier.verify(await setup.token({ expiresAt: NOW_SECONDS - 1 })),
    ).rejects.toBeInstanceOf(InvalidIdentityTokenError);
  });

  it('rejects a token signed by a key that is not in Firebase JWKS', async () => {
    const setup = await fixture();
    const { privateKey } = await generateKeyPair('RS256');
    const token = await new SignJWT({
      auth_time: NOW_SECONDS - 30,
    })
      .setProtectedHeader({ alg: 'RS256', kid: KEY_ID })
      .setSubject('firebase-user-123')
      .setAudience(PROJECT_ID)
      .setIssuer(`https://securetoken.google.com/${PROJECT_ID}`)
      .setIssuedAt(NOW_SECONDS - 10)
      .setExpirationTime(NOW_SECONDS + 3600)
      .sign(privateKey);

    const verifier = new FirebaseIdTokenVerifier(
      PROJECT_ID,
      setup.fetcher,
      () => NOW_MS,
    );

    await expect(verifier.verify(token)).rejects.toBeInstanceOf(
      InvalidIdentityTokenError,
    );
  });
});
