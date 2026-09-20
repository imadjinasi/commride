import type { RideRole } from '../clubs-rides/models';
import type {
  PresenceFreshness,
  PresenceMovement,
} from '../active-ride/protocol';

export type RideSosState = 'active' | 'cancelled' | 'resolved';

export interface TrustedRidePresenceSnapshot {
  readonly latitude: number;
  readonly longitude: number;
  readonly observedAt: string;
  readonly receivedAt: string;
  readonly freshness: PresenceFreshness;
  readonly movement: PresenceMovement;
}

export interface RideSos {
  readonly id: string;
  readonly rideId: string;
  readonly riderId: string;
  readonly riderDisplayName: string;
  readonly riderRideRole: RideRole;
  readonly state: RideSosState;
  readonly clientCommandId: string;
  readonly reason: string | null;
  readonly raisedAt: string;
  readonly cancelledAt: string | null;
  readonly resolvedAt: string | null;
  readonly resolvedByRiderId: string | null;
  readonly presence: TrustedRidePresenceSnapshot | null;
}

export interface CreateRideSosInput extends RideSos {}
