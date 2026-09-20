import type { PushPlatform, RiderPushToken } from './models';

export interface PushRepository {
  registerToken(input: {
    readonly id: string;
    readonly riderId: string;
    readonly token: string;
    readonly platform: PushPlatform;
    readonly now: string;
  }): Promise<RiderPushToken>;

  unregisterToken(riderId: string, token: string): Promise<void>;

  listRideTokens(
    rideId: string,
    options?: {
      readonly excludeRiderId?: string;
      readonly leaderOnly?: boolean;
    },
  ): Promise<readonly RiderPushToken[]>;

  claimEvent(input: {
    readonly eventKey: string;
    readonly rideId: string;
    readonly kind: string;
    readonly createdAt: string;
  }): Promise<boolean>;

  deleteToken(token: string): Promise<void>;
}

interface PushTokenRow {
  readonly id: string;
  readonly rider_id: string;
  readonly token: string;
  readonly platform: PushPlatform;
  readonly created_at: string;
  readonly updated_at: string;
}

export class D1PushRepository implements PushRepository {
  constructor(private readonly database: D1Database) {}

  async registerToken(input: {
    readonly id: string;
    readonly riderId: string;
    readonly token: string;
    readonly platform: PushPlatform;
    readonly now: string;
  }): Promise<RiderPushToken> {
    await this.database
      .prepare(
        `
        INSERT INTO rider_push_tokens(
          id,
          rider_id,
          token,
          platform,
          created_at,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(token) DO UPDATE SET
          rider_id = excluded.rider_id,
          platform = excluded.platform,
          updated_at = excluded.updated_at
        `,
      )
      .bind(
        input.id,
        input.riderId,
        input.token,
        input.platform,
        input.now,
        input.now,
      )
      .run();

    const row = await this.database
      .prepare(
        `
        SELECT id, rider_id, token, platform, created_at, updated_at
        FROM rider_push_tokens
        WHERE token = ?
        LIMIT 1
        `,
      )
      .bind(input.token)
      .first<PushTokenRow>();

    if (row == null) {
      throw new Error('Push token was not persisted.');
    }
    return mapToken(row);
  }

  async unregisterToken(riderId: string, token: string): Promise<void> {
    await this.database
      .prepare(
        `
        DELETE FROM rider_push_tokens
        WHERE rider_id = ? AND token = ?
        `,
      )
      .bind(riderId, token)
      .run();
  }

  async listRideTokens(
    rideId: string,
    options: {
      readonly excludeRiderId?: string;
      readonly leaderOnly?: boolean;
    } = {},
  ): Promise<readonly RiderPushToken[]> {
    const rows = await this.database
      .prepare(
        `
        SELECT
          tokens.id,
          tokens.rider_id,
          tokens.token,
          tokens.platform,
          tokens.created_at,
          tokens.updated_at
        FROM rider_push_tokens AS tokens
        JOIN ride_memberships AS memberships
          ON memberships.rider_id = tokens.rider_id
        WHERE
          memberships.ride_id = ?
          AND memberships.status NOT IN ('invited', 'left')
          AND (? IS NULL OR memberships.rider_id != ?)
          AND (? = 0 OR memberships.role = 'leader')
        ORDER BY tokens.updated_at DESC, tokens.id
        `,
      )
      .bind(
        rideId,
        options.excludeRiderId ?? null,
        options.excludeRiderId ?? null,
        options.leaderOnly === true ? 1 : 0,
      )
      .all<PushTokenRow>();

    return rows.results.map(mapToken);
  }

  async claimEvent(input: {
    readonly eventKey: string;
    readonly rideId: string;
    readonly kind: string;
    readonly createdAt: string;
  }): Promise<boolean> {
    const result = await this.database
      .prepare(
        `
        INSERT INTO push_notification_events(
          event_key,
          ride_id,
          kind,
          created_at
        ) VALUES (?, ?, ?, ?)
        ON CONFLICT(event_key) DO NOTHING
        `,
      )
      .bind(
        input.eventKey,
        input.rideId,
        input.kind,
        input.createdAt,
      )
      .run();

    return (result.meta.changes ?? 0) > 0;
  }

  async deleteToken(token: string): Promise<void> {
    await this.database
      .prepare('DELETE FROM rider_push_tokens WHERE token = ?')
      .bind(token)
      .run();
  }
}

function mapToken(row: PushTokenRow): RiderPushToken {
  return {
    id: row.id,
    riderId: row.rider_id,
    token: row.token,
    platform: row.platform,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
