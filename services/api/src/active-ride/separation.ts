import type { RideRole } from '../clubs-rides/models';
import {
  presenceView,
  type StoredPresence,
} from './protocol';

export interface ConvoySeparationPolicy {
  readonly continuityDistanceMeters: number;
  readonly splitConfirmationMs: number;
  readonly recoveryConfirmationMs: number;
  readonly minimumEligibleRiders: number;
}

export const DEFAULT_CONVOY_SEPARATION_POLICY: ConvoySeparationPolicy = {
  continuityDistanceMeters: 600,
  splitConfirmationMs: 20_000,
  recoveryConfirmationMs: 15_000,
  minimumEligibleRiders: 2,
};

export type ConvoySeparationPhase =
  | 'insufficient_data'
  | 'normal'
  | 'split_candidate'
  | 'separated_attention';

export interface ConvoySeparationState {
  readonly phase: ConvoySeparationPhase;
  readonly dataSufficient: boolean;
  readonly components: readonly (readonly string[])[];
  readonly isolatedRiderIds: readonly string[];
  readonly sweeperComponentRiderIds: readonly string[] | null;
  readonly firstSplitObservedAt: string | null;
  readonly confirmedAt: string | null;
  readonly recoveryObservedAt: string | null;
  readonly lastUpdatedAt: string;
}

interface EligiblePresence {
  readonly riderId: string;
  readonly role: RideRole;
  readonly latitude: number;
  readonly longitude: number;
  readonly observedAt: string;
}

export function evaluateConvoySeparation(
  previous: ConvoySeparationState | null,
  presences: readonly StoredPresence[],
  now: Date,
  policy: ConvoySeparationPolicy = DEFAULT_CONVOY_SEPARATION_POLICY,
): ConvoySeparationState {
  validatePolicy(policy);

  const nowIso = now.toISOString();
  const eligible = eligiblePresences(presences, now);
  if (eligible.length < policy.minimumEligibleRiders) {
    if (previous?.phase === 'separated_attention') {
      return {
        ...previous,
        dataSufficient: false,
        recoveryObservedAt: null,
        lastUpdatedAt: nowIso,
      };
    }

    return {
      phase: 'insufficient_data',
      dataSufficient: false,
      components: eligible.map((presence) => [presence.riderId]),
      isolatedRiderIds: eligible.map((presence) => presence.riderId),
      sweeperComponentRiderIds: sweeperComponent(
        eligible,
        eligible.map((presence) => [presence.riderId]),
      ),
      firstSplitObservedAt: null,
      confirmedAt: null,
      recoveryObservedAt: null,
      lastUpdatedAt: nowIso,
    };
  }

  const components = buildComponents(
    eligible,
    policy.continuityDistanceMeters,
  );
  const isolatedRiderIds = components
    .filter((component) => component.length === 1)
    .map((component) => component[0]);
  const sweeper = sweeperComponent(eligible, components);
  const isSplit = components.length > 1;

  if (isSplit) {
    if (previous?.phase === 'separated_attention') {
      return {
        phase: 'separated_attention',
        dataSufficient: true,
        components,
        isolatedRiderIds,
        sweeperComponentRiderIds: sweeper,
        firstSplitObservedAt:
          previous.firstSplitObservedAt ?? nowIso,
        confirmedAt: previous.confirmedAt ?? nowIso,
        recoveryObservedAt: null,
        lastUpdatedAt: nowIso,
      };
    }

    if (
      previous?.phase === 'split_candidate' &&
      previous.firstSplitObservedAt != null
    ) {
      const candidateAge =
        now.valueOf() - Date.parse(previous.firstSplitObservedAt);
      if (candidateAge >= policy.splitConfirmationMs) {
        return {
          phase: 'separated_attention',
          dataSufficient: true,
          components,
          isolatedRiderIds,
          sweeperComponentRiderIds: sweeper,
          firstSplitObservedAt: previous.firstSplitObservedAt,
          confirmedAt: nowIso,
          recoveryObservedAt: null,
          lastUpdatedAt: nowIso,
        };
      }

      return {
        phase: 'split_candidate',
        dataSufficient: true,
        components,
        isolatedRiderIds,
        sweeperComponentRiderIds: sweeper,
        firstSplitObservedAt: previous.firstSplitObservedAt,
        confirmedAt: null,
        recoveryObservedAt: null,
        lastUpdatedAt: nowIso,
      };
    }

    return {
      phase: 'split_candidate',
      dataSufficient: true,
      components,
      isolatedRiderIds,
      sweeperComponentRiderIds: sweeper,
      firstSplitObservedAt: nowIso,
      confirmedAt: null,
      recoveryObservedAt: null,
      lastUpdatedAt: nowIso,
    };
  }

  if (previous?.phase === 'separated_attention') {
    const recoveryObservedAt =
      previous.recoveryObservedAt ?? nowIso;
    const recoveryAge =
      now.valueOf() - Date.parse(recoveryObservedAt);

    if (recoveryAge < policy.recoveryConfirmationMs) {
      return {
        phase: 'separated_attention',
        dataSufficient: true,
        components,
        isolatedRiderIds,
        sweeperComponentRiderIds: sweeper,
        firstSplitObservedAt: previous.firstSplitObservedAt,
        confirmedAt: previous.confirmedAt,
        recoveryObservedAt,
        lastUpdatedAt: nowIso,
      };
    }
  }

  return {
    phase: 'normal',
    dataSufficient: true,
    components,
    isolatedRiderIds,
    sweeperComponentRiderIds: sweeper,
    firstSplitObservedAt: null,
    confirmedAt: null,
    recoveryObservedAt: null,
    lastUpdatedAt: nowIso,
  };
}

