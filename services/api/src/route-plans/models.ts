import type {
  GeoPoint,
  RouteManeuver,
  RouteTravelMode,
} from '../maps/models';

export type StopType =
  | 'generic'
  | 'fuel'
  | 'rest'
  | 'meal'
  | 'hotel'
  | 'custom';

export type CheckpointType =
  | 'stop'
  | 'fuel'
  | 'rest'
  | 'meal'
  | 'regroup'
  | 'mandatory_regroup'
  | 'hotel'
  | 'custom'
  | 'finish';

export interface RouteStop {
  readonly id: string;
  readonly sequence: number;
  readonly label: string;
  readonly formattedAddress: string | null;
  readonly location: GeoPoint;
  readonly stopType: StopType;
  readonly checkpointType: CheckpointType | null;
  readonly plannedDurationMinutes: number | null;
}

export interface RoutePlan {
  readonly id: string;
  readonly rideId: string;
  readonly revision: number;
  readonly createdByRiderId: string;
  readonly travelMode: RouteTravelMode;
  readonly originLabel: string | null;
  readonly origin: GeoPoint;
  readonly destinationLabel: string | null;
  readonly destination: GeoPoint;
  readonly distanceMeters: number;
  readonly durationSeconds: number;
  readonly encodedPolyline: string;
  readonly maneuvers: readonly RouteManeuver[];
  readonly isCurrent: boolean;
  readonly createdAt: string;
  readonly stops: readonly RouteStop[];
}

export interface SaveRouteStopInput {
  readonly id: string;
  readonly sequence: number;
  readonly label: string;
  readonly formattedAddress: string | null;
  readonly location: GeoPoint;
  readonly stopType: StopType;
  readonly checkpointType: CheckpointType | null;
  readonly plannedDurationMinutes: number | null;
}

export interface SaveRoutePlanInput {
  readonly id: string;
  readonly rideId: string;
  readonly createdByRiderId: string;
  readonly travelMode: RouteTravelMode;
  readonly originLabel: string | null;
  readonly origin: GeoPoint;
  readonly destinationLabel: string | null;
  readonly destination: GeoPoint;
  readonly distanceMeters: number;
  readonly durationSeconds: number;
  readonly encodedPolyline: string;
  readonly maneuvers?: readonly RouteManeuver[];
  readonly stops: readonly SaveRouteStopInput[];
}
