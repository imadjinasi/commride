import type {
  CreateNotificationInput,
  NotificationScope,
  RiderNotification,
} from './models';

export interface NotificationRepository {
  createForRider(
    riderId: string,
    input: CreateNotificationInput,
  ): Promise<void>;

  createForClubMembers(
    clubId: string,
    input: CreateNotificationInput,
    options?: { readonly excludeRiderId?: string },
  ): Promise<void>;

  createForRideParticipants(
    rideId: string,
    input: CreateNotificationInput,
    options?: { readonly excludeRiderId?: string },
  ): Promise<void>;

  listForRider(
    riderId: string,
    options?: {
      readonly scope?: NotificationScope;
      readonly clubId?: string;
      readonly limit?: number;
    },
  ): Promise<readonly RiderNotification[]>;

  markRead(riderId: string, notificationId: string, readAt: string): Promise<boolean>;
}

interface NotificationRow {
  readonly id: string;
  readonly rider_id: string;
  readonly scope: NotificationScope;
  readonly club_id: string | null;
  readonly ride_id: string | null;
  readonly event_key: string;
  readonly kind: string;
  readonly title: string;
  readonly body: string;
  readonly data_json: string;
  readonly created_at: string;
  readonly read_at: string | null;
}

export class D1NotificationRepository implements NotificationRepository {
  constructor(private readonly database: D1Database) {}

  async createForRider(
    riderId: string,
    input: CreateNotificationInput,
  ): Promise<void> {
    await this.database
      .prepare(
        `
        INSERT INTO rider_notifications(
          id, rider_id, scope, club_id, ride_id, event_key, kind,
          title, body, data_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(rider_id, event_key) DO NOTHING
        `,
      )
      .bind(
        crypto.randomUUID(),
        riderId,
        input.scope,
        input.clubId ?? null,
        input.rideId ?? null,
        input.eventKey,
        input.kind,
        input.title,
        input.body,
        JSON.stringify(input.data ?? {}),
        input.createdAt,
      )
      .run();
  }

  async createForClubMembers(
    clubId: string,
    input: CreateNotificationInput,
    options: { readonly excludeRiderId?: string } = {},
  ): Promise<void> {
    await this.database
      .prepare(
        `
        INSERT OR IGNORE INTO rider_notifications(
          id, rider_id, scope, club_id, ride_id, event_key, kind,
          title, body, data_json, created_at
        )
        SELECT
          lower(hex(randomblob(16))),
          memberships.rider_id,
          ?,
          ?,
          ?,
          ?,
          ?,
          ?,
          ?,
          ?,
          ?
        FROM club_memberships AS memberships
        WHERE
          memberships.club_id = ?
          AND memberships.status = 'active'
          AND (? IS NULL OR memberships.rider_id != ?)
        `,
      )
      .bind(
        input.scope,
        clubId,
        input.rideId ?? null,
        input.eventKey,
        input.kind,
        input.title,
        input.body,
        JSON.stringify(input.data ?? {}),
        input.createdAt,
        clubId,
        options.excludeRiderId ?? null,
        options.excludeRiderId ?? null,
      )
      .run();
  }

  async createForRideParticipants(
    rideId: string,
    input: CreateNotificationInput,
    options: { readonly excludeRiderId?: string } = {},
  ): Promise<void> {
    await this.database
      .prepare(
        `
        INSERT OR IGNORE INTO rider_notifications(
          id, rider_id, scope, club_id, ride_id, event_key, kind,
          title, body, data_json, created_at
        )
        SELECT
          lower(hex(randomblob(16))),
          memberships.rider_id,
          ?,
          ?,
          ?,
          ?,
          ?,
          ?,
          ?,
          ?,
          ?
        FROM ride_memberships AS memberships
        WHERE
          memberships.ride_id = ?
          AND memberships.status NOT IN ('invited', 'left')
          AND (? IS NULL OR memberships.rider_id != ?)
        `,
      )
      .bind(
        input.scope,
        input.clubId ?? null,
        rideId,
        input.eventKey,
        input.kind,
        input.title,
        input.body,
        JSON.stringify(input.data ?? {}),
        input.createdAt,
        rideId,
        options.excludeRiderId ?? null,
        options.excludeRiderId ?? null,
      )
      .run();
  }

  async listForRider(
    riderId: string,
    options: {
      readonly scope?: NotificationScope;
      readonly clubId?: string;
      readonly limit?: number;
    } = {},
  ): Promise<readonly RiderNotification[]> {
    const limit = Math.min(Math.max(options.limit ?? 50, 1), 100);
    const rows = await this.database
      .prepare(
        `
        SELECT
          id, rider_id, scope, club_id, ride_id, event_key, kind,
          title, body, data_json, created_at, read_at
        FROM rider_notifications
        WHERE
          rider_id = ?
          AND (? IS NULL OR scope = ?)
          AND (? IS NULL OR club_id = ?)
        ORDER BY created_at DESC, id DESC
        LIMIT ?
        `,
      )
      .bind(
        riderId,
        options.scope ?? null,
        options.scope ?? null,
        options.clubId ?? null,
        options.clubId ?? null,
        limit,
      )
      .all<NotificationRow>();

    return rows.results.map(mapNotification);
  }

  async markRead(
    riderId: string,
    notificationId: string,
    readAt: string,
  ): Promise<boolean> {
    const result = await this.database
      .prepare(
        `
        UPDATE rider_notifications
        SET read_at = COALESCE(read_at, ?)
        WHERE id = ? AND rider_id = ?
        `,
      )
      .bind(readAt, notificationId, riderId)
      .run();
    return (result.meta.changes ?? 0) > 0;
  }
}

function mapNotification(row: NotificationRow): RiderNotification {
  let data: Readonly<Record<string, string>> = {};
  try {
    const parsed = JSON.parse(row.data_json);
    if (isStringRecord(parsed)) {
      data = parsed;
    }
  } catch {
    data = {};
  }

  return {
    id: row.id,
    riderId: row.rider_id,
    scope: row.scope,
    clubId: row.club_id,
    rideId: row.ride_id,
    eventKey: row.event_key,
    kind: row.kind,
    title: row.title,
    body: row.body,
    data,
    createdAt: row.created_at,
    readAt: row.read_at,
  };
}

function isStringRecord(value: unknown): value is Record<string, string> {
  if (typeof value !== 'object' || value == null || Array.isArray(value)) {
    return false;
  }
  return Object.values(value).every((entry) => typeof entry === 'string');
}
