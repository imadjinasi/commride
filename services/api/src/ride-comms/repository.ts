import type {
  CreateRideMessageInput,
  RideMessage,
  RideMessageCursor,
  RideMessageKind,
  RideMessagePage,
} from './models';

export interface RideMessageRepository {
  findByClientMessageId(
    rideId: string,
    senderRiderId: string,
    clientMessageId: string,
  ): Promise<RideMessage | null>;

  create(input: CreateRideMessageInput): Promise<RideMessage>;

  list(
    rideId: string,
    limit: number,
    cursor: RideMessageCursor | null,
  ): Promise<RideMessagePage>;
}

interface RideMessageRow {
  readonly id: string;
  readonly ride_id: string;
  readonly sender_rider_id: string;
  readonly sender_display_name: string;
  readonly sender_ride_role: RideMessage['senderRideRole'];
  readonly kind: RideMessageKind;
  readonly body: string;
  readonly client_message_id: string;
  readonly created_at: string;
}

export class D1RideMessageRepository implements RideMessageRepository {
  constructor(private readonly database: D1Database) {}

  async findByClientMessageId(
    rideId: string,
    senderRiderId: string,
    clientMessageId: string,
  ): Promise<RideMessage | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          id,
          ride_id,
          sender_rider_id,
          sender_display_name,
          sender_ride_role,
          kind,
          body,
          client_message_id,
          created_at
        FROM ride_messages
        WHERE
          ride_id = ?
          AND sender_rider_id = ?
          AND client_message_id = ?
        LIMIT 1
        `,
      )
      .bind(rideId, senderRiderId, clientMessageId)
      .first<RideMessageRow>();

    return row == null ? null : mapMessage(row);
  }

  async create(input: CreateRideMessageInput): Promise<RideMessage> {
    await this.database
      .prepare(
        `
        INSERT INTO ride_messages(
          id,
          ride_id,
          sender_rider_id,
          sender_display_name,
          sender_ride_role,
          kind,
          body,
          client_message_id,
          created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(ride_id, sender_rider_id, client_message_id) DO NOTHING
        `,
      )
      .bind(
        input.id,
        input.rideId,
        input.senderRiderId,
        input.senderDisplayName,
        input.senderRideRole,
        input.kind,
        input.body,
        input.clientMessageId,
        input.createdAt,
      )
      .run();

    const persisted = await this.findByClientMessageId(
      input.rideId,
      input.senderRiderId,
      input.clientMessageId,
    );
    if (persisted == null) {
      throw new Error('Ride message was not persisted.');
    }

    return persisted;
  }

  async list(
    rideId: string,
    limit: number,
    cursor: RideMessageCursor | null,
  ): Promise<RideMessagePage> {
    const queryLimit = limit + 1;
    const result = cursor == null
      ? await this.database
          .prepare(
            `
            SELECT
              id,
              ride_id,
              sender_rider_id,
              sender_display_name,
              sender_ride_role,
              kind,
              body,
              client_message_id,
              created_at
            FROM ride_messages
            WHERE ride_id = ?
            ORDER BY created_at DESC, id DESC
            LIMIT ?
            `,
          )
          .bind(rideId, queryLimit)
          .all<RideMessageRow>()
      : await this.database
          .prepare(
            `
            SELECT
              id,
              ride_id,
              sender_rider_id,
              sender_display_name,
              sender_ride_role,
              kind,
              body,
              client_message_id,
              created_at
            FROM ride_messages
            WHERE
              ride_id = ?
              AND (
                created_at < ?
                OR (created_at = ? AND id < ?)
              )
            ORDER BY created_at DESC, id DESC
            LIMIT ?
            `,
          )
          .bind(
            rideId,
            cursor.createdAt,
            cursor.createdAt,
            cursor.id,
            queryLimit,
          )
          .all<RideMessageRow>();

    const hasMore = result.results.length > limit;
    const newestFirst = result.results.slice(0, limit);
    const oldestInPage = newestFirst.at(-1);

    return {
      messages: newestFirst.map(mapMessage).reverse(),
      nextCursor:
        hasMore && oldestInPage != null
          ? {
              createdAt: oldestInPage.created_at,
              id: oldestInPage.id,
            }
          : null,
    };
  }
}

function mapMessage(row: RideMessageRow): RideMessage {
  return {
    id: row.id,
    rideId: row.ride_id,
    senderRiderId: row.sender_rider_id,
    senderDisplayName: row.sender_display_name,
    senderRideRole: row.sender_ride_role,
    kind: row.kind,
    body: row.body,
    clientMessageId: row.client_message_id,
    createdAt: row.created_at,
  };
}
