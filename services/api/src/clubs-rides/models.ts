export type ClubRole = 'owner' | 'admin' | 'member';
export type ClubMembershipStatus = 'invited' | 'active' | 'left';

export interface Club {
  readonly id: string;
  readonly createdByRiderId: string;
  readonly name: string;
  readonly slug: string;
  readonly homeArea: string | null;
  readonly description: string | null;
  readonly visibility: 'private' | 'unlisted' | 'public';
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface ClubMembership {
  readonly clubId: string;
  readonly riderId: string;
  readonly role: ClubRole;
  readonly status: ClubMembershipStatus;
}

export type RideRole = 'leader' | 'sweeper' | 'navigator' | 'member';
export type RideMembershipStatus =
  | 'invited'
  | 'joined'
  | 'ready'
  | 'active'
  | 'finished'
  | 'left';

export type RideStatus =
  | 'draft'
  | 'published'
  | 'active'
  | 'completed'
  | 'cancelled';

export interface Ride {
  readonly id: string;
  readonly clubId: string;
  readonly createdByRiderId: string;
  readonly title: string;
  readonly status: RideStatus;
  readonly scheduledStartAt: string | null;
  readonly actualStartAt: string | null;
  readonly endedAt: string | null;
  readonly notes: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface RideMembership {
  readonly rideId: string;
  readonly riderId: string;
  readonly role: RideRole;
  readonly status: RideMembershipStatus;
}
