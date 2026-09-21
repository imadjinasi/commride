import {
  type AuthenticatedIdentity,
  type IdentityVerifier,
  InvalidIdentityTokenError,
} from './identity';

const FIREBASE_JWKS_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/' +
  'securetoken@system.gserviceaccount.com';
const DEFAULT_KEY_CACHE_SECONDS = 300;

interface FirebaseJwk {
  readonly kid: string;
  readonly kty: 'RSA';
  readonly alg: 'RS256';
  readonly use?: 'sig';
  readonly n: string;
  readonly e: string;
}

interface KeyCache {
  readonly expiresAtMs: number;
  readonly keys: ReadonlyMap<string, FirebaseJwk>;
}

interface JwtHeader {
  readonly alg: string;
  readonly kid: string;
}

interface JwtPayload {
  readonly aud: string;
  readonly iss: string;
  readonly sub: string;
  readonly exp: number;
  readonly iat: number;
  readonly auth_time: number;
  readonly email?: string;
  readonly email_verified?: boolean;
}

export class FirebaseIdTokenVerifier implements IdentityVerifier {
  constructor(
    private readonly projectId: string,
    private readonly fetcher: typeof fetch = fetch,
    private readonly now: () => number = Date.now,
  ) {
    if (projectId.trim().length === 0) {
      throw new ArgumentError('Firebase project ID must not be empty.');
    }
  }

  private keyCache: KeyCache | null = null;
  private readonly importedKeys = new Map<string, CryptoKey>();

  async verify(token: string): Promise<AuthenticatedIdentity> {
    try {
      const segments = token.split('.');
      if (
        segments.length !== 3 ||
        segments.some((segment) => segment.length === 0)
      ) {
        throw new InvalidIdentityTokenError();
      }

      const [encodedHeader, encodedPayload, encodedSignature] = segments;
      const header = readHeader(encodedHeader);
      if (header.alg !== 'RS256' || header.kid.length === 0) {
        throw new InvalidIdentityTokenError();
      }

      const key = await this.keyForId(header.kid);
      const verified = await crypto.subtle.verify(
        {
          name: 'RSASSA-PKCS1-v1_5',
        },
        key,
        decodeBase64Url(encodedSignature),
        new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
      );

      if (!verified) {
        throw new InvalidIdentityTokenError();
      }

      const payload = readPayload(encodedPayload);
      const nowSeconds = Math.floor(this.now() / 1000);
      if (
        payload.aud !== this.projectId ||
        payload.iss !== `https://securetoken.google.com/${this.projectId}` ||
        payload.sub.length === 0 ||
        payload.exp <= nowSeconds ||
        payload.iat > nowSeconds ||
        payload.auth_time > nowSeconds
      ) {
        throw new InvalidIdentityTokenError();
      }

      return {
        subject: payload.sub,
        ...(payload.email == null ? {} : { email: payload.email }),
        ...(payload.email_verified == null
          ? {}
          : { emailVerified: payload.email_verified }),
      };
    } catch (error) {
      if (error instanceof InvalidIdentityTokenError) {
        throw error;
      }

      throw new InvalidIdentityTokenError();
    }
  }

  private async keyForId(keyId: string): Promise<CryptoKey> {
    const existing = this.importedKeys.get(keyId);
    if (existing != null) {
      return existing;
    }

    let cache = await this.getKeyCache();
    let jwk = cache.keys.get(keyId);
    if (jwk == null) {
      this.keyCache = null;
      this.importedKeys.clear();
      cache = await this.getKeyCache();
      jwk = cache.keys.get(keyId);
    }

    if (jwk == null) {
      throw new InvalidIdentityTokenError();
    }

    const key = await crypto.subtle.importKey(
      'jwk',
      {
        kty: jwk.kty,
        n: jwk.n,
        e: jwk.e,
        alg: jwk.alg,
        use: jwk.use ?? 'sig',
      },
      {
        name: 'RSASSA-PKCS1-v1_5',
        hash: 'SHA-256',
      },
      false,
      ['verify'],
    );

    this.importedKeys.set(keyId, key);
    return key;
  }

