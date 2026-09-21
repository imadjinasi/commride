import type {
  AlongRoutePlace, ComputeRoutesInput, GeoPoint, PlaceSuggestion,
  ResolvedPlace, RouteOption, SearchAlongRouteInput,
} from './models';
import {
  type PlaceAutocompleteInput, type ResolvePlaceInput,
  type RoutePlaceProvider, RoutePlaceProviderError,
} from './provider';
import {
  decodePolyline, distanceMeters, distanceToRoute, encodePolyline,
  MAX_POLYLINE_LENGTH, sampleRoute, validPoint,
} from './route-geometry';

const API_ORIGIN = 'https://api.geoapify.com';
const REQUEST_TIMEOUT_MS = 15000;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const SEARCH_RADIUS_METERS = 5000;
const MAX_SEARCH_CENTERS = 6;
const MAX_PER_CENTER = 5;
const workerFetch: typeof fetch = (input, init) => fetch(input, init);

type JsonObject = Record<string, unknown>;
type RouteKind = 'balanced' | 'short';
interface Candidate extends AlongRoutePlace { readonly routeDistance: number }

/** Provider payloads, credentials and request policy stop at this boundary. */
export class GeoapifyProvider implements RoutePlaceProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetcher: typeof fetch = workerFetch,
  ) {
    if (apiKey.trim().length === 0) throw new Error('Geoapify API key must not be empty.');
  }

  async autocomplete(input: PlaceAutocompleteInput): Promise<readonly PlaceSuggestion[]> {
    const body = await this.get('/v1/geocode/autocomplete', {
      text: input.input, format: 'json', limit: '8',
    });
    return collection(body, 'results').slice(0, 8).flatMap((item) => {
      const reference = text(item.place_id);
      const label = text(item.formatted) ?? text(item.address_line1) ?? text(item.name);
      return reference == null || reference.length > 500 || label == null
        ? [] : [{ reference, text: label }];
    });
  }

  async resolvePlace(input: ResolvePlaceInput): Promise<ResolvedPlace> {
    const body = await this.get('/v2/place-details', { id: input.reference, features: 'details' });
    const feature = collection(body, 'features')[0];
    if (feature == null) throw invalidResponse();
    const properties = object(feature.properties);
    const location = placePoint(properties, feature.geometry);
    if (location == null) throw invalidResponse();
    return {
      reference: text(properties.place_id) ?? input.reference,
      formattedAddress: text(properties.formatted),
      location,
    };
  }

  async computeRoutes(input: ComputeRoutesInput): Promise<readonly RouteOption[]> {
    if (input.travelMode === 'two_wheeler' &&
        (input.modifiers.avoidTolls || input.modifiers.avoidHighways)) {
      throw new RoutePlaceProviderError('route_modifier_not_supported',
        'Motorcycle routing does not support toll or highway avoidance preferences.', 400);
    }
    const viaCount = input.intermediates.filter((point) => point.via).length;
    if (viaCount > 0 && viaCount !== input.intermediates.length) {
      throw new RoutePlaceProviderError('mixed_waypoint_modes_not_supported',
        'Use one intermediate waypoint mode per route request.', 400);
    }
    const primary = await this.route(input, 'balanced');
    if (primary == null) return [];
    const routes: RouteOption[] = [primary];
    if (input.computeAlternatives && input.intermediates.length === 0) {
      // An optional alternative failure must not destroy the valid primary route.
      try {
        const alternate = await this.route(input, 'short');
        if (alternate != null && materiallyDifferent(primary, alternate)) {
          routes.push({ ...alternate, routeIndex: 1 });
        }
      } catch (error) {
        if (!(error instanceof RoutePlaceProviderError)) throw error;
      }
    }
    return routes;
  }

  private async route(input: ComputeRoutesInput, kind: RouteKind): Promise<RouteOption | null> {
    const points = [input.origin, ...input.intermediates.map((p) => p.location), input.destination];
    if (points.some((p) => validPoint(p.latitude, p.longitude) == null)) {
      throw new RoutePlaceProviderError('invalid_maps_request', 'Invalid route coordinates.', 400);
    }
    const parameters: Record<string, string> = {
      waypoints: points.map((p) => `${p.latitude},${p.longitude}`).join('|'),
      mode: input.travelMode === 'two_wheeler' ? 'motorcycle' : 'drive',
      type: kind, units: 'metric', format: 'geojson',
    };
    if (input.intermediates.length > 0) {
      parameters.intermediate_waypoint_mode = input.intermediates[0]!.via ? 'pass_through' : 'stopover';
    }
    const avoids = [
      ...(input.modifiers.avoidTolls ? ['tolls'] : []),
      ...(input.modifiers.avoidHighways ? ['highways'] : []),
      ...(input.modifiers.avoidFerries ? ['ferries'] : []),
    ];
    if (avoids.length > 0) parameters.avoid = avoids.join('|');
    const body = await this.get('/v1/routing', parameters);
    const feature = collection(body, 'features')[0];
    if (feature == null) return null;
    const properties = object(feature.properties);
    const geometry = object(feature.geometry);
    if (geometry.type !== 'MultiLineString' || !Array.isArray(geometry.coordinates)) throw invalidResponse();
    const routePoints: GeoPoint[] = [];
    for (const line of geometry.coordinates) {
      if (!Array.isArray(line) || line.length < 2) throw invalidResponse();
      for (const coordinates of line) {
        if (!Array.isArray(coordinates)) throw invalidResponse();
        const point = validPoint(coordinates[1], coordinates[0]);
        if (point == null) throw invalidResponse();
        const previous = routePoints.at(-1);
        if (previous?.latitude !== point.latitude || previous.longitude !== point.longitude) {
          routePoints.push(point);
        }
      }
    }
    if (routePoints.length < 2) throw invalidResponse();
    const encodedPolyline = encodePolyline(routePoints);
    if (encodedPolyline.length > MAX_POLYLINE_LENGTH) {
      throw new RoutePlaceProviderError('route_geometry_too_large',
        'This route is too detailed for the pilot. Choose a shorter Ride segment.', 422);
    }
    const legs = collection(properties, 'legs').map((leg) => ({
      distanceMeters: metric(leg.distance), durationSeconds: metric(leg.time),
    }));
    if (legs.length === 0) throw invalidResponse();
    return {
      routeIndex: 0, labels: [kind === 'balanced' ? 'RECOMMENDED' : 'SHORTEST'],
      distanceMeters: metric(properties.distance), durationSeconds: metric(properties.time),
      encodedPolyline, legs,
    };
  }

  async searchAlongRoute(input: SearchAlongRouteInput): Promise<readonly AlongRoutePlace[]> {
    const route = decodePolyline(input.encodedPolyline);
    if (route.length < 2) {
      throw new RoutePlaceProviderError('invalid_route_polyline',
        'Search Along Route requires a valid route polyline.', 400);
    }
    if (!Number.isInteger(input.maxResults) || input.maxResults < 1 || input.maxResults > 10) {
      throw new RoutePlaceProviderError('invalid_maps_request', 'Invalid result limit.', 400);
    }
    const centers = sampleRoute(route, MAX_SEARCH_CENTERS);
    const category = categoryForQuery(input.textQuery);
    const groups = await Promise.all(centers.map(async (center): Promise<Candidate[]> => {
      const limit = Math.min(MAX_PER_CENTER, input.maxResults);
      const parameters: Record<string, string> = {
        filter: `circle:${center.longitude},${center.latitude},${SEARCH_RADIUS_METERS}`,
        bias: `proximity:${center.longitude},${center.latitude}`, limit: String(limit),
      };
      const body = category == null
        ? await this.get('/v1/geocode/search', { ...parameters, text: input.textQuery, format: 'json' })
        : await this.get('/v2/places', { ...parameters, categories: category });
      const items = collection(body, category == null ? 'results' : 'features').slice(0, limit);
      return items.flatMap((item) => {
        const properties = category == null ? item : object(item.properties);
        const reference = text(properties.place_id);
        const displayName = text(properties.name) ?? text(properties.address_line1) ?? text(properties.formatted);
        const location = placePoint(properties, item.geometry);
        if (reference == null || reference.length > 500 || displayName == null || location == null) return [];
        const routeDistance = distanceToRoute(location, route);
        if (routeDistance > SEARCH_RADIUS_METERS ||
            distanceMeters(location, center) > SEARCH_RADIUS_METERS) return [];
        return [{
          reference, displayName, location,
          formattedAddress: text(properties.formatted),
          // Geographic proximity is not a measured detour or road-access promise.
          viaPlaceDistanceMeters: null, viaPlaceDurationSeconds: null, routeDistance,
        }];
      });
    }));
    const unique = new Map<string, Candidate>();
    for (const candidate of groups.flat()) {
      const previous = unique.get(candidate.reference);
      if (previous == null || candidate.routeDistance < previous.routeDistance) {
        unique.set(candidate.reference, candidate);
      }
    }
    return [...unique.values()]
      .sort((a, b) => a.routeDistance - b.routeDistance || a.reference.localeCompare(b.reference))
      .slice(0, input.maxResults)
      .map(({ routeDistance: _distance, ...place }) => place);
  }

  private async get(path: string, parameters: Record<string, string>): Promise<JsonObject> {
    const url = new URL(path, API_ORIGIN);
    for (const [name, value] of Object.entries(parameters)) url.searchParams.set(name, value);
    url.searchParams.set('apiKey', this.apiKey);
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new RoutePlaceProviderError('maps_provider_timeout',
          'The map provider timed out. Try again later.', 504));
      }, REQUEST_TIMEOUT_MS);
    });
    const operation = async (): Promise<JsonObject> => {
      const response = await this.fetcher(url, {
        signal: controller.signal, redirect: 'error', headers: { accept: 'application/json' },
      });
      if (!response.ok) {
        const upstreamStatus = response.status;
        void response.body?.cancel().catch(() => {});
        // Never use upstream text: it can echo request URLs, coordinates or keys.
        console.warn('geoapify_request_failed', {
          stage: 'http',
          status: upstreamStatus,
        });
        const status = upstreamStatus === 429 ? 429 :
          upstreamStatus === 401 || upstreamStatus === 403 ? 503 :
          upstreamStatus >= 400 && upstreamStatus < 500 ? 400 : 502;
        throw new RoutePlaceProviderError('maps_provider_error',
          status === 429 ? 'The map provider quota is temporarily unavailable.' :
          'The map provider request could not be completed.', status);
      }
      try {
        return await readBoundedJson(response);
      } catch (error) {
        if (error instanceof RoutePlaceProviderError) {
          console.warn('geoapify_request_failed', {
            stage: 'response',
          });
        }
        throw error;
      }
    };
    try {
      return await Promise.race([operation(), deadline]);
    } catch (error) {
      if (error instanceof RoutePlaceProviderError) {
        if (error.code === 'maps_provider_timeout') {
          console.warn('geoapify_request_failed', {
            stage: 'timeout',
          });
        }
        throw error;
      }
      console.warn('geoapify_request_failed', {
        stage: 'network',
      });
      throw new RoutePlaceProviderError('maps_provider_error',
        'The map provider could not be reached.', 502);
    } finally {
      clearTimeout(timer);
      controller.abort();
    }
  }
}

