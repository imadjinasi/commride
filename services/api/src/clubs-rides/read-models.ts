import type {
  Club,
  ClubMembership,
  Ride,
  RideMembership,
} from './models';

export interface ClubListItem {
  readonly club: Club;
  readonly membership: ClubMembership;
}

export interface RideListItem {
  readonly ride: Ride;
  readonly membership: RideMembership | null;
}
