import type {
  AlongRoutePlace, ComputeRoutesInput, GeoPoint, PlaceSuggestion,
  ResolvedPlace, RouteOption, SearchAlongRouteInput,
} from './models';
import {
  type PlaceAutocompleteInput, type ResolvePlaceInput,
  type RoutePlaceProvider, RoutePlaceProviderError,
} from './provider';

const PLACES_ORIGIN = 'https://places.googleapis.com';
const ROUTES_ORIGIN = 'https://routes.googleapis.com';
const REQUEST_TIMEOUT_MS = 15000;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const workerFetch: typeof fetch = (input, init) => fetch(input, init);

type JsonObject = Record<string, unknown>;

export class GoogleMapsProvider implements RoutePlaceProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetcher: typeof fetch = workerFetch,
  ) {
    if (apiKey.trim().length === 0) {
      throw new Error('Google Maps API key must not be empty.');
    }
  }

  async autocomplete(
    input: PlaceAutocompleteInput,
  ): Promise<readonly PlaceSuggestion[]> {
    const body = await this.request(
      new URL('/v1/places:autocomplete', PLACES_ORIGIN),
      {
        method: 'POST',
        body: JSON.stringify({
          input: input.input,
          ...(input.sessionToken == null
            ? {}
            : { sessionToken: input.sessionToken }),
        }),
      },
      'suggestions.placePrediction.placeId,suggestions.placePrediction.text.text',
    );

    return array(body.suggestions).flatMap((raw) => {
      const suggestion = recordOrNull(raw);
      const prediction = recordOrNull(suggestion?.placePrediction);
      const placeId = text(prediction?.placeId);
      const predictionText = text(recordOrNull(prediction?.text)?.text);
      return placeId == null || predictionText == null
        ? []
        : [{ reference: placeId, text: predictionText }];
    });
  }

  async resolvePlace(input: ResolvePlaceInput): Promise<ResolvedPlace> {
    const url = new URL(
      `/v1/places/${encodeURIComponent(input.reference)}`,
      PLACES_ORIGIN,
    );
    if (input.sessionToken != null) {
      url.searchParams.set('sessionToken', input.sessionToken);
    }

    const body = await this.request(
      url,
      { method: 'GET' },
      'id,formattedAddress,location',
    );
    const reference = text(body.id) ?? input.reference;
    const location = point(body.location);
    if (location == null) {
      throw invalidResponse();
    }

    return {
      reference,
      formattedAddress: text(body.formattedAddress),
      location,
    };
  }

  async computeRoutes(
    input: ComputeRoutesInput,
  ): Promise<readonly RouteOption[]> {
    const hasViaWaypoint = input.intermediates.some((waypoint) => waypoint.via);
    const routeFields = [
      'routes.distanceMeters',
      'routes.duration',
      'routes.polyline.encodedPolyline',
      'routes.legs.distanceMeters',
      'routes.legs.duration',
      'routes.routeLabels',
      ...(hasViaWaypoint ? [] : ['routes.routeToken']),
    ].join(',');

    const body = await this.request(
      new URL('/directions/v2:computeRoutes', ROUTES_ORIGIN),
      {
        method: 'POST',
        body: JSON.stringify({
          origin: routeWaypoint(input.origin),
          destination: routeWaypoint(input.destination),
          intermediates: input.intermediates.map((waypoint) => ({
            ...routeWaypoint(waypoint.location),
            via: waypoint.via,
          })),
          travelMode: googleTravelMode(input.travelMode),
          routingPreference: 'TRAFFIC_AWARE',
          computeAlternativeRoutes: input.computeAlternatives,
          routeModifiers: {
            avoidTolls: input.modifiers.avoidTolls,
            avoidHighways: input.modifiers.avoidHighways,
            avoidFerries: input.modifiers.avoidFerries,
          },
          polylineQuality: 'OVERVIEW',
        }),
      },
      routeFields,
    );

    return array(body.routes).map((raw, routeIndex) => {
      const route = record(raw);
      const polyline = record(route.polyline);
      const encodedPolyline = text(polyline.encodedPolyline);
      const distanceMeters = integerMetric(route.distanceMeters);
      const durationSeconds = duration(route.duration);
      const legs = array(route.legs).map((legRaw) => {
        const leg = record(legRaw);
        return {
          distanceMeters: integerMetric(leg.distanceMeters),
          durationSeconds: duration(leg.duration),
        };
      });

      if (encodedPolyline == null || legs.length === 0) {
        throw invalidResponse();
      }

      return {
        routeIndex,
        labels: array(route.routeLabels).filter(
          (value): value is string => typeof value === 'string',
        ),
        distanceMeters,
        durationSeconds,
        encodedPolyline,
        routeToken: text(route.routeToken),
        legs,
      };
    });
  }

  async searchAlongRoute(
    input: SearchAlongRouteInput,
  ): Promise<readonly AlongRoutePlace[]> {
    const body = await this.request(
      new URL('/v1/places:searchText', PLACES_ORIGIN),
      {
        method: 'POST',
        body: JSON.stringify({
          textQuery: input.textQuery,
          maxResultCount: input.maxResults,
          searchAlongRouteParameters: {
            polyline: { encodedPolyline: input.encodedPolyline },
          },
          routingParameters: {
            travelMode: googleTravelMode(input.travelMode),
            routeModifiers: {
              avoidTolls: input.modifiers.avoidTolls,
              avoidHighways: input.modifiers.avoidHighways,
              avoidFerries: input.modifiers.avoidFerries,
            },
          },
        }),
      },
      [
        'places.id',
        'places.displayName.text',
        'places.formattedAddress',
        'places.location',
        'routingSummaries.legs.distanceMeters',
        'routingSummaries.legs.duration',
      ].join(','),
    );

    const places = array(body.places);
    const summaries = array(body.routingSummaries);
    return places.flatMap((raw, index) => {
      const place = recordOrNull(raw);
      const reference = text(place?.id);
      const displayName = text(recordOrNull(place?.displayName)?.text);
      if (reference == null || displayName == null) {
        return [];
      }

      const summary = recordOrNull(summaries[index]);
      const legs = array(summary?.legs).flatMap((legRaw) => {
        const leg = recordOrNull(legRaw);
        if (leg == null) return [];
        try {
          return [{
            distanceMeters: integerMetric(leg.distanceMeters),
            durationSeconds: duration(leg.duration),
          }];
        } catch {
          return [];
        }
      });
      const totals = legs.length === 2
        ? {
            distanceMeters: legs.reduce(
              (sum, leg) => sum + leg.distanceMeters,
              0,
            ),
            durationSeconds: legs.reduce(
              (sum, leg) => sum + leg.durationSeconds,
              0,
            ),
          }
        : null;

      return [{
        reference,
        displayName,
        formattedAddress: text(place?.formattedAddress),
        location: point(place?.location),
        viaPlaceDistanceMeters: totals?.distanceMeters ?? null,
        viaPlaceDurationSeconds: totals?.durationSeconds ?? null,
      }];
    });
  }

  private async request(
    url: URL,
    init: RequestInit,
    fieldMask: string,
  ): Promise<JsonObject> {
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new RoutePlaceProviderError(
          'maps_provider_timeout',
          'The map provider timed out. Try again later.',
          504,
        ));
      }, REQUEST_TIMEOUT_MS);
    });

    const operation = async (): Promise<JsonObject> => {
      const headers = new Headers(init.headers);
      headers.set('accept', 'application/json');
      headers.set('x-goog-api-key', this.apiKey);
      headers.set('x-goog-fieldmask', fieldMask);
      if (init.body != null) {
        headers.set('content-type', 'application/json');
      }

      const response = await this.fetcher(url, {
        ...init,
        headers,
        signal: controller.signal,
        redirect: 'manual',
      });
      if (!response.ok) {
        const upstreamStatus = response.status;
        void response.body?.cancel().catch(() => {});
        console.warn('google_maps_request_failed', {
          stage:
            upstreamStatus >= 300 && upstreamStatus < 400
              ? 'redirect'
              : 'http',
          status: upstreamStatus,
        });
        const status =
          upstreamStatus === 429 ? 429 :
          upstreamStatus === 401 || upstreamStatus === 403 ? 503 :
          upstreamStatus >= 400 && upstreamStatus < 500 ? 400 :
          502;
        throw new RoutePlaceProviderError(
          'maps_provider_error',
          upstreamStatus === 429
            ? 'The map provider quota is temporarily unavailable.'
            : 'The map provider request could not be completed.',
          status,
        );
      }
      return readBoundedJson(response);
    };

    try {
      return await Promise.race([operation(), deadline]);
    } catch (error) {
      if (error instanceof RoutePlaceProviderError) {
        if (error.code === 'maps_provider_timeout') {
          console.warn('google_maps_request_failed', { stage: 'timeout' });
        }
        throw error;
      }
      console.warn('google_maps_request_failed', {
        stage: 'network',
        errorName: error instanceof Error ? error.name : 'unknown',
      });
      throw new RoutePlaceProviderError(
        'maps_provider_error',
        'The map provider could not be reached.',
        502,
      );
    } finally {
      clearTimeout(timer);
      controller.abort();
    }
  }
}

