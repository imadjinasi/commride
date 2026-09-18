import type { RideMembershipStatus, RideRole } from '../clubs-rides/models';
import type { CheckpointType } from '../route-plans/models';

export type RideCheckpointState = 'current' | 'upcoming' | 'released';

export interface CheckpointParticipant {
  readonly riderId: string;
  readonly displayName: string;
  readonly role: RideRole;
  readonly membershipStatus: RideMembershipStatus;
  readonly checkedInAt: string | null;
}

export interface CheckpointRelease {
  readonly checkpointId: string;
  readonly releasedByRiderId: string;
  readonly releasedAt: string;
}

export interface CheckpointCheckIn {
  readonly checkpointId: string;
  readonly riderId: string;
  readonly checkedInAt: string;
  readonly method: 'manual';
}

export interface RideCheckpointItem {
  readonly checkpointId: string;
  readonly sequence: number;
  readonly label: string;
  readonly formattedAddress: string | null;
  readonly latitude: number;
  readonly longitude: number;
  readonly checkpointType: CheckpointType;
  readonly plannedDurationMinutes: number | null;
  readonly state: RideCheckpointState;
  readonly expectedCount: number;
  readonly checkedInCount: number;
  readonly missingCount: number;
  readonly currentRiderCheckedIn: boolean;
  readonly releasedAt: string | null;
  readonly participants: readonly CheckpointParticipant[];
}

export interface RideCheckpointView {
  readonly rideId: string;
  readonly routePlanId: string;
  readonly routePlanRevision: number;
  readonly checkpoints: readonly RideCheckpointItem[];
}