export function haversineDistanceMeters(
  a: Pick<StoredPresence, 'latitude' | 'longitude'>,
  b: Pick<StoredPresence, 'latitude' | 'longitude'>,
): number {
  const earthRadiusMeters = 6_371_000;
  const latitude1 = degreesToRadians(a.latitude);
  const latitude2 = degreesToRadians(b.latitude);
  const deltaLatitude = degreesToRadians(b.latitude - a.latitude);
  const deltaLongitude = degreesToRadians(b.longitude - a.longitude);

  const haversine =
    Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(latitude1) *
      Math.cos(latitude2) *
      Math.sin(deltaLongitude / 2) ** 2;
  const centralAngle =
    2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));

  return earthRadiusMeters * centralAngle;
}

function eligiblePresences(
  presences: readonly StoredPresence[],
  now: Date,
): EligiblePresence[] {
  const latestByRider = new Map<string, StoredPresence>();

  for (const presence of presences) {
    const existing = latestByRider.get(presence.riderId);
    if (
      existing == null ||
      Date.parse(presence.observedAt) >
        Date.parse(existing.observedAt)
    ) {
      latestByRider.set(presence.riderId, presence);
    }
  }

  return [...latestByRider.values()]
    .filter(
      (presence) =>
        presence.connected &&
        presenceView(presence, now).freshness === 'live',
    )
    .map((presence) => ({
      riderId: presence.riderId,
      role: presence.role,
      latitude: presence.latitude,
      longitude: presence.longitude,
      observedAt: presence.observedAt,
    }))
    .sort((a, b) => a.riderId.localeCompare(b.riderId));
}

function buildComponents(
  presences: readonly EligiblePresence[],
  thresholdMeters: number,
): readonly (readonly string[])[] {
  const adjacency = new Map<string, Set<string>>();
  for (const presence of presences) {
    adjacency.set(presence.riderId, new Set<string>());
  }

  for (let left = 0; left < presences.length; left += 1) {
    for (let right = left + 1; right < presences.length; right += 1) {
      const a = presences[left];
      const b = presences[right];
      if (haversineDistanceMeters(a, b) <= thresholdMeters) {
        adjacency.get(a.riderId)?.add(b.riderId);
        adjacency.get(b.riderId)?.add(a.riderId);
      }
    }
  }

  const visited = new Set<string>();
  const components: string[][] = [];

  for (const presence of presences) {
    if (visited.has(presence.riderId)) {
      continue;
    }

    const stack = [presence.riderId];
    const component: string[] = [];
    visited.add(presence.riderId);

    while (stack.length > 0) {
      const riderId = stack.pop();
      if (riderId == null) {
        continue;
      }
      component.push(riderId);

      const neighbors = [...(adjacency.get(riderId) ?? [])].sort();
      for (const neighbor of neighbors) {
        if (!visited.has(neighbor)) {
          visited.add(neighbor);
          stack.push(neighbor);
        }
      }
    }

    component.sort();
    components.push(component);
  }

  components.sort((a, b) => a[0].localeCompare(b[0]));
  return components;
}

function sweeperComponent(
  presences: readonly EligiblePresence[],
  components: readonly (readonly string[])[],
): readonly string[] | null {
  const sweeper = presences.find((presence) => presence.role === 'sweeper');
  if (sweeper == null) {
    return null;
  }

  return components.find(
    (component) => component.includes(sweeper.riderId),
  ) ?? null;
}

function validatePolicy(policy: ConvoySeparationPolicy): void {
  if (
    !Number.isFinite(policy.continuityDistanceMeters) ||
    policy.continuityDistanceMeters <= 0 ||
    !Number.isFinite(policy.splitConfirmationMs) ||
    policy.splitConfirmationMs < 0 ||
    !Number.isFinite(policy.recoveryConfirmationMs) ||
    policy.recoveryConfirmationMs < 0 ||
    !Number.isInteger(policy.minimumEligibleRiders) ||
    policy.minimumEligibleRiders < 2
  ) {
    throw new Error('Invalid convoy separation policy.');
  }
}

function degreesToRadians(value: number): number {
  return value * Math.PI / 180;
}
