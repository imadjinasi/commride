import type {
  CreateRideSosInput,
  RideSos,
  RideSosState,
  TrustedRidePresenceSnapshot,
} from './models';

export interface RideSosRepository {
  findByClientCommandId(
    rideId: string,
    riderId: string,
    clientCommandId: string,
  ): Promise<RideSos | null>;

  findById(rideId: string, sosId: string): Promise<RideSos | null>;

  create(input: CreateRideSosInput): Promise<RideSos>;

  list(rideId: string): Promise<readonly RideSos[]>;

  hasActiveForRide(rideId: string): Promise<boolean>;

  cancel(
    rideId: string,
    sosId: string,
    cancelledAt: string,
  ): Promise<RideSos | null>;

  resolve(
    rideId: string,
    sosId: string,
    resolvedAt: string,
    resolvedByRiderId: string,
  ): Promise<RideSos | null>;
}

interface RideSosRow {
  readonly id: string;
  readonly ride_id: string;
  readonly rider_id: string;
  readonly rider_display_name: string;
  readonly rider_ride_role: RideSos['riderRideRole'];
  readonly state: RideSosState;
  readonly client_command_id: string;
  readonly reason: string | null;
  readonly raised_at: string;
  readonly cancelled_at: string | null;
  readonly resolved_at: string | null;
  readonly resolved_by_rider_id: string | null;
  readonly presence_latitude: number | null;
  readonly presence_longitude: number | null;
  readonly presence_observed_at: string | null;
  readonly presence_received_at: string | null;
  readonly presence_freshness: TrustedRidePresenceSnapshot['freshness'] | null;
  readonly presence_movement: TrustedRidePresenceSnapshot['movement'] | null;
}

const SELECT_COLUMNS = `
  id,
  ride_id,
  rider_id,
  rider_display_name,
  rider_ride_role,
  state,
  client_command_id,
  reason,
  raised_at,
  cancelled_at,
  resolved_at,
  resolved_by_rider_id,
  presence_latitude,
  presence_longitude,
  presence_observed_at,
  presence_received_at,
  presence_freshness,
  presence_movement
`;

export class D1RideSosRepository implements RideSosRepository {
  constructor(private readonly database: D1Database) {}

  async findByClientCommandId(
    rideId: string,
    riderId: string,
    clientCommandId: string,
  ): Promise<RideSos | null> {
    const row = await this.database
      .prepare(
        `
        SELECT ${SELECT_COLUMNS}
        FROM ride_sos
        WHERE ride_id = ? AND rider_id = ? AND client_command_id = ?
        LIMIT 1
        `,
      )
      .bind(rideId, riderId, clientCommandId)
      .first<RideSosRow>();

    return row == null ? null : mapRideSos(row);
  }

  async findById(rideId: string, sosId: string): Promise<RideSos | null> {
    const row = await this.database
      .prepare(
        `
        SELECT ${SELECT_COLUMNS}
        FROM ride_sos
        WHERE ride_id = ? AND id = ?
        LIMIT 1
        `,
      )
      .bind(rideId, sosId)
      .first<RideSosRow>();

    return row == null ? null : mapRideSos(row);
  }

  async create(input: CreateRideSosInput): Promise<RideSos> {
    const presence = input.presence;

    await this.database
      .prepare(
        `
        INSERT INTO ride_sos(
          id,
          ride_id,
          rider_id,
          rider_display_name,
          rider_ride_role,
          state,
          client_command_id,
          reason,
          raised_at,
          cancelled_at,
          resolved_at,
          resolved_by_rider_id,
          presence_latitude,
          presence_longitude,
          presence_observed_at,
          presence_received_at,
          presence_freshness,
          presence_movement
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(ride_id, rider_id, client_command_id) DO NOTHING
        `,
      )
      .bind(
        input.id,
        input.rideId,
        input.riderId,
        input.riderDisplayName,
        input.riderRideRole,
        input.state,
        input.clientCommandId,
        input.reason,
        input.raisedAt,
        input.cancelledAt,
        input.resolvedAt,
        input.resolvedByRiderId,
        presence?.latitude ?? null,
        presence?.longitude ?? null,
        presence?.observedAt ?? null,
        presence?.receivedAt ?? null,
        presence?.freshness ?? null,
        presence?.movement ?? null,
      )
      .run();

    const persisted = await this.findByClientCommandId(
      input.rideId,
      input.riderId,
      input.clientCommandId,
    );
    if (persisted == null) {
      throw new Error('Ride SOS was not persisted.');
    }

    return persisted;
  }

  async list(rideId: string): Promise<readonly RideSos[]> {
    const rows = await this.database
      .prepare(
        `
        SELECT ${SELECT_COLUMNS}
        FROM ride_sos
        WHERE ride_id = ?
        ORDER BY raised_at DESC, id DESC
        `,
      )
      .bind(rideId)
      .all<RideSosRow>();

    return rows.results.map(mapRideSos);
  }

  async hasActiveForRide(rideId: string): Promise<boolean> {
    const row = await this.database
      .prepare(
        `
        SELECT 1 AS present
        FROM ride_sos
        WHERE ride_id = ? AND state = 'active'
        LIMIT 1
        `,
      )
      .bind(rideId)
      .first<{ present: number }>();

    return row != null;
  }

  async cancel(
    rideId: string,
    sosId: string,
    cancelledAt: string,
  ): Promise<RideSos | null> {
    await this.database
      .prepare(
        `
        UPDATE ride_sos
        SET state = 'cancelled', cancelled_at = ?
        WHERE ride_id = ? AND id = ? AND state = 'active'
        `,
      )
      .bind(cancelledAt, rideId, sosId)
      .run();

    return this.findById(rideId, sosId);
  }

  async resolve(
    rideId: string,
    sosId: string,
    resolvedAt: string,
    resolvedByRiderId: string,
  ): Promise<RideSos | null> {
    await this.database
      .prepare(
        `
        UPDATE ride_sos
        SET
          state = 'resolved',
          resolved_at = ?,
          resolved_by_rider_id = ?
        WHERE ride_id = ? AND id = ? AND state = 'active'
        `,
      )
      .bind(resolvedAt, resolvedByRiderId, rideId, sosId)
      .run();

    return this.findById(rideId, sosId);
  }
}

function mapRideSos(row: RideSosRow): RideSos {
  const hasPresence =
    row.presence_latitude != null &&
    row.presence_longitude != null &&
    row.presence_observed_at != null &&
    row.presence_received_at != null &&
    row.presence_freshness != null &&
    row.presence_movement != null;

  return {
    id: row.id,
    rideId: row.ride_id,
    riderId: row.rider_id,
    riderDisplayName: row.rider_display_name,
    riderRideRole: row.rider_ride_role,
    state: row.state,
    clientCommandId: row.client_command_id,
    reason: row.reason,
    raisedAt: row.raised_at,
    cancelledAt: row.cancelled_at,
    resolvedAt: row.resolved_at,
    resolvedByRiderId: row.resolved_by_rider_id,
    presence: hasPresence
      ? {
          latitude: row.presence_latitude!,
          longitude: row.presence_longitude!,
          observedAt: row.presence_observed_at!,
          receivedAt: row.presence_received_at!,
          freshness: row.presence_freshness!,
          movement: row.presence_movement!,
        }
      : null,
  };
}
