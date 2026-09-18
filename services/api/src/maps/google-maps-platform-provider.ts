import type {
  AlongRoutePlace,
  ComputeRoutesInput,
  GeoPoint,
  PlaceSuggestion,
  ResolvedPlace,
  RouteLeg,
  RouteOption,
  SearchAlongRouteInput,
} from './models';
import {
  type PlaceAutocompleteInput,
  type ResolvePlaceInput,
  type RoutePlaceProvider,
  RoutePlaceProviderError,
} from './provider';

const PLACES_BASE_URL = 'https://places.googleapis.com/v1';
const ROUTES_URL =
  'https://routes.googleapis.com/directions/v2:computeRoutes';

const AUTOCOMPLETE_FIELD_MASK =
  'suggestions.placePrediction.placeId,' +
  'suggestions.placePrediction.text.text';
const PLACE_DETAILS_FIELD_MASK = 'id,formattedAddress,location';
const ROUTES_FIELD_MASK =
  'routes.distanceMeters,routes.duration,' +
  'routes.polyline.encodedPolyline,routes.routeLabels,' +
  'routes.legs.distanceMeters,routes.legs.duration';
const SEARCH_ALONG_ROUTE_FIELD_MASK =
  'places.id,places.displayName.text,places.formattedAddress,' +
  'places.location,routingSummaries.legs.duration,' +
  'routingSummaries.legs.distanceMeters';

export class GoogleMapsPlatformProvider implements RoutePlaceProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetcher: typeof fetch = fetch,
  ) {
    if (apiKey.trim().length === 0) {
      throw new Error('Google Maps Platform API key must not be empty.');
    }
  }

  async autocomplete(
    input: PlaceAutocompleteInput,
  ): Promise<readonly PlaceSuggestion[]> {
    const response = await this.fetcher(
      `${PLACES_BASE_URL}/places:autocomplete`,
      {
        method: 'POST',
        headers: this.headers(AUTOCOMPLETE_FIELD_MASK),
        body: JSON.stringify({
          input: input.input,
          ...(input.sessionToken == null
            ? {}
            : { sessionToken: input.sessionToken }),
        }),
      },
    );
    const body = await readJsonObject(response);

    if (!response.ok) {
      throw providerError(response.status, body);
    }

    const suggestions = array(body.suggestions);
    return suggestions.flatMap((item) => {
      const prediction = record(item.placePrediction);
      const reference = string(prediction.placeId);
      const textValue = string(record(prediction.text).text);
      if (reference == null || textValue == null) {
        return [];
      }
      return [{ reference, text: textValue }];
    });
  }

  async resolvePlace(input: ResolvePlaceInput): Promise<ResolvedPlace> {
    const url = new URL(
      `${PLACES_BASE_URL}/places/${encodeURIComponent(input.reference)}`,
    );
    if (input.sessionToken != null) {
      url.searchParams.set('sessionToken', input.sessionToken);
    }

    const response = await this.fetcher(url, {
      headers: this.headers(PLACE_DETAILS_FIELD_MASK),
    });
    const body = await readJsonObject(response);

    if (!response.ok) {
      throw providerError(response.status, body);
    }

    const reference = string(body.id);
    const location = geoPoint(body.location);
    if (reference == null || location == null) {
      throw new RoutePlaceProviderError(
        'provider_invalid_response',
        'The place provider returned an incomplete place.',
        502,
      );
    }

    return {
      reference,
      formattedAddress: string(body.formattedAddress),
      location,
    };
  }

  async computeRoutes(
    input: ComputeRoutesInput,
  ): Promise<readonly RouteOption[]> {
    const response = await this.fetcher(ROUTES_URL, {
      method: 'POST',
      headers: this.headers(ROUTES_FIELD_MASK),
      body: JSON.stringify({
        origin: waypoint(input.origin),
        destination: waypoint(input.destination),
        ...(input.intermediates.length === 0
          ? {}
          : {
              intermediates: input.intermediates.map((item) => ({
                ...waypoint(item.location),
                via: item.via,
              })),
            }),
        travelMode: travelMode(input.travelMode),
        computeAlternativeRoutes:
          input.computeAlternatives && input.intermediates.length === 0,
        routeModifiers: {
          avoidTolls: input.modifiers.avoidTolls,
          avoidHighways: input.modifiers.avoidHighways,
          avoidFerries: input.modifiers.avoidFerries,
        },
        units: 'METRIC',
      }),
    });
    const body = await readJsonObject(response);

    if (!response.ok) {
      throw providerError(response.status, body);
    }

    return array(body.routes).flatMap((raw, routeIndex) => {
      const distanceMeters = integer(raw.distanceMeters);
      const durationSeconds = duration(raw.duration);
      const encodedPolyline = string(record(raw.polyline).encodedPolyline);

      if (
        distanceMeters == null ||
        durationSeconds == null ||
        encodedPolyline == null
      ) {
        return [];
      }

      const legs: RouteLeg[] = array(raw.legs).flatMap((leg) => {
        const legDistance = integer(leg.distanceMeters);
        const legDuration = duration(leg.duration);
        if (legDistance == null || legDuration == null) {
          return [];
        }
        return [{
          distanceMeters: legDistance,
          durationSeconds: legDuration,
        }];
      });

      return [{
        routeIndex,
        labels: array(raw.routeLabels)
          .map((value) => typeof value === 'string' ? value : null)
          .filter((value): value is string => value != null),
        distanceMeters,
        durationSeconds,
        encodedPolyline,
        legs,
      }];
    });
  }

  async searchAlongRoute(
    input: SearchAlongRouteInput,
  ): Promise<readonly AlongRoutePlace[]> {
    if (input.travelMode === 'two_wheeler') {
      throw new RoutePlaceProviderError(
        'search_along_route_mode_not_supported',
        'Google Places Search Along Route does not currently support TWO_WHEELER.',
        400,
      );
    }

    const response = await this.fetcher(
      `${PLACES_BASE_URL}/places:searchText`,
      {
        method: 'POST',
        headers: this.headers(SEARCH_ALONG_ROUTE_FIELD_MASK),
        body: JSON.stringify({
          textQuery: input.textQuery,
          maxResultCount: input.maxResults,
          searchAlongRouteParameters: {
            polyline: {
              encodedPolyline: input.encodedPolyline,
            },
          },
          routingParameters: {
            travelMode: travelMode(input.travelMode),
            routeModifiers: {
              avoidTolls: input.modifiers.avoidTolls,
              avoidHighways: input.modifiers.avoidHighways,
              avoidFerries: input.modifiers.avoidFerries,
            },
          },
        }),
      },
    );
    const body = await readJsonObject(response);

    if (!response.ok) {
      throw providerError(response.status, body);
    }

    const places = array(body.places);
    const summaries = array(body.routingSummaries);

    return places.flatMap((place, index) => {
      const reference = string(place.id);
      const displayName = string(record(place.displayName).text);
      if (reference == null || displayName == null) {
        return [];
      }

      const legs = array(summaries[index]?.legs);
      const distances = legs
        .map((leg) => integer(leg.distanceMeters))
        .filter((value): value is number => value != null);
      const durations = legs
        .map((leg) => duration(leg.duration))
        .filter((value): value is number => value != null);

      return [{
        reference,
        displayName,
        formattedAddress: string(place.formattedAddress),
        location: geoPoint(place.location),
        viaPlaceDistanceMeters:
          distances.length === legs.length && legs.length > 0
            ? distances.reduce((sum, value) => sum + value, 0)
            : null,
        viaPlaceDurationSeconds:
          durations.length === legs.length && legs.length > 0
            ? durations.reduce((sum, value) => sum + value, 0)
            : null,
      }];
    });
  }

  private headers(fieldMask: string): HeadersInit {
    return {
      'content-type': 'application/json',
      'x-goog-api-key': this.apiKey,
      'x-goog-fieldmask': fieldMask,
    };
  }
}

