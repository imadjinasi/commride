/**
 * Voice intercom room provider. Provider payloads stay inside the adapter;
 * the handler only sees a room id and a join token.
 */
export type IntercomPreset = 'rider' | 'leader';

export interface IntercomParticipantInput {
  readonly roomId: string;
  readonly riderId: string;
  readonly displayName: string;
  readonly preset: IntercomPreset;
}

export interface IntercomRoomProvider {
  readonly name: 'cloudflare_realtimekit';
  /** Value the client SDK needs besides the token (e.g. base domain). */
  readonly clientBaseDomain: string;
  createRoom(title: string): Promise<string>;
  addParticipant(input: IntercomParticipantInput): Promise<string>;
}

export class IntercomProviderError extends Error {
  constructor(
    message: string,
    readonly status: number | null,
  ) {
    super(message);
    this.name = 'IntercomProviderError';
  }
}

export interface RealtimeKitConfig {
  readonly accountId: string;
  readonly appId: string;
  readonly apiToken: string;
  readonly riderPreset: string;
  readonly leaderPreset: string;
}

const workerFetch: typeof fetch = (input, init) => fetch(input, init);

interface RealtimeKitEnvelope {
  readonly success?: boolean;
  readonly data?: { readonly id?: unknown; readonly token?: unknown };
}

export class RealtimeKitRoomProvider implements IntercomRoomProvider {
  readonly name = 'cloudflare_realtimekit' as const;
  readonly clientBaseDomain = 'realtime.cloudflare.com';

  constructor(
    private readonly config: RealtimeKitConfig,
    private readonly fetcher: typeof fetch = workerFetch,
  ) {}

  async createRoom(title: string): Promise<string> {
    const data = await this.post('/meetings', { title });
    if (typeof data.id !== 'string' || data.id.length === 0) {
      throw new IntercomProviderError('Meeting id missing.', null);
    }
    return data.id;
  }

  async addParticipant(input: IntercomParticipantInput): Promise<string> {
    const data = await this.post(
      `/meetings/${encodeURIComponent(input.roomId)}/participants`,
      {
        name: input.displayName,
        custom_participant_id: input.riderId,
        preset_name:
          input.preset === 'leader'
            ? this.config.leaderPreset
            : this.config.riderPreset,
      },
    );
    if (typeof data.token !== 'string' || data.token.length === 0) {
      throw new IntercomProviderError('Participant token missing.', null);
    }
    return data.token;
  }

  private async post(
    path: string,
    body: unknown,
  ): Promise<NonNullable<RealtimeKitEnvelope['data']>> {
    const url =
      'https://api.cloudflare.com/client/v4/accounts/' +
      `${encodeURIComponent(this.config.accountId)}/realtime/kit/` +
      `${encodeURIComponent(this.config.appId)}${path}`;
    const response = await this.fetcher(url, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${this.config.apiToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      throw new IntercomProviderError(
        `RealtimeKit request failed (${response.status}).`,
        response.status,
      );
    }
    const envelope = (await response.json()) as RealtimeKitEnvelope;
    if (envelope.success !== true || envelope.data == null) {
      throw new IntercomProviderError('RealtimeKit request rejected.', null);
    }
    return envelope.data;
  }
}
