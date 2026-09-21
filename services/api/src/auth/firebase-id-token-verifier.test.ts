import {
  generateKeyPair,
  importPKCS8,
  SignJWT,
} from 'jose';
import { describe, expect, it } from 'vitest';

import { FirebaseIdTokenVerifier } from './firebase-id-token-verifier';
import { InvalidIdentityTokenError } from './identity';

const PROJECT_ID = 'commride-pilot';
const KEY_ID = 'pilot-key';
const NOW_MS = Date.UTC(2026, 8, 21, 15, 0, 0);
const NOW_SECONDS = Math.floor(NOW_MS / 1000);

const TEST_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQC++hHSYPPeKQ+1
UaGA9UGvDmHBMo85I35AEZdcEfoazTBuVpLAZoUXyVsB7LXtsoSH5eCPhODllgmL
cE8EWw+74UxIdvxVAYwrNV3WQ6e7VfGaA2xMy5bJBuPztVQE8MZJp6BULXd0Whk5
GZWqBCpnUFZVarm9yKqIN6GN+EapFHBOjrW7tYfoAPEPzjw5oec8+SX8gz8fSAtT
tbgRchNv7v5ht3feYPitdButCkrhWvNyk23CMZtRMfCGGK2Om/kqNPAfgGVw9P94
TeFb1VBk61N73jq447KIM+JhTJx3Fim77+uOB6j/iDj/Y60b95AhTzvB7NdmpFwK
gCbb6L5TAgMBAAECggEAN59+MVgrrzkmahksgPLt/p6hujOPo4TC8MYu35Ic1lGN
GZX9iCxT92meKCFZm7GzCCHcFfENz9CzVvmPCiW7n20vWqvNMrUQrkUM36s030tY
4xK8KGHjuQlYu1LE9etq1WkNOXdEo47aadcZ0DsGXrD3dElxb+VSRfpuA3ucmQHp
LgsDItFh8ghZSu/5ZPpIBbJKB21K6LxNfKJQ0X5/0ShMGa5SibGZM9VF+rzgQ4aX
hf+MOAdnR2nrURfywwV7qlSkXvmY1y1j9vWab28/R6exKV14UuAtzMX0O6gcxlKF
dG1LJ0Ep9y2p7SshVM/JPLggQYf7kSYuYwcIBpgygQKBgQD5/XP/+f8rzQylUjzd
f65GxHdJjTOhB7cvRLU53O4+kqbv1umjuVKzHdkW1QIKCuhm1edvWB49eA1sbXwJ
DlfkJKEzglwMDICtLxLNm7ldU5ik2oQnjdZG23Aa3boVa8FRGL7mRZwydlTiWxef
2cAUXIUAm+olhGBbk0g/VkR8HwKBgQDDkWxzep/DtD6a4NmgiZ7n7YhNZA3sVbLl
Knix3nm6eZrsZYp/633RLtkd8z8KHPQ5nQGVYXGUJ3M7ay7wGjo6k6DYCD9INxfm
gYnPqM3bldfSPLrUgTObkXZM9tqD2LLkIcKD07whcsgH9Veo1Wg4b5TXBbZXa8qN
igd5eMN3TQKBgGJn+O+8s0vErcOuObNffXTyBZr4cGhlJyD+RPCAHXCYPgqPaO1A
GGPVzg0E0IavgIhqj23vHAhKZ85U0sylzsdJ/ALQv/cmPMjvjNFPCYrJS38pXXhM
hxrhaqHIwmWIQ1LvEMaIhFIA7q0j+oq8JrZdLSXuOh+Gmn+x3HDCPrc1AoGASVV7
xGXECP/KxgrwsGlKpA+HH/YX3npYReTCM3iITuuQs3p0D/m/STR3B+sRxXoL/pqo
YFqU24hbhnlvtWswUIzRMJEPIcY++Rm0EqFq6B9tOZG6QTtdncVTBhM+51fX5QHf
zc0U67n91jYis9Wqahc1SdgDgw6Rere6i8tECLUCgYBXPCgNPXBR4rgAmhLtzroB
FOUvuE4GbZ5ixs5ktwkBQk+dNh4+hc64lUL/+T6KRQ6DI8SMVNkmJh33CU559/A/
jpsvcJKMsWiexfbOsCgFN1PIMXt6BZd4KpNvegLwrN3FOB+U6A34m6Bqy5nu9lck
TvMWn7z8wLFdbP6oo3cTqg==
-----END PRIVATE KEY-----`;

const TEST_CERTIFICATE = `-----BEGIN CERTIFICATE-----
MIIDETCCAfmgAwIBAgIUHNfXFOPoJ+6Cxm1wzlT/Sv4OscswDQYJKoZIhvcNAQEL
BQAwGDEWMBQGA1UEAwwNY29tbXJpZGUtdGVzdDAeFw0yNjA5MjExNDE0NDFaFw0z
NjA5MTgxNDE0NDFaMBgxFjAUBgNVBAMMDWNvbW1yaWRlLXRlc3QwggEiMA0GCSqG
SIb3DQEBAQUAA4IBDwAwggEKAoIBAQC++hHSYPPeKQ+1UaGA9UGvDmHBMo85I35A
EZdcEfoazTBuVpLAZoUXyVsB7LXtsoSH5eCPhODllgmLcE8EWw+74UxIdvxVAYwr
NV3WQ6e7VfGaA2xMy5bJBuPztVQE8MZJp6BULXd0Whk5GZWqBCpnUFZVarm9yKqI
N6GN+EapFHBOjrW7tYfoAPEPzjw5oec8+SX8gz8fSAtTtbgRchNv7v5ht3feYPit
dButCkrhWvNyk23CMZtRMfCGGK2Om/kqNPAfgGVw9P94TeFb1VBk61N73jq447KI
M+JhTJx3Fim77+uOB6j/iDj/Y60b95AhTzvB7NdmpFwKgCbb6L5TAgMBAAGjUzBR
MB0GA1UdDgQWBBTX0lEXBnlnnLX+kpOlBT0P1puTJDAfBgNVHSMEGDAWgBTX0lEX
BnlnnLX+kpOlBT0P1puTJDAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUA
A4IBAQBJZyLsR1sr0g8RCaSvtTZb2XeT5vIzZA40VFMGQ+EiQgMVjAlPqFr/bkHj
4zXVx6ii457NwfE7yz/j5K/AM616d/up+8TQxuDWVqi4dVmSaBSZYCNaYe3XyfyN
GLRMcGL7B+nDWMZMnNqx1DkycQzCxafvD0zx3TZowjKA6uxt2mCcVc9q9PneN4tO
uk1ckbONF11hXcMAOiXxP6+Zy99aOCvbtVSJiG/OQsRj3rk+8b5ciiQMwvU1N7Jb
uch9ZZlQ+uf9kbMZT97fQBaymuB/PwoySfQt62RulAq4muOgqa9qLUiLdZZc3QMh
yFlqA7GMghre4MRhhRisHEBkin5s
-----END CERTIFICATE-----`;

async function fixture() {
  const privateKey = await importPKCS8(TEST_PRIVATE_KEY, 'RS256');
  let fetchCount = 0;

  const fetcher: typeof fetch = async () => {
    fetchCount += 1;
    return new Response(
      JSON.stringify({
        [KEY_ID]: TEST_CERTIFICATE,
      }),
      {
        status: 200,
        headers: {
          'content-type': 'application/json',
          'cache-control': 'public, max-age=3600',
        },
      },
    );
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
  it('accepts a correctly signed Firebase-shaped token using an X.509 certificate', async () => {
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

  it('rejects a token signed by a key that does not match the Firebase certificate', async () => {
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
