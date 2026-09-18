import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from './rider-profile';

export interface RiderRepository {
  findByAuthSubject(authSubject: string): Promise<RiderProfile | null>;

  upsertProfile(input: UpsertRiderProfileInput): Promise<RiderProfile>;
}

interface RiderRow {
  readonly id: string;
  readonly auth_subject: string;
  readonly display_name: string;
  readonly callsign: string | null;
  readonly home_area: string | null;
  readonly created_at: string;
  readonly updated_at: string;
}

export class D1RiderRepository implements RiderRepository {
  constructor(private readonly database: D1Database) {}

  async findByAuthSubject(authSubject: string): Promise<RiderProfile | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          id,
          auth_subject,
          display_name,
          callsign,
          home_area,
          created_at,
          updated_at
        FROM riders
        WHERE auth_subject = ?
        LIMIT 1
        `,
      )
      .bind(authSubject)
      .first<RiderRow>();

    return row == null ? null : mapRiderRow(row);
  }

  async upsertProfile(
    input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    await this.database
      .prepare(
        `
        INSERT INTO riders(
          id,
          auth_subject,
          display_name,
          callsign,
          home_area
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(auth_subject) DO UPDATE SET
          display_name = excluded.display_name,
          callsign = excluded.callsign,
          home_area = excluded.home_area,
          updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        `,
      )
      .bind(
        input.newRiderId,
        input.authSubject,
        input.displayName,
        input.callsign,
        input.homeArea,
      )
      .run();

    const profile = await this.findByAuthSubject(input.authSubject);
    if (profile == null) {
      throw new Error('Rider profile was not persisted.');
    }

    return profile;
  }
}

function mapRiderRow(row: RiderRow): RiderProfile {
  return {
    id: row.id,
    authSubject: row.auth_subject,
    displayName: row.display_name,
    callsign: row.callsign,
    homeArea: row.home_area,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
