export interface GeoPoint {
  readonly latitude: number;
  readonly longitude: number;
}

export type RouteTravelMode = 'drive' | 'two_wheeler';

export interface RouteModifiers {
  readonly avoidTolls: boolean;
  readonly avoidHighways: boolean;
  readonly avoidFerries: boolean;
}

export interface PlaceSuggestion {
  /**
   * Opaque provider reference. Clients may pass it back to resolvePlace(), but
   * must not persist it as the route's geographic source of truth.
   */
  readonly reference: string;
  readonly text: string;
}

export interface ResolvedPlace {
  readonly reference: string;
  readonly formattedAddress: string | null;
  readonly location: GeoPoint;
}

export interface RouteWaypoint {
  readonly location: GeoPoint;
  readonly via: boolean;
}

export interface ComputeRoutesInput {
  readonly origin: GeoPoint;
  readonly destination: GeoPoint;
  readonly intermediates: readonly RouteWaypoint[];
  readonly travelMode: RouteTravelMode;
  readonly computeAlternatives: boolean;
  readonly modifiers: RouteModifiers;
}

export interface RouteLeg {
  readonly distanceMeters: number;
  readonly durationSeconds: number;
}

export interface RouteManeuver {
  readonly instruction: string;
  readonly type: string | null;
  readonly distanceMeters: number;
  readonly durationSeconds: number;
  readonly beginShapeIndex: number;
  readonly endShapeIndex: number;
  readonly verbalPreTransitionInstruction: string | null;
  readonly verbalTransitionInstruction: string | null;
  readonly verbalPostTransitionInstruction: string | null;
}

export interface RouteOption {
  readonly routeIndex: number;
  readonly labels: readonly string[];
  readonly distanceMeters: number;
  readonly durationSeconds: number;
  readonly encodedPolyline: string;
  /**
   * Short-lived opaque provider token that can reproduce the computed route
   * in a compatible embedded navigation SDK. It is transport-only and is not
   * persisted as RoutePlan source of truth.
   */
  readonly routeToken?: string | null;
  readonly legs: readonly RouteLeg[];
  /**
   * Provider-normalized turn-by-turn narrative. Missing/empty is honest:
   * clients may render the route but must not fabricate guidance.
   */
  readonly maneuvers?: readonly RouteManeuver[];
}

export interface SearchAlongRouteInput {
  readonly textQuery: string;
  readonly encodedPolyline: string;
  readonly travelMode: RouteTravelMode;
  readonly modifiers: RouteModifiers;
  readonly maxResults: number;
}

export interface AlongRoutePlace {
  readonly reference: string;
  readonly displayName: string;
  readonly formattedAddress: string | null;
  readonly location: GeoPoint | null;
  /**
   * Actual provider-computed route-via-place totals when available; otherwise
   * null. Geographic corridor proximity must never be presented as a detour.
   */
  readonly viaPlaceDistanceMeters: number | null;
  readonly viaPlaceDurationSeconds: number | null;
}


export interface TrafficIncidentInput {
  readonly encodedPolyline: string;
  readonly maxResults: number;
}

export interface TrafficIncident {
  readonly id: string;
  readonly category: string;
  readonly magnitudeOfDelay: string | null;
  readonly description: string | null;
  readonly from: string | null;
  readonly to: string | null;
  readonly delaySeconds: number | null;
  readonly lengthMeters: number | null;
  readonly startTime: string | null;
  readonly endTime: string | null;
  readonly probabilityOfOccurrence: string | null;
  readonly numberOfReports: number | null;
  readonly lastReportTime: string | null;
  readonly points: readonly GeoPoint[];
}
