import type {
  AlongRoutePlace,
  ComputeRoutesInput,
  GeoPoint,
  PlaceSuggestion,
  ResolvedPlace,
  RouteOption,
  SearchAlongRouteInput,
} from './models';

export interface SearchArea {
  readonly south: number;
  readonly west: number;
  readonly north: number;
  readonly east: number;
}

export interface PlaceAutocompleteInput {
  readonly input: string;
  readonly sessionToken?: string;
  /** Prefer results near this point (usually the map center). */
  readonly near?: GeoPoint;
  /** Only return results inside this area ("cari di area ini"). */
  readonly area?: SearchArea;
}

export interface ResolvePlaceInput {
  readonly reference: string;
  readonly sessionToken?: string;
}

export interface PlaceProvider {
  autocomplete(
    input: PlaceAutocompleteInput,
  ): Promise<readonly PlaceSuggestion[]>;

  resolvePlace(input: ResolvePlaceInput): Promise<ResolvedPlace>;

  /**
   * Describes a point picked on the map. The returned location is the picked
   * point itself; only the address text comes from the provider.
   */
  reverseGeocode(location: GeoPoint): Promise<ResolvedPlace>;

  searchAlongRoute(
    input: SearchAlongRouteInput,
  ): Promise<readonly AlongRoutePlace[]>;
}

export interface RouteProvider {
  computeRoutes(
    input: ComputeRoutesInput,
  ): Promise<readonly RouteOption[]>;
}

export interface RoutePlaceProvider extends PlaceProvider, RouteProvider {}

export class CompositeRoutePlaceProvider implements RoutePlaceProvider {
  constructor(
    private readonly places: PlaceProvider,
    private readonly routes: RouteProvider,
  ) {}

  autocomplete(input: PlaceAutocompleteInput) {
    return this.places.autocomplete(input);
  }

  resolvePlace(input: ResolvePlaceInput) {
    return this.places.resolvePlace(input);
  }

  reverseGeocode(location: GeoPoint) {
    return this.places.reverseGeocode(location);
  }

  computeRoutes(input: ComputeRoutesInput) {
    return this.routes.computeRoutes(input);
  }

  searchAlongRoute(input: SearchAlongRouteInput) {
    return this.places.searchAlongRoute(input);
  }
}

export class RoutePlaceProviderError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = 'RoutePlaceProviderError';
  }
}
