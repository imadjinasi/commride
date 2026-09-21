import type {
  Club,
  ClubMembership,
  ClubRole,
  Ride,
  RideMembership,
  RideRole,
  RideStatus,
} from './models';

export interface CreateClubInput {
  readonly clubId: string;
  readonly creatorRiderId: string;
  readonly name: string;
  readonly slug: string;
  readonly homeArea: string | null;
  readonly visibility: 'private' | 'unlisted' | 'public';
}

export interface CreateRideInput {
  readonly rideId: string;
  readonly clubId: string;
  readonly creatorRiderId: string;
  readonly title: string;
  readonly scheduledStartAt: string | null;
  readonly notes: string | null;
}

export interface ClubRideRepository {
  createClubWithOwner(input: CreateClubInput): Promise<Club>;

  findClubMembership(
    clubId: string,
    riderId: string,
  ): Promise<ClubMembership | null>;

  inviteClubMember(
    clubId: string,
    riderId: string,
    role: Exclude<ClubRole, 'owner'>,
  ): Promise<ClubMembership>;

  acceptClubInvite(
    clubId: string,
    riderId: string,
  ): Promise<ClubMembership | null>;

  createRideWithLeader(input: CreateRideInput): Promise<Ride>;

  findRide(rideId: string): Promise<Ride | null>;

  findRideMembership(
    rideId: string,
    riderId: string,
  ): Promise<RideMembership | null>;

  inviteRideMember(
    rideId: string,
    riderId: string,
    role: Exclude<RideRole, 'leader'>,
  ): Promise<RideMembership>;

  acceptRideInvite(
    rideId: string,
    riderId: string,
  ): Promise<RideMembership | null>;

  transitionRideStatus(
    rideId: string,
    expectedStatus: RideStatus,
    nextStatus: RideStatus,
    timestamp: string,
  ): Promise<Ride | null>;
}

interface ClubRow {
  readonly id: string;
  readonly created_by_rider_id: string;
  readonly name: string;
  readonly slug: string;
  readonly home_area: string | null;
  readonly description: string | null;
  readonly visibility: 'private' | 'unlisted' | 'public';
  readonly created_at: string;
  readonly updated_at: string;
}

interface ClubMembershipRow {
  readonly club_id: string;
  readonly rider_id: string;
  readonly role: ClubRole;
  readonly status: 'invited' | 'active' | 'left';
}

interface RideRow {
  readonly id: string;
  readonly club_id: string;
  readonly created_by_rider_id: string;
  readonly title: string;
  readonly status: RideStatus;
  readonly scheduled_start_at: string | null;
  readonly actual_start_at: string | null;
  readonly ended_at: string | null;
  readonly notes: string | null;
  readonly created_at: string;
  readonly updated_at: string;
}

interface RideMembershipRow {
  readonly ride_id: string;
  readonly rider_id: string;
  readonly role: RideRole;
  readonly status:
    | 'invited'
    | 'joined'
    | 'ready'
    | 'active'
    | 'finished'
    | 'left';
}

export class D1ClubRideRepository implements ClubRideRepository {
  constructor(private readonly database: D1Database) {}

  async createClubWithOwner(input: CreateClubInput): Promise<Club> {
    await this.database.batch([
      this.database
        .prepare(
          `
          INSERT INTO clubs(
            id,
            created_by_rider_id,
            name,
            slug,
            home_area,
            visibility
          ) VALUES (?, ?, ?, ?, ?, ?)
          `,
        )
        .bind(
          input.clubId,
          input.creatorRiderId,
          input.name,
          input.slug,
          input.homeArea,
          input.visibility,
        ),
      this.database
        .prepare(
          `
          INSERT INTO club_memberships(
            club_id,
            rider_id,
            role,
            status,
            joined_at
          ) VALUES (?, ?, 'owner', 'active', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
          `,
        )
        .bind(input.clubId, input.creatorRiderId),
    ]);

    const club = await this.findClub(input.clubId);
    if (club == null) {
      throw new Error('Club was not persisted.');
    }

    return club;
  }

  async findClubMembership(
    clubId: string,
    riderId: string,
  ): Promise<ClubMembership | null> {
    const row = await this.database
      .prepare(
        `
        SELECT club_id, rider_id, role, status
        FROM club_memberships
        WHERE club_id = ? AND rider_id = ?
        LIMIT 1
        `,
      )
      .bind(clubId, riderId)
      .first<ClubMembershipRow>();

    return row == null ? null : mapClubMembership(row);
  }

  async inviteClubMember(
    clubId: string,
    riderId: string,
    role: Exclude<ClubRole, 'owner'>,
  ): Promise<ClubMembership> {
    await this.database
      .prepare(
        `
        INSERT INTO club_memberships(
          club_id,
          rider_id,
          role,
          status,
          invited_at,
          joined_at,
          left_at
        ) VALUES (?, ?, ?, 'invited', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), NULL, NULL)
        ON CONFLICT(club_id, rider_id) DO UPDATE SET
          role = excluded.role,
          status = 'invited',
          invited_at = excluded.invited_at,
          joined_at = NULL,
          left_at = NULL
        WHERE club_memberships.status IN ('invited', 'left')
        `,
      )
      .bind(clubId, riderId, role)
      .run();

    const membership = await this.findClubMembership(clubId, riderId);
    if (membership == null) {
      throw new Error('Club invitation was not persisted.');
    }

    return membership;
  }

  async acceptClubInvite(
    clubId: string,
    riderId: string,
  ): Promise<ClubMembership | null> {
    await this.database
      .prepare(
        `
        UPDATE club_memberships
        SET
          status = 'active',
          joined_at = COALESCE(joined_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
          left_at = NULL
        WHERE club_id = ? AND rider_id = ? AND status = 'invited'
        `,
      )
      .bind(clubId, riderId)
      .run();

    return this.findClubMembership(clubId, riderId);
  }