function routeWaypoint(location: GeoPoint): JsonObject {
  return {
    location: {
      latLng: {
        latitude: location.latitude,
        longitude: location.longitude,
      },
    },
  };
}

function googleTravelMode(
  value: ComputeRoutesInput['travelMode'] | SearchAlongRouteInput['travelMode'],
): 'DRIVE' | 'TWO_WHEELER' {
  return value === 'two_wheeler' ? 'TWO_WHEELER' : 'DRIVE';
}

async function readBoundedJson(response: Response): Promise<JsonObject> {
  if (response.body == null) {
    throw invalidResponse();
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0;
  let raw = '';
  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      bytes += chunk.value.byteLength;
      if (bytes > MAX_RESPONSE_BYTES) {
        void reader.cancel().catch(() => {});
        throw invalidResponse();
      }
      raw += decoder.decode(chunk.value, { stream: true });
    }
    raw += decoder.decode();
    return record(JSON.parse(raw));
  } catch (error) {
    if (error instanceof RoutePlaceProviderError) {
      throw error;
    }
    throw invalidResponse();
  } finally {
    reader.releaseLock();
  }
}

function invalidResponse(): RoutePlaceProviderError {
  return new RoutePlaceProviderError(
    'provider_invalid_response',
    'The map provider returned an incomplete or invalid response.',
    502,
  );
}

