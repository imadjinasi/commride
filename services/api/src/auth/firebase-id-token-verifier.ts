import {
  importX509,
  jwtVerify,
  type JWTHeaderParameters,
} from 'jose';

import {
  type AuthenticatedIdentity,
  type IdentityVerifier,
  InvalidIdentityTokenError,
} from './identity';

const FIREBASE_CERTIFICATES_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/' +
  'securetoken@system.gserviceaccount.com';
const DEFAULT_CERTIFICATE_CACHE_SECONDS = 300;

type VerificationKey = Awaited<ReturnType<typeof importX509>>;

interface CertificateCache {
  readonly expiresAtMs: number;
  readonly keys: ReadonlyMap<string, VerificationKey>;
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

  async verify(token: string): Promise<AuthenticatedIdentity> {
    try {
      const { payload } = await jwtVerify(
        token,
        async (protectedHeader: JWTHeaderParameters) => {
          if (
            protectedHeader.alg !== 'RS256' ||
            protectedHeader.kid == null ||
            protectedHeader.kid.length === 0
          ) {
            throw new InvalidIdentityTokenError();
          }

          return this.keyForId(protectedHeader.kid);
        },
        {
          algorithms: ['RS256'],
          audience: this.projectId,
          issuer: `https://securetoken.google.com/${this.projectId}`,
        },
      );

      const nowSeconds = Math.floor(this.now() / 1000);

      if (
        payload.sub == null ||
        payload.sub.length === 0 ||
        payload.iat == null ||
        payload.iat > nowSeconds ||
        typeof payload.auth_time !== 'number' ||
        payload.auth_time > nowSeconds
      ) {
        throw new InvalidIdentityTokenError();
      }

      return {
        subject: payload.sub,
        ...(typeof payload.email === 'string'
          ? { email: payload.email }
          : {}),
        ...(typeof payload.email_verified === 'boolean'
          ? { emailVerified: payload.email_verified }
          : {}),
      };
    } catch (error) {
      if (error instanceof InvalidIdentityTokenError) {
        throw error;
      }

      throw new InvalidIdentityTokenError();
    }
  }

  private async keyForId(keyId: string): Promise<VerificationKey> {
    const cache = await this.getCertificateCache();
    const key = cache.keys.get(keyId);

    if (key == null) {
      this.certificateCache = null;
      const refreshed = await this.getCertificateCache();
      const refreshedKey = refreshed.keys.get(keyId);

      if (refreshedKey == null) {
        throw new InvalidIdentityTokenError();
      }

      return refreshedKey;
    }

    return key;
  }

  private async getCertificateCache(): Promise<CertificateCache> {
    const existing = this.certificateCache;
    if (existing != null && existing.expiresAtMs > this.now()) {
      return existing;
    }

    const response = await this.fetcher(FIREBASE_CERTIFICATES_URL);
    if (!response.ok) {
      throw new InvalidIdentityTokenError(
        'Firebase signing keys are temporarily unavailable.',
      );
    }

    const certificates = (await response.json()) as Record<string, unknown>;
    const keys = new Map<string, VerificationKey>();

    for (const [keyId, certificate] of Object.entries(certificates)) {
      if (typeof certificate !== 'string') {
        continue;
      }

      keys.set(keyId, await importX509(certificate, 'RS256'));
    }

    if (keys.size === 0) {
      throw new InvalidIdentityTokenError(
        'Firebase signing keys are temporarily unavailable.',
      );
    }

    const maxAgeSeconds = parseMaxAge(
      response.headers.get('cache-control'),
    );

    const cache: CertificateCache = {
      expiresAtMs: this.now() + maxAgeSeconds * 1000,
      keys,
    };
    this.certificateCache = cache;
    return cache;
  }
}

class ArgumentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ArgumentError';
  }
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