  private async getKeyCache(): Promise<KeyCache> {
    const existing = this.keyCache;
    if (existing != null && existing.expiresAtMs > this.now()) {
      return existing;
    }

    const response = await this.fetcher(FIREBASE_JWKS_URL);
    if (!response.ok) {
      throw new InvalidIdentityTokenError(
        'Firebase signing keys are temporarily unavailable.',
      );
    }

    const body: unknown = await response.json();
    if (!isRecord(body) || !Array.isArray(body.keys)) {
      throw new InvalidIdentityTokenError(
        'Firebase signing keys are temporarily unavailable.',
      );
    }

    const keys = new Map<string, FirebaseJwk>();
    for (const candidate of body.keys) {
      const jwk = readFirebaseJwk(candidate);
      if (jwk != null) {
        keys.set(jwk.kid, jwk);
      }
    }

    if (keys.size === 0) {
      throw new InvalidIdentityTokenError(
        'Firebase signing keys are temporarily unavailable.',
      );
    }

    const cache: KeyCache = {
      expiresAtMs:
        this.now() +
        parseMaxAge(response.headers.get('cache-control')) * 1000,
      keys,
    };
    this.keyCache = cache;
    return cache;
  }
}

function readHeader(encoded: string): JwtHeader {
  const value = decodeJsonObject(encoded);
  const alg = value.alg;
  const kid = value.kid;
  if (typeof alg !== 'string' || typeof kid !== 'string') {
    throw new InvalidIdentityTokenError();
  }

  return { alg, kid };
}

function readPayload(encoded: string): JwtPayload {
  const value = decodeJsonObject(encoded);
  const { aud, iss, sub, exp, iat, auth_time: authTime } = value;

  if (
    typeof aud !== 'string' ||
    typeof iss !== 'string' ||
    typeof sub !== 'string' ||
    typeof exp !== 'number' ||
    !Number.isFinite(exp) ||
    typeof iat !== 'number' ||
    !Number.isFinite(iat) ||
    typeof authTime !== 'number' ||
    !Number.isFinite(authTime)
  ) {
    throw new InvalidIdentityTokenError();
  }

  const email =
    typeof value.email === 'string' && value.email.length > 0
      ? value.email
      : undefined;
  const emailVerified =
    typeof value.email_verified === 'boolean'
      ? value.email_verified
      : undefined;

  return {
    aud,
    iss,
    sub,
    exp,
    iat,
    auth_time: authTime,
    ...(email == null ? {} : { email }),
    ...(emailVerified == null ? {} : { email_verified: emailVerified }),
  };
}

function readFirebaseJwk(value: unknown): FirebaseJwk | null {
  if (!isRecord(value)) {
    return null;
  }

  const { kid, kty, alg, use, n, e } = value;
  if (
    typeof kid !== 'string' ||
    kid.length === 0 ||
    kty !== 'RSA' ||
    alg !== 'RS256' ||
    (use != null && use !== 'sig') ||
    typeof n !== 'string' ||
    n.length === 0 ||
    typeof e !== 'string' ||
    e.length === 0
  ) {
    return null;
  }

  return {
    kid,
    kty,
    alg,
    ...(use === 'sig' ? { use } : {}),
    n,
    e,
  };
}

function decodeJsonObject(encoded: string): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(
      new TextDecoder().decode(decodeBase64Url(encoded)),
    );
    if (!isRecord(value)) {
      throw new InvalidIdentityTokenError();
    }
    return value;
  } catch (error) {
    if (error instanceof InvalidIdentityTokenError) {
      throw error;
    }
    throw new InvalidIdentityTokenError();
  }
}

function decodeBase64Url(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new InvalidIdentityTokenError();
  }

  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded =
    normalized + '='.repeat((4 - (normalized.length % 4 || 4)) % 4);

  let decoded: string;
  try {
    decoded = atob(padded);
  } catch {
    throw new InvalidIdentityTokenError();
  }

  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function parseMaxAge(cacheControl: string | null): number {
  if (cacheControl == null) {
    return DEFAULT_KEY_CACHE_SECONDS;
  }

  const match = /(?:^|,)\s*max-age=(\d+)/i.exec(cacheControl);
  const parsed = match == null ? Number.NaN : Number(match[1]);

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_KEY_CACHE_SECONDS;
  }

  return parsed;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}

class ArgumentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ArgumentError';
  }
}
