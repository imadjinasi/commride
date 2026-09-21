import {
  createPublicKey,
  verify as verifySignature,
} from 'node:crypto';

import {
  type AuthenticatedIdentity,
  type IdentityVerifier,
  InvalidIdentityTokenError,
} from './identity';

const FIREBASE_CERTIFICATES_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/' +
  'securetoken@system.gserviceaccount.com';
const DEFAULT_CERTIFICATE_CACHE_SECONDS = 300;

type VerificationKey = ReturnType<typeof createPublicKey>;

interface CertificateCache {
  readonly expiresAtMs: number;
  readonly certificates: ReadonlyMap<string, string>;
}

interface ImportedKeyCacheEntry {
  readonly expiresAtMs: number;
  readonly key: VerificationKey;
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

type FailureStage =
  | 'token_shape'
  | 'header'
  | 'certificate_network'
  | 'certificate_http'
  | 'certificate_json'
  | 'certificate_empty'
  | 'certificate_missing'
  | 'public_key_import'
  | 'signature'
  | 'payload'
  | 'claims';

class VerificationFailure extends Error {
  constructor(readonly stage: FailureStage) {
    super(stage);
    this.name = 'VerificationFailure';
  }
}

class CertificateHttpFailure extends VerificationFailure {
  constructor(readonly status: number) {
    super('certificate_http');
    this.name = 'CertificateHttpFailure';
  }
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

  private certificateCache: CertificateCache | null = null;
  private readonly importedKeys = new Map<string, ImportedKeyCacheEntry>();

  async verify(token: string): Promise<AuthenticatedIdentity> {
    try {
      const segments = token.split('.');
      if (
        segments.length !== 3 ||
        segments.some((segment) => segment.length === 0)
      ) {
        throw new VerificationFailure('token_shape');
      }

      const [encodedHeader, encodedPayload, encodedSignature] = segments;
      const header = readHeader(encodedHeader);
      if (header.alg !== 'RS256' || header.kid.length === 0) {
        throw new VerificationFailure('header');
      }

      const key = await this.keyForId(header.kid);
      const verified = verifySignature(
        'RSA-SHA256',
        new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
        key,
        decodeBase64Url(encodedSignature),
      );

      if (!verified) {
        throw new VerificationFailure('signature');
      }

      const payload = readPayload(encodedPayload);
      const nowSeconds = Math.floor(this.now() / 1000);
      if (
        payload.aud !== this.projectId ||
        payload.iss !== `https://securetoken.google.com/${this.projectId}` ||
        payload.sub.length === 0 ||
        payload.sub.length > 128 ||
        payload.exp <= nowSeconds ||
        payload.iat > nowSeconds ||
        payload.auth_time > nowSeconds
      ) {
        throw new VerificationFailure('claims');
      }

      return {
        subject: payload.sub,
        ...(payload.email == null ? {} : { email: payload.email }),
        ...(payload.email_verified == null
          ? {}
          : { emailVerified: payload.email_verified }),
      };
    } catch (error) {
      if (error instanceof CertificateHttpFailure) {
        console.warn('firebase_id_token_verification_failed', {
          stage: error.stage,
          status: error.status,
        });
      } else if (error instanceof VerificationFailure) {
        console.warn('firebase_id_token_verification_failed', {
          stage: error.stage,
        });
      } else {
        console.warn('firebase_id_token_verification_failed', {
          stage: 'public_key_import',
        });
      }

      throw new InvalidIdentityTokenError();
    }
  }

  private async keyForId(keyId: string): Promise<VerificationKey> {
    const existing = this.importedKeys.get(keyId);
    if (existing != null && existing.expiresAtMs > this.now()) {
      return existing.key;
    }
    this.importedKeys.delete(keyId);

    let cache = await this.getCertificateCache();
    let certificate = cache.certificates.get(keyId);
    if (certificate == null) {
      this.certificateCache = null;
      this.importedKeys.clear();
      cache = await this.getCertificateCache();
      certificate = cache.certificates.get(keyId);
    }

    if (certificate == null) {
      throw new VerificationFailure('certificate_missing');
    }

    let key: VerificationKey;
    try {
      key = createPublicKey(certificate);
    } catch {
      throw new VerificationFailure('public_key_import');
    }

    this.importedKeys.set(keyId, {
      expiresAtMs: cache.expiresAtMs,
      key,
    });
    return key;
  }

  private async getCertificateCache(): Promise<CertificateCache> {
    const existing = this.certificateCache;
    if (existing != null && existing.expiresAtMs > this.now()) {
      return existing;
    }

    let response: Response;
    try {
      response = await this.fetcher(FIREBASE_CERTIFICATES_URL, {
        headers: {
          accept: 'application/json',
        },
      });
    } catch {
      throw new VerificationFailure('certificate_network');
    }

    if (!response.ok) {
      throw new CertificateHttpFailure(response.status);
    }

    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new VerificationFailure('certificate_json');
    }

    if (!isRecord(body)) {
      throw new VerificationFailure('certificate_json');
    }

    const certificates = new Map<string, string>();
    for (const [keyId, certificate] of Object.entries(body)) {
      if (
        keyId.length > 0 &&
        typeof certificate === 'string' &&
        certificate.includes('-----BEGIN CERTIFICATE-----') &&
        certificate.includes('-----END CERTIFICATE-----')
      ) {
        certificates.set(keyId, certificate);
      }
    }

    if (certificates.size === 0) {
      throw new VerificationFailure('certificate_empty');
    }

    const cache: CertificateCache = {
      expiresAtMs:
        this.now() +
        parseMaxAge(response.headers.get('cache-control')) * 1000,
      certificates,
    };
    this.certificateCache = cache;
    return cache;
  }
}

function readHeader(encoded: string): JwtHeader {
  let value: Record<string, unknown>;
  try {
    value = decodeJsonObject(encoded);
  } catch {
    throw new VerificationFailure('header');
  }

  const alg = value.alg;
  const kid = value.kid;
  if (typeof alg !== 'string' || typeof kid !== 'string') {
    throw new VerificationFailure('header');
  }

  return { alg, kid };
}

function readPayload(encoded: string): JwtPayload {
  let value: Record<string, unknown>;
  try {
    value = decodeJsonObject(encoded);
  } catch {
    throw new VerificationFailure('payload');
  }

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
    throw new VerificationFailure('payload');
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

function decodeJsonObject(encoded: string): Record<string, unknown> {
  const value: unknown = JSON.parse(
    new TextDecoder().decode(decodeBase64Url(encoded)),
  );
  if (!isRecord(value)) {
    throw new Error('JWT section must be an object.');
  }
  return value;
}

function decodeBase64Url(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error('Invalid base64url.');
  }

  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded =
    normalized + '='.repeat((4 - (normalized.length % 4 || 4)) % 4);

  let decoded: string;
  try {
    decoded = atob(padded);
  } catch {
    throw new Error('Invalid base64url.');
  }

  const bytes = new Uint8Array(decoded.length);
  for (let index = 0; index < decoded.length; index += 1) {
    bytes[index] = decoded.charCodeAt(index);
  }
  return bytes;
}

function parseMaxAge(cacheControl: string | null): number {
  if (cacheControl == null) {
    return DEFAULT_CERTIFICATE_CACHE_SECONDS;
  }

  const match = /(?:^|,)\s*max-age=(\d+)/i.exec(cacheControl);
  const parsed = match == null ? Number.NaN : Number(match[1]);

  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_CERTIFICATE_CACHE_SECONDS;
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
