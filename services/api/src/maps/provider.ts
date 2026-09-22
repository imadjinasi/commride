import type {
  AlongRoutePlace,
  ComputeRoutesInput,
  PlaceSuggestion,
  ResolvedPlace,
  RouteOption,
  SearchAlongRouteInput,
} from './models';

export interface PlaceAutocompleteInput {
  readonly input: string;
  readonly sessionToken?: string;
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
