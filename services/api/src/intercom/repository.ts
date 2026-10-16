export interface IntercomRoomRecord {
  readonly rideId: string;
  readonly provider: 'cloudflare_realtimekit';
  readonly providerRoomId: string;
  readonly createdAt: string;
}

export interface IntercomRoomRepository {
  find(rideId: string): Promise<IntercomRoomRecord | null>;
  /**
   * Stores the room unless another request already did; returns whichever
   * room is now persisted so concurrent first joins end up together.
   */
  insertIfAbsent(record: IntercomRoomRecord): Promise<IntercomRoomRecord>;
}

interface IntercomRoomRow {
  readonly ride_id: string;
  readonly provider: 'cloudflare_realtimekit';
  readonly provider_room_id: string;
  readonly created_at: string;
}

export class D1IntercomRoomRepository implements IntercomRoomRepository {
  constructor(private readonly db: D1Database) {}

  async find(rideId: string): Promise<IntercomRoomRecord | null> {
    const row = await this.db
      .prepare(
        `SELECT ride_id, provider, provider_room_id, created_at
         FROM ride_intercom_rooms WHERE ride_id = ?1`,
      )
      .bind(rideId)
      .first<IntercomRoomRow>();
    return row == null
      ? null
      : {
          rideId: row.ride_id,
          provider: row.provider,
          providerRoomId: row.provider_room_id,
          createdAt: row.created_at,
        };
  }

  async insertIfAbsent(
    record: IntercomRoomRecord,
  ): Promise<IntercomRoomRecord> {
    await this.db
      .prepare(
        `INSERT OR IGNORE INTO ride_intercom_rooms
           (ride_id, provider, provider_room_id, created_at)
         VALUES (?1, ?2, ?3, ?4)`,
      )
      .bind(
        record.rideId,
        record.provider,
        record.providerRoomId,
        record.createdAt,
      )
      .run();
    return (await this.find(record.rideId)) ?? record;
  }
}