  async createRideWithLeader(input: CreateRideInput): Promise<Ride> {
    await this.database.batch([
      this.database
        .prepare(
          `
          INSERT INTO rides(
            id,
            club_id,
            created_by_rider_id,
            title,
            scheduled_start_at,
            notes
          ) VALUES (?, ?, ?, ?, ?, ?)
          `,
        )
        .bind(
          input.rideId,
          input.clubId,
          input.creatorRiderId,
          input.title,
          input.scheduledStartAt,
          input.notes,
        ),
      this.database
        .prepare(
          `
          INSERT INTO ride_memberships(
            ride_id,
            rider_id,
            role,
            status,
            joined_at
          ) VALUES (?, ?, 'leader', 'joined', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
          `,
        )
        .bind(input.rideId, input.creatorRiderId),
    ]);

    const ride = await this.findRide(input.rideId);
    if (ride == null) {
      throw new Error('Ride was not persisted.');
    }

    return ride;
  }

  async findRide(rideId: string): Promise<Ride | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          id,
          club_id,
          created_by_rider_id,
          title,
          status,
          scheduled_start_at,
          actual_start_at,
          ended_at,
          notes,
          created_at,
          updated_at
        FROM rides
        WHERE id = ?
        LIMIT 1
        `,
      )
      .bind(rideId)
      .first<RideRow>();

    return row == null ? null : mapRide(row);
  }

  async findRideMembership(
    rideId: string,
    riderId: string,
  ): Promise<RideMembership | null> {
    const row = await this.database
      .prepare(
        `
        SELECT ride_id, rider_id, role, status
        FROM ride_memberships
        WHERE ride_id = ? AND rider_id = ?
        LIMIT 1
        `,
      )
      .bind(rideId, riderId)
      .first<RideMembershipRow>();

    return row == null ? null : mapRideMembership(row);
  }

  async inviteRideMember(
    rideId: string,
    riderId: string,
    role: Exclude<RideRole, 'leader'>,
  ): Promise<RideMembership> {
    await this.database
      .prepare(
        `
        INSERT INTO ride_memberships(
          ride_id,
          rider_id,
          role,
          status,
          invited_at,
          joined_at
        ) VALUES (?, ?, ?, 'invited', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), NULL)
        ON CONFLICT(ride_id, rider_id) DO UPDATE SET
          role = excluded.role,
          status = 'invited',
          invited_at = excluded.invited_at,
          joined_at = NULL
        WHERE ride_memberships.status IN ('invited', 'left')
        `,
      )
      .bind(rideId, riderId, role)
      .run();

    const membership = await this.findRideMembership(rideId, riderId);
    if (membership == null) {
      throw new Error('Ride invitation was not persisted.');
    }

    return membership;
  }

  async acceptRideInvite(
    rideId: string,
    riderId: string,
  ): Promise<RideMembership | null> {
    await this.database
      .prepare(
        `
        UPDATE ride_memberships
        SET
          status = 'joined',
          joined_at = COALESCE(joined_at, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        WHERE ride_id = ? AND rider_id = ? AND status = 'invited'
        `,
      )
      .bind(rideId, riderId)
      .run();

    return this.findRideMembership(rideId, riderId);
  }

  async transitionRideStatus(
    rideId: string,
    expectedStatus: RideStatus,
    nextStatus: RideStatus,
    timestamp: string,
  ): Promise<Ride | null> {
    const timingAssignment =
      nextStatus === 'active'
        ? ', actual_start_at = COALESCE(actual_start_at, ?)'
        : nextStatus === 'completed'
          ? ', ended_at = COALESCE(ended_at, ?)'
          : '';

    const values: unknown[] = [nextStatus, timestamp];

    let query = `
      UPDATE rides
      SET
        status = ?,
        updated_at = ?
        ${timingAssignment}
      WHERE id = ? AND status = ?
    `;

    if (timingAssignment.length > 0) {
      values.push(timestamp);
    }

    values.push(rideId, expectedStatus);

    await this.database.prepare(query).bind(...values).run();

    return this.findRide(rideId);
  }

  private async findClub(clubId: string): Promise<Club | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          id,
          created_by_rider_id,
          name,
          slug,
          home_area,
          description,
          visibility,
          created_at,
          updated_at
        FROM clubs
        WHERE id = ?
        LIMIT 1
        `,
      )
      .bind(clubId)
      .first<ClubRow>();

    return row == null ? null : mapClub(row);
  }
}

function mapClub(row: ClubRow): Club {
  return {
    id: row.id,
    createdByRiderId: row.created_by_rider_id,
    name: row.name,
    slug: row.slug,
    homeArea: row.home_area,
    description: row.description,
    visibility: row.visibility,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapClubMembership(row: ClubMembershipRow): ClubMembership {
  return {
    clubId: row.club_id,
    riderId: row.rider_id,
    role: row.role,
    status: row.status,
  };
}

function mapRide(row: RideRow): Ride {
  return {
    id: row.id,
    clubId: row.club_id,
    createdByRiderId: row.created_by_rider_id,
    title: row.title,
    status: row.status,
    scheduledStartAt: row.scheduled_start_at,
    actualStartAt: row.actual_start_at,
    endedAt: row.ended_at,
    notes: row.notes,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapRideMembership(row: RideMembershipRow): RideMembership {
  return {
    rideId: row.ride_id,
    riderId: row.rider_id,
    role: row.role,
    status: row.status,
  };
}
