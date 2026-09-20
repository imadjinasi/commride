import type { RoutePlan } from '../route-plans/models';

export interface BriefingRoleIdentity {
  readonly riderId: string;
  readonly displayName: string;
}

export interface BriefingRoleSnapshot {
  readonly leader: BriefingRoleIdentity;
  readonly sweeper: BriefingRoleIdentity | null;
}

export interface RideBriefing {
  readonly id: string;
  readonly rideId: string;
  readonly revision: number;
  readonly routePlanId: string;
  readonly createdByRiderId: string;
  readonly scheduledStartAt: string | null;
  readonly leader: BriefingRoleIdentity;
  readonly sweeper: BriefingRoleIdentity | null;
  readonly notes: string | null;
  readonly isCurrent: boolean;
  readonly publishedAt: string;
}

export interface PublishRideBriefingInput {
  readonly id: string;
  readonly rideId: string;
  readonly routePlanId: string;
  readonly createdByRiderId: string;
  readonly scheduledStartAt: string | null;
  readonly roles: BriefingRoleSnapshot;
  readonly notes: string | null;
  readonly publishedAt: string;
}

export interface BriefingReadiness {
  readonly expectedCount: number;
  readonly readyCount: number;
  readonly currentRiderAcknowledged: boolean;
}

export interface RideBriefingView {
  readonly briefing: RideBriefing;
  readonly routePlan: RoutePlan;
  readonly readiness: BriefingReadiness;
  readonly routePlanIsCurrent: boolean;
}