function record(value: unknown): JsonObject {
  const result = recordOrNull(value);
  if (result == null) {
    throw invalidResponse();
  }
  return result;
}

function recordOrNull(value: unknown): JsonObject | null {
  return typeof value === 'object' &&
    value != null &&
    !Array.isArray(value)
    ? value as JsonObject
    : null;
}

function array(value: unknown): unknown[] {
  return value == null ? [] : Array.isArray(value) ? value : [];
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0
    ? value
    : null;
}

function integerMetric(value: unknown): number {
  if (
    typeof value !== 'number' ||
    !Number.isFinite(value) ||
    value < 0 ||
    value > Number.MAX_SAFE_INTEGER
  ) {
    throw invalidResponse();
  }
  return Math.round(value);
}

function duration(value: unknown): number {
  if (typeof value !== 'string' || !value.endsWith('s')) {
    throw invalidResponse();
  }
  const parsed = Number(value.slice(0, -1));
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw invalidResponse();
  }
  return Math.round(parsed);
}

function point(value: unknown): GeoPoint | null {
  const raw = recordOrNull(value);
  if (raw == null) return null;
  const latitude = raw.latitude;
  const longitude = raw.longitude;
  return typeof latitude === 'number' &&
    Number.isFinite(latitude) &&
    latitude >= -90 &&
    latitude <= 90 &&
    typeof longitude === 'number' &&
    Number.isFinite(longitude) &&
    longitude >= -180 &&
    longitude <= 180
    ? { latitude, longitude }
    : null;
}
