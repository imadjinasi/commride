import { SignJWT } from 'jose';

/**
 * Voice intercom room provider. Provider payloads stay inside the adapter;
 * the handler only sees a join token and a mute result.
 */
export type IntercomPreset = 'rider' | 'leader';

export interface IntercomJoinInput {
  readonly rideId: string;
  readonly riderId: string;
  readonly displayName: string;
}

export interface IntercomRoomProvider {
  readonly name: 'livekit';
  /** WebSocket URL the client SDK connects to. */
  readonly clientUrl: string;
  mintJoinToken(input: IntercomJoinInput): Promise<string>;
  /**
   * Mutes the Rider's microphone track for everyone in the Ride room.
   * Returns false when that Rider is not publishing a microphone there.
   */
  muteRider(rideId: string, riderId: string): Promise<boolean>;
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

export interface LiveKitConfig {
  /** wss:// project URL from LiveKit Cloud. */
  readonly url: string;
  readonly apiKey: string;
  readonly apiSecret: string;
}

/** One room per Ride; LiveKit creates it on the first join. */
export function liveKitRoomName(rideId: string): string {
  return `commride-ride-${rideId}`;
}

// Long enough for a full Ride; a rejoin asks the Worker for a new token.
const JOIN_TOKEN_TTL_SECONDS = 6 * 60 * 60;
const ADMIN_TOKEN_TTL_SECONDS = 60;

const workerFetch: typeof fetch = (input, init) => fetch(input, init);

interface LiveKitTrackJson {
  readonly sid?: unknown;
  readonly source?: unknown;
}

interface LiveKitParticipantJson {
  readonly identity?: unknown;
  readonly tracks?: readonly LiveKitTrackJson[];
}

export class LiveKitRoomProvider implements IntercomRoomProvider {
  readonly name = 'livekit' as const;

  constructor(
    private readonly config: LiveKitConfig,
    private readonly fetcher: typeof fetch = workerFetch,
    private readonly now: () => Date = () => new Date(),
  ) {}

  get clientUrl(): string {
    return this.config.url;
  }

  mintJoinToken(input: IntercomJoinInput): Promise<string> {
    // Riders publish their microphone only. Leader mute goes through the
    // Worker, so no client ever gets room admin.
    return this.sign(
      input.riderId,
      {
        room: liveKitRoomName(input.rideId),
        roomJoin: true,
        canSubscribe: true,
        canPublish: true,
        canPublishData: false,
        canPublishSources: ['microphone'],
      },
      JOIN_TOKEN_TTL_SECONDS,
      input.displayName,
    );
  }

  async muteRider(rideId: string, riderId: string): Promise<boolean> {
    const room = liveKitRoomName(rideId);
    const listed = (await this.roomService('ListParticipants', room, {
      room,
    })) as { participants?: readonly LiveKitParticipantJson[] };
    const participant = listed.participants?.find(
      (item) => item.identity === riderId,
    );
    const track = participant?.tracks?.find(isMicrophone);
    if (track == null || typeof track.sid !== 'string') {
      return false;
    }

    await this.roomService('MutePublishedTrack', room, {
      room,
      identity: riderId,
      track_sid: track.sid,
      muted: true,
    });
    return true;
  }

  private async roomService(
    method: string,
    room: string,
    body: unknown,
  ): Promise<unknown> {
    const token = await this.sign(
      'commride-api',
      { room, roomAdmin: true },
      ADMIN_TOKEN_TTL_SECONDS,
    );
    const response = await this.fetcher(
      `${httpBase(this.config.url)}/twirp/livekit.RoomService/${method}`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${token}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify(body),
      },
    );
    if (!response.ok) {
      throw new IntercomProviderError(
        `LiveKit ${method} failed (${response.status}).`,
        response.status,
      );
    }
    return response.json();
  }

  private sign(
    identity: string,
    video: Record<string, unknown>,
    ttlSeconds: number,
    name?: string,
  ): Promise<string> {
    const issuedAt = Math.floor(this.now().getTime() / 1000);
    return new SignJWT({ video, ...(name == null ? {} : { name }) })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setIssuer(this.config.apiKey)
      .setSubject(identity)
      .setNotBefore(issuedAt)
      .setExpirationTime(issuedAt + ttlSeconds)
      .sign(new TextEncoder().encode(this.config.apiSecret));
  }
}

function isMicrophone(track: LiveKitTrackJson): boolean {
  return track.source === 'MICROPHONE' || track.source === 2;
}

function httpBase(url: string): string {
  return url
    .replace(/^wss:/, 'https:')
    .replace(/^ws:/, 'http:')
    .replace(/\/+$/, '');
}
