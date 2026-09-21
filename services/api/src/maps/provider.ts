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

export interface RoutePlaceProvider {
  autocomplete(
    input: PlaceAutocompleteInput,
  ): Promise<readonly PlaceSuggestion[]>;

  resolvePlace(input: ResolvePlaceInput): Promise<ResolvedPlace>;

  computeRoutes(
    input: ComputeRoutesInput,
  ): Promise<readonly RouteOption[]>;

  searchAlongRoute(
    input: SearchAlongRouteInput,
  ): Promise<readonly AlongRoutePlace[]>;
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
