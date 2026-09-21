import type { PushDeliveryResult, RiderPushToken } from './models';
import type { PushRepository } from './repository';

interface AccessToken {
  readonly token: string;
  readonly expiresAtMs: number;
}

export interface PushTransport {
  sendToTokens(
    tokens: readonly RiderPushToken[],
    message: {
      readonly title: string;
      readonly body: string;
      readonly data: Readonly<Record<string, string>>;
    },
  ): Promise<PushDeliveryResult>;
}

export class FcmHttpV1Transport implements PushTransport {
  private accessToken: AccessToken | null = null;

  constructor(
    private readonly options: {
      readonly projectId: string;
      readonly clientEmail: string;
      readonly privateKeyPem: string;
      readonly pushRepository: PushRepository;
      readonly fetchImpl?: typeof fetch;
      readonly now?: () => Date;
    },
  ) {}

  async sendToTokens(
    tokens: readonly RiderPushToken[],
    message: {
      readonly title: string;
      readonly body: string;
      readonly data: Readonly<Record<string, string>>;
    },
  ): Promise<PushDeliveryResult> {
    if (tokens.length === 0) {
      return { delivered: 0, failed: 0 };
    }

    const token = await this.googleAccessToken();
    let delivered = 0;
    let failed = 0;

    for (const destination of tokens) {
      try {
        const response = await (this.options.fetchImpl ?? fetch)(
          `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(
            this.options.projectId,
          )}/messages:send`,
          {
            method: 'POST',
            headers: {
              authorization: `Bearer ${token}`,
              'content-type': 'application/json',
            },
            body: JSON.stringify({
              message: {
                token: destination.token,
                notification: {
                  title: message.title,
                  body: message.body,
                },
                data: message.data,
                android: {
                  priority: 'high',
                },
                apns: {
                  headers: {
                    'apns-priority': '10',
                  },
                },
              },
            }),
          },
        );

        if (response.ok) {
          delivered += 1;
          continue;
        }

        failed += 1;
        const body = await safeJson(response);
        if (isUnregistered(body)) {
          await this.options.pushRepository.deleteToken(destination.token);
        }
      } catch {
        failed += 1;
      }
    }

    return { delivered, failed };
  }

  private async googleAccessToken(): Promise<string> {
    const nowMs = (this.options.now?.() ?? new Date()).getTime();
    if (
      this.accessToken != null &&
      this.accessToken.expiresAtMs - 60_000 > nowMs
    ) {
      return this.accessToken.token;
    }

    const assertion = await serviceAccountAssertion(
      this.options.clientEmail,
      this.options.privateKeyPem,
      nowMs,
    );
    const response = await (this.options.fetchImpl ?? fetch)(
      'https://oauth2.googleapis.com/token',
      {
        method: 'POST',
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          assertion,
        }).toString(),
      },
    );
    if (!response.ok) {
      throw new Error('FCM OAuth token exchange failed.');
    }

    const decoded = await response.json() as {
      readonly access_token?: unknown;
      readonly expires_in?: unknown;
    };
    if (
      typeof decoded.access_token !== 'string' ||
      typeof decoded.expires_in !== 'number'
    ) {
      throw new Error('FCM OAuth token response is invalid.');
    }

    this.accessToken = {
      token: decoded.access_token,
      expiresAtMs: nowMs + decoded.expires_in * 1000,
    };
    return decoded.access_token;
  }
}

async function serviceAccountAssertion(
  clientEmail: string,
  privateKeyPem: string,
  nowMs: number,
): Promise<string> {
  const issuedAt = Math.floor(nowMs / 1000);
  const header = base64UrlJson({ alg: 'RS256', typ: 'JWT' });
  const claim = base64UrlJson({
    iss: clientEmail,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: issuedAt,
    exp: issuedAt + 3600,
  });
  const unsigned = `${header}.${claim}`;

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKeyPem),
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64Url(new Uint8Array(signature))}`;
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const normalized = pem
    .replaceAll('\\n', '\n')
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

async function safeJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

function isUnregistered(value: unknown): boolean {
  if (typeof value !== 'object' || value == null) {
    return false;
  }
  const text = JSON.stringify(value);
  return text.includes('UNREGISTERED') || text.includes('registration-token-not-registered');
}