function waypoint(point: GeoPoint): object {
  return {
    location: {
      latLng: {
        latitude: point.latitude,
        longitude: point.longitude,
      },
    },
  };
}

function travelMode(mode: ComputeRoutesInput['travelMode']): string {
  return mode === 'two_wheeler' ? 'TWO_WHEELER' : 'DRIVE';
}

async function readJsonObject(response: Response): Promise<Record<string, unknown>> {
  try {
    const value = await response.json();
    return record(value);
  } catch {
    return {};
  }
}

function providerError(
  status: number,
  body: Record<string, unknown>,
): RoutePlaceProviderError {
  const providerMessage = string(record(body.error).message);
  return new RoutePlaceProviderError(
    'maps_provider_error',
    providerMessage ?? 'The map provider request failed.',
    status >= 400 && status < 500 ? 400 : 502,
  );
}

function record(value: unknown): Record<string, any> {
  return typeof value === 'object' && value != null && !Array.isArray(value)
    ? value as Record<string, any>
    : {};
}

function array(value: unknown): Record<string, any>[] {
  return Array.isArray(value)
    ? value.map(record)
    : [];
}

function string(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function integer(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0
    ? value
    : null;
}

function duration(value: unknown): number | null {
  if (typeof value !== 'string') {
    return null;
  }
  const match = /^(\d+(?:\.\d+)?)s$/.exec(value);
  if (match?.[1] == null) {
    return null;
  }
  const seconds = Number(match[1]);
  return Number.isFinite(seconds) ? Math.round(seconds) : null;
}

function geoPoint(value: unknown): GeoPoint | null {
  const raw = record(value);
  const latitude = raw.latitude;
  const longitude = raw.longitude;
  if (typeof latitude !== 'number' || typeof longitude !== 'number') {
    return null;
  }
  return { latitude, longitude };
}
