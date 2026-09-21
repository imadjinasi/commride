import {
  type AuthenticatedIdentity,
  type IdentityVerifier,
  InvalidIdentityTokenError,
} from './identity';

const FIREBASE_CERTIFICATES_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/' +
  'securetoken@system.gserviceaccount.com';
const DEFAULT_CERTIFICATE_CACHE_SECONDS = 300;

interface CertificateCache {
  readonly expiresAtMs: number;
  readonly certificates: ReadonlyMap<string, string>;
}

interface ImportedKeyCacheEntry {
  readonly expiresAtMs: number;
  readonly key: CryptoKey;
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

interface DerElement {
  readonly tag: number;
  readonly start: number;
  readonly contentStart: number;
  readonly end: number;
  readonly next: number;
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
      throw new InvalidIdentityTokenError();
    }

    const spki = extractSubjectPublicKeyInfo(certificate);
    const key = await crypto.subtle.importKey(
      'spki',
      spki,
      {
        name: 'RSASSA-PKCS1-v1_5',
        hash: 'SHA-256',
      },
      false,
      ['verify'],
    );

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

    const response = await this.fetcher(FIREBASE_CERTIFICATES_URL);
    if (!response.ok) {
      throw new InvalidIdentityTokenError(
        'Firebase signing keys are temporarily unavailable.',
      );
    }

    const body: unknown = await response.json();
    if (!isRecord(body)) {
      throw new InvalidIdentityTokenError(
        'Firebase signing keys are temporarily unavailable.',
      );
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
      throw new InvalidIdentityTokenError(
        'Firebase signing keys are temporarily unavailable.',
      );
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

function extractSubjectPublicKeyInfo(certificatePem: string): Uint8Array<ArrayBuffer> {
  const der = decodeCertificatePem(certificatePem);
  const certificate = readDerElement(der, 0);
  requireTag(certificate, 0x30);

  if (certificate.next !== der.length) {
    throw new InvalidIdentityTokenError();
  }

  const tbsCertificate = readDerElement(der, certificate.contentStart);
  requireTag(tbsCertificate, 0x30);

  let offset = tbsCertificate.contentStart;
  let field = readDerElement(der, offset);

  if (field.tag === 0xa0) {
    offset = field.next;
    field = readDerElement(der, offset);
  }

  requireTag(field, 0x02);
  offset = field.next;

  field = readDerElement(der, offset);
  requireTag(field, 0x30);
  offset = field.next;

  field = readDerElement(der, offset);
  requireTag(field, 0x30);
  offset = field.next;

  field = readDerElement(der, offset);
  requireTag(field, 0x30);
  offset = field.next;

  field = readDerElement(der, offset);
  requireTag(field, 0x30);
  offset = field.next;

  const subjectPublicKeyInfo = readDerElement(der, offset);
  requireTag(subjectPublicKeyInfo, 0x30);

  if (subjectPublicKeyInfo.next > tbsCertificate.end) {
    throw new InvalidIdentityTokenError();
  }

  const result = new Uint8Array(
    subjectPublicKeyInfo.next - subjectPublicKeyInfo.start,
  );
  result.set(
    der.subarray(subjectPublicKeyInfo.start, subjectPublicKeyInfo.next),
  );
  return result;
}

function readDerElement(bytes: Uint8Array, offset: number): DerElement {
  if (offset < 0 || offset + 2 > bytes.length) {
    throw new InvalidIdentityTokenError();
  }

  const tag = bytes[offset];
  const firstLengthByte = bytes[offset + 1];

  let length = 0;
  let contentStart = offset + 2;

  if ((firstLengthByte & 0x80) === 0) {
    length = firstLengthByte;
  } else {
    const lengthBytes = firstLengthByte & 0x7f;
    if (
      lengthBytes === 0 ||
      lengthBytes > 4 ||
      contentStart + lengthBytes > bytes.length
    ) {
      throw new InvalidIdentityTokenError();
    }

    for (let index = 0; index < lengthBytes; index += 1) {
      length = length * 256 + bytes[contentStart + index];
    }
    contentStart += lengthBytes;

    if (length < 128) {
      throw new InvalidIdentityTokenError();
    }
  }

  const end = contentStart + length;
  if (end > bytes.length) {
    throw new InvalidIdentityTokenError();
  }

  return {
    tag,
    start: offset,
    contentStart,
    end,
    next: end,
  };
}

function requireTag(element: DerElement, expected: number): void {
  if (element.tag !== expected) {
    throw new InvalidIdentityTokenError();
  }
}

function decodeCertificatePem(value: string): Uint8Array<ArrayBuffer> {
  const base64 = value
    .replace('-----BEGIN CERTIFICATE-----', '')
    .replace('-----END CERTIFICATE-----', '')
    .replace(/\s+/g, '');

  if (base64.length === 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    throw new InvalidIdentityTokenError();
  }

  return decodeBase64(base64);
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

function decodeBase64Url(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new InvalidIdentityTokenError();
  }

  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded =
    normalized + '='.repeat((4 - (normalized.length % 4 || 4)) % 4);
  return decodeBase64(padded);
}

function decodeBase64(value: string): Uint8Array<ArrayBuffer> {
  let decoded: string;
  try {
    decoded = atob(value);
  } catch {
    throw new InvalidIdentityTokenError();
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
