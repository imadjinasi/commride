import type {
  RideMembershipStatus,
  RideRole,
} from '../clubs-rides/models';

export interface RideRecapParticipant {
  readonly riderId: string;
  readonly displayName: string;
  readonly role: RideRole;
  readonly membershipStatus: RideMembershipStatus;
}

export interface RideRecapPlannedRoute {
  readonly routePlanId: string;
  readonly revision: number;
  readonly originLabel: string | null;
  readonly destinationLabel: string | null;
  readonly distanceMeters: number;
  readonly durationSeconds: number;
  readonly stopCount: number;
}

export interface RideRecapJourney {
  readonly sampleCount: number;
  readonly trackedRiderCount: number;
  readonly firstObservedAt: string | null;
  readonly lastObservedAt: string | null;
  readonly leaderTrackedDistanceMeters: number | null;
}

export interface RideRecapCheckpoint {
  readonly checkpointId: string;
  readonly label: string;
  readonly checkpointType: string;
  readonly checkInCount: number;
  readonly participantCount: number;
  readonly releasedAt: string | null;
}

export interface RideRecapIncident {
  readonly sosId: string;
  readonly riderId: string;
  readonly riderDisplayName: string;
  readonly state: 'active' | 'cancelled' | 'resolved';
  readonly reason: string | null;
  readonly raisedAt: string;
  readonly closedAt: string | null;
}

export interface RideRecap {
  readonly rideId: string;
  readonly title: string;
  readonly actualStartAt: string | null;
  readonly endedAt: string | null;
  readonly durationSeconds: number | null;
  readonly participants: readonly RideRecapParticipant[];
  readonly plannedRoute: RideRecapPlannedRoute | null;
  readonly journey: RideRecapJourney;
  readonly checkpoints: readonly RideRecapCheckpoint[];
  readonly incidents: readonly RideRecapIncident[];
  readonly generatedAt: string;
}