async function readBoundedJson(response: Response): Promise<JsonObject> {
  if (response.body == null) throw invalidResponse();
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let length = 0, body = '';
  try {
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      length += chunk.value.byteLength;
      if (length > MAX_RESPONSE_BYTES) {
        void reader.cancel().catch(() => {});
        throw invalidResponse();
      }
      body += decoder.decode(chunk.value, { stream: true });
    }
    body += decoder.decode();
    return object(JSON.parse(body));
  } catch (error) {
    if (error instanceof RoutePlaceProviderError) throw error;
    throw invalidResponse();
  } finally { reader.releaseLock(); }
}

function invalidResponse(): RoutePlaceProviderError {
  return new RoutePlaceProviderError('provider_invalid_response',
    'The map provider returned an incomplete or invalid response.', 502);
}
function object(value: unknown): JsonObject {
  if (typeof value !== 'object' || value == null || Array.isArray(value)) throw invalidResponse();
  return value as JsonObject;
}
function collection(body: JsonObject, name: string): JsonObject[] {
  const values = body[name];
  if (!Array.isArray(values)) throw invalidResponse();
  return values.map(object);
}
function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value : null;
}
function metric(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > Number.MAX_SAFE_INTEGER) {
    throw invalidResponse();
  }
  return Math.round(value);
}
function placePoint(properties: JsonObject, geometry: unknown): GeoPoint | null {
  const point = validPoint(properties.lat, properties.lon);
  if (point != null) return point;
  if (geometry == null || typeof geometry !== 'object' || Array.isArray(geometry)) return null;
  const raw = geometry as JsonObject;
  return raw.type === 'Point' && Array.isArray(raw.coordinates)
    ? validPoint(raw.coordinates[1], raw.coordinates[0]) : null;
}
function materiallyDifferent(a: RouteOption, b: RouteOption): boolean {
  return a.encodedPolyline !== b.encodedPolyline && (
    Math.abs(a.distanceMeters - b.distanceMeters) / Math.max(1, a.distanceMeters) >= 0.02 ||
    Math.abs(a.durationSeconds - b.durationSeconds) / Math.max(1, a.durationSeconds) >= 0.02
  );
}
function categoryForQuery(query: string): string | null {
  switch (query.trim().toLowerCase()) {
    case 'fuel': case 'fuel station': case 'gas station': case 'bbm': case 'spbu':
      return 'service.vehicle.fuel';
    case 'restaurant': case 'food': case 'makan':
      return 'catering.restaurant,catering.fast_food,catering.food_court';
    case 'hotel': case 'penginapan':
      return 'accommodation.hotel,accommodation.guest_house,accommodation.motel';
    default: return null;
  }
}
