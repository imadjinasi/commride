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

const AUTOCOMPLETE_URL = 'https://api.geoapify.com/v1/geocode/autocomplete';
const PLACE_DETAILS_URL = 'https://api.geoapify.com/v2/place-details';
const ROUTING_URL = 'https://api.geoapify.com/v1/routing';
const PLACES_URL = 'https://api.geoapify.com/v2/places';
const GEOCODE_SEARCH_URL = 'https://api.geoapify.com/v1/geocode/search';

const AUTOCOMPLETE_LIMIT = 8;
const ALONG_ROUTE_RADIUS_METERS = 5000;
const MAX_ALONG_ROUTE_SAMPLES = 6;
const MAX_RESULTS_PER_SAMPLE = 5;
const MATERIAL_ALTERNATIVE_RATIO = 0.02;

type RouteKind = 'balanced' | 'short';

interface CandidatePlace extends AlongRoutePlace {
  readonly routeDistanceMeters: number;
}

export class GeoapifyProvider implements RoutePlaceProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetcher: typeof fetch = fetch,
  ) {
    if (apiKey.trim().length === 0) {
      throw new Error('Geoapify API key must not be empty.');
    }
  }

  async autocomplete(
    input: PlaceAutocompleteInput,
  ): Promise<readonly PlaceSuggestion[]> {
    const url = this.url(AUTOCOMPLETE_URL);
    url.searchParams.set('text', input.input);
    url.searchParams.set('format', 'json');
    url.searchParams.set('limit', String(AUTOCOMPLETE_LIMIT));

    const response = await this.fetcher(url);
    const body = await readJsonObject(response);
    if (!response.ok) {
      throw providerError(response.status, body);
    }

    return array(body.results).flatMap((item) => {
      const reference = string(item.place_id);
      const text = string(item.formatted) ??
        string(item.address_line1) ??
        string(item.name);
      if (reference == null || text == null) {
        return [];
      }
      return [{ reference, text }];
    });
  }

  async resolvePlace(input: ResolvePlaceInput): Promise<ResolvedPlace> {
    const url = this.url(PLACE_DETAILS_URL);
    url.searchParams.set('id', input.reference);
    url.searchParams.set('features', 'details');

    const response = await this.fetcher(url);
    const body = await readJsonObject(response);
    if (!response.ok) {
      throw providerError(response.status, body);
    }

    const feature = array(body.features)[0];
    const properties = record(feature?.properties);
    const reference = string(properties.place_id) ?? input.reference;
    const location = geoPoint(properties) ?? geometryPoint(feature?.geometry);
    if (location == null) {
      throw new RoutePlaceProviderError(
        'provider_invalid_response',
        'The place provider returned an incomplete place.',
        502,
      );
    }

    return {
      reference,
      formattedAddress: string(properties.formatted),
      location,
    };
  }

  async computeRoutes(
    input: ComputeRoutesInput,
  ): Promise<readonly RouteOption[]> {
    const mode = input.travelMode === 'two_wheeler' ? 'motorcycle' : 'drive';

    if (
      input.travelMode === 'two_wheeler' &&
      (input.modifiers.avoidTolls || input.modifiers.avoidHighways)
    ) {
      throw new RoutePlaceProviderError(
        'route_modifier_not_supported',
        'Geoapify motorcycle routing does not support avoid-tolls or avoid-highways.',
        400,
      );
    }

    const waypointMode = intermediateWaypointMode(input);
    const kinds: readonly RouteKind[] =
      input.computeAlternatives && input.intermediates.length === 0
        ? ['balanced', 'short']
        : ['balanced'];

    const routeCandidates = await Promise.all(
      kinds.map((kind) => this.fetchRoute(input, mode, waypointMode, kind)),
    );

    const primary = routeCandidates[0];
    if (primary == null) {
      return [];
    }

    const accepted: RouteOption[] = [{ ...primary, routeIndex: 0 }];
    const alternative = routeCandidates[1];
    if (alternative != null && isMateriallyDifferent(primary, alternative)) {
      accepted.push({ ...alternative, routeIndex: 1 });
    }
    return accepted;
  }

  async searchAlongRoute(
    input: SearchAlongRouteInput,
  ): Promise<readonly AlongRoutePlace[]> {
    const routePoints = decodePolyline(input.encodedPolyline);
    if (routePoints.length === 0) {
      throw new RoutePlaceProviderError(
        'invalid_route_polyline',
        'Search Along Route requires a valid route polyline.',
        400,
      );
    }

    const samples = sampleRoute(routePoints, MAX_ALONG_ROUTE_SAMPLES);
    const perSampleLimit = Math.min(
      MAX_RESULTS_PER_SAMPLE,
      Math.max(3, input.maxResults),
    );

    const resultGroups = await Promise.all(
      samples.map((sample) =>
        this.searchNearRouteSample(
          input.textQuery,
          sample,
          perSampleLimit,
          samples,
        )),
    );

    const deduplicated = new Map<string, CandidatePlace>();
    for (const candidate of resultGroups.flat()) {
      const current = deduplicated.get(candidate.reference);
      if (
        current == null ||
        candidate.routeDistanceMeters < current.routeDistanceMeters
      ) {
        deduplicated.set(candidate.reference, candidate);
      }
    }

    return [...deduplicated.values()]
      .sort((a, b) =>
        a.routeDistanceMeters - b.routeDistanceMeters ||
        a.displayName.localeCompare(b.displayName)
      )
      .slice(0, input.maxResults)
      .map(({ routeDistanceMeters: _distance, ...place }) => place);
  }

  private async fetchRoute(
    input: ComputeRoutesInput,
    mode: 'motorcycle' | 'drive',
    waypointMode: 'stopover' | 'pass_through' | null,
    kind: RouteKind,
  ): Promise<RouteOption | null> {
    const url = this.url(ROUTING_URL);
    const points = [
      input.origin,
      ...input.intermediates.map((item) => item.location),
      input.destination,
    ];
    url.searchParams.set(
      'waypoints',
      points.map((point) => `${point.latitude},${point.longitude}`).join('|'),
    );
    url.searchParams.set('mode', mode);
    url.searchParams.set('type', kind);
    url.searchParams.set('units', 'metric');
    url.searchParams.set('format', 'geojson');

    if (waypointMode != null) {
      url.searchParams.set('intermediate_waypoint_mode', waypointMode);
    }

    const avoid = routeAvoids(input);
    if (avoid.length > 0) {
      url.searchParams.set('avoid', avoid.join('|'));
    }

    const response = await this.fetcher(url);
    const body = await readJsonObject(response);
    if (!response.ok) {
      throw providerError(response.status, body);
    }

    const feature = array(body.features)[0];
    if (feature == null) {
      return null;
    }

    const properties = record(feature.properties);
    const distanceMeters = nonNegativeNumber(properties.distance);
    const durationSeconds = nonNegativeNumber(properties.time);
    const pointsFromGeometry = routeGeometryPoints(feature.geometry);
    if (
      distanceMeters == null ||
      durationSeconds == null ||
      pointsFromGeometry.length === 0
    ) {
      throw new RoutePlaceProviderError(
        'provider_invalid_response',
        'The routing provider returned an incomplete route.',
        502,
      );
    }

    const legs: RouteLeg[] = array(properties.legs).flatMap((rawLeg) => {
      const distance = nonNegativeNumber(rawLeg.distance);
      const duration = nonNegativeNumber(rawLeg.time);
      if (distance == null || duration == null) {
        return [];
      }
      return [{
        distanceMeters: Math.round(distance),
        durationSeconds: Math.round(duration),
      }];
    });

    return {
      routeIndex: 0,
      labels: [kind === 'balanced' ? 'RECOMMENDED' : 'SHORTEST'],
      distanceMeters: Math.round(distanceMeters),
      durationSeconds: Math.round(durationSeconds),
      encodedPolyline: encodePolyline(pointsFromGeometry),
      legs,
    };
  }

  private async searchNearRouteSample(
    textQuery: string,
    sample: GeoPoint,
    limit: number,
    routeSamples: readonly GeoPoint[],
  ): Promise<readonly CandidatePlace[]> {
    const categories = categoriesForQuery(textQuery);
    return categories == null
      ? this.searchGeocodingNearSample(textQuery, sample, limit, routeSamples)
      : this.searchPlacesNearSample(categories, sample, limit, routeSamples);
  }

  private async searchPlacesNearSample(
    categories: string,
    sample: GeoPoint,
    limit: number,
    routeSamples: readonly GeoPoint[],
  ): Promise<readonly CandidatePlace[]> {
    const url = this.url(PLACES_URL);
    url.searchParams.set('categories', categories);
    url.searchParams.set(
      'filter',
      `circle:${sample.longitude},${sample.latitude},${ALONG_ROUTE_RADIUS_METERS}`,
    );
    url.searchParams.set(
      'bias',
      `proximity:${sample.longitude},${sample.latitude}`,
    );
    url.searchParams.set('limit', String(limit));

    const response = await this.fetcher(url);
    const body = await readJsonObject(response);
    if (!response.ok) {
      throw providerError(response.status, body);
    }

    return array(body.features).flatMap((feature) => {
      const properties = record(feature.properties);
      const location = geoPoint(properties) ?? geometryPoint(feature.geometry);
      const reference = string(properties.place_id);
      const displayName = string(properties.name) ??
        string(properties.address_line1) ??
        string(properties.formatted);
      if (reference == null || displayName == null || location == null) {
        return [];
      }

      return [candidatePlace(
        reference,
        displayName,
        string(properties.formatted),
        location,
        routeSamples,
      )];
    });
  }

  private async searchGeocodingNearSample(
    textQuery: string,
    sample: GeoPoint,
    limit: number,
    routeSamples: readonly GeoPoint[],
  ): Promise<readonly CandidatePlace[]> {
    const url = this.url(GEOCODE_SEARCH_URL);
    url.searchParams.set('text', textQuery);
    url.searchParams.set('format', 'json');
    url.searchParams.set(
      'filter',
      `circle:${sample.longitude},${sample.latitude},${ALONG_ROUTE_RADIUS_METERS}`,
    );
    url.searchParams.set(
      'bias',
      `proximity:${sample.longitude},${sample.latitude}`,
    );
    url.searchParams.set('limit', String(limit));

    const response = await this.fetcher(url);
    const body = await readJsonObject(response);
    if (!response.ok) {
      throw providerError(response.status, body);
    }

    return array(body.results).flatMap((item) => {
      const reference = string(item.place_id);
      const displayName = string(item.name) ??
        string(item.address_line1) ??
        string(item.formatted);
      const location = geoPoint(item);
      if (reference == null || displayName == null || location == null) {
        return [];
      }

      return [candidatePlace(
        reference,
        displayName,
        string(item.formatted),
        location,
        routeSamples,
     )];
    });
  }

  private url(base: string): URL {
    const url = new URL(base);
    url.searchParams.set('apiKey', this.apiKey);
    return url;
  }
}

function intermediateWaypointMode(
  input: ComputeRoutesInput,
): 'stopover' | 'pass_through' | null {
  if (input.intermediates.length === 0) {
    return null;
  }

  const viaCount = input.intermediates.filter((item) => item.via).length;
  if (viaCount === 0) {
    return 'stopover';
  }
  if (viaCount === input.intermediates.length) {
    return 'pass_through';
  }

  throw new RoutePlaceProviderError(
    'mixed_waypoint_modes_not_supported',
    'Geoapify routing requires one intermediate waypoint mode per route request.',
    400,
  );
}

function routeAvoids(input: ComputeRoutesInput): string[] {
  const values: string[] = [];
  if (input.modifiers.avoidTolls) {
    values.push('tolls');
  }
  if (input.modifiers.avoidHighways) {
    values.push('highways');
  }
  if (input.modifiers.avoidFerries) {
    values.push('ferries');
  }
  return values;
}

function isMateriallyDifferent(
  primary: RouteOption,
  alternative: RouteOption,
): boolean {
  if (primary.encodedPolyline === alternative.encodedPolyline) {
    return false;
  }

  const distanceRatio =
    Math.abs(primary.distanceMeters - alternative.distanceMeters) /
    Math.max(primary.distanceMeters, 1);
  const durationRatio =
    Math.abs(primary.durationSeconds - alternative.durationSeconds) /
    Math.max(primary.durationSeconds, 1);

  return distanceRatio >= MATERIAL_ALTERNATIVE_RATIO ||
    durationRatio >= MATERIAL_ALTERNATIVE_RATIO;
}

function categoriesForQuery(textQuery: string): string | null {
  const query = textQuery.trim().toLowerCase();
  if (
    query.includes('fuel') ||
    query.includes('gas station') ||
    query.includes('bbm')
  ) {
    return 'service.vehicle.fuel';
  }
  if (
    query.includes('restaurant') ||
    query.includes('food') ||
    query.includes('makan')
  ) {
    return 'catering.restaurant,catering.fast_food,catering.food_court';
  }
  if (query.includes('hotel') || query.includes('penginapan')) {
    return 'accommodation.hotel,accommodation.guest_house,accommodation.motel';
  }
  return null;
}

function candidatePlace(
  reference: string,
  displayName: string,
  formattedAddress: string | null,
  location: GeoPoint,
  routeSamples: readonly GeoPoint[],
): CandidatePlace {
  return {
    reference,
    displayName,
    formattedAddress,
    location,
    viaPlaceDistanceMeters: null,
    viaPlaceDurationSeconds: null,
    routeDistanceMeters: Math.min(
      ...routeSamples.map((sample) => distanceMeters(location, sample)),
    ),
  };
}

function sampleRoute(
  points: readonly GeoPoint[],
  maxSamples: number,
): GeoPoint[] {
  if (points.length <= maxSamples) {
    return [...points];
  }

  const indexes = new Set<number>();
  for (let index = 0; index < maxSamples; index += 1) {
    indexes.add(
      Math.round(index * (points.length - 1) / (maxSamples - 1)),
    );
  }
  return [...indexes].map((index) => points[index]!);
}

function distanceMeters(a: GeoPoint, b: GeoPoint): number {
  const earthRadiusMeters = 6371000;
  const degreesToRadians = Math.PI / 180;
  const lat1 = a.latitude * degreesToRadians;
  const lat2 = b.latitude * degreesToRadians;
  const deltaLat = (b.latitude - a.latitude) * degreesToRadians;
  const deltaLon = (b.longitude - a.longitude) * degreesToRadians;

  const haversine =
    Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLon / 2) ** 2;

  return 2 * earthRadiusMeters * Math.atan2(
    Math.sqrt(haversine),
    Math.sqrt(1 - haversine),
  );
}

function routeGeometryPoints(value: unknown): GeoPoint[] {
  const geometry = record(value);
  const coordinates = geometry.coordinates;
  if (!Array.isArray(coordinates)) {
    return [];
  }

  const points: GeoPoint[] = [];
  for (const rawLine of coordinates) {
    if (!Array.isArray(rawLine)) {
      continue;
    }
    for (const rawPoint of rawLine) {
      if (!Array.isArray(rawPoint) || rawPoint.length < 2) {
        continue;
      }
      const longitude = rawPoint[0];
      const latitude = rawPoint[1];
      if (
        typeof latitude !== 'number' ||
        !Number.isFinite(latitude) ||
        typeof longitude !== 'number' ||
        !Number.isFinite(longitude)
      ) {
        continue;
      }
      const previous = points[points.length - 1];
      if (
        previous?.latitude === latitude &&
        previous.longitude === longitude
      ) {
        continue;
      }
      points.push({ latitude, longitude });
    }
  }
  return points;
}

function encodePolyline(points: readonly GeoPoint[]): string {
  let lastLatitude = 0;
  let lastLongitude = 0;
  let encoded = '';

  for (const point of points) {
    const latitude = Math.round(point.latitude * 1e5);
    const longitude = Math.round(point.longitude * 1e5);
    encoded += encodeSigned(latitude - lastLatitude);
    encoded += encodeSigned(longitude - lastLongitude);
    lastLatitude = latitude;
    lastLongitude = longitude;
  }
  return encoded;
}

function encodeSigned(value: number): string {
  let current = value < 0 ? ~(value << 1) : value << 1;
  let encoded = '';
  while (current >= 0x20) {
    encoded += String.fromCharCode((0x20 | (current & 0x1f)) + 63);
    current >>= 5;
  }
  return encoded + String.fromCharCode(current + 63);
}

function decodePolyline(encoded: string): GeoPoint[] {
  const points: GeoPoint[] = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;

  try {
    while (index < encoded.length) {
      const latitudeResult = decodeSigned(encoded, index);
      latitude += latitudeResult.value;
      index = latitudeResult.nextIndex;

      const longitudeResult = decodeSigned(encoded, index);
      longitude += longitudeResult.value;
      index = longitudeResult.nextIndex;

      points.push({
        latitude: latitude / 1e5,
        longitude: longitude / 1e5,
      });
    }
  } catch {
    return [];
  }

  return points;
}

function decodeSigned(
  encoded: string,
  startIndex: number;
): { readonly value: number; readonly nextIndex: number } {
  let result = 0;
  let shift = 0;
  let index = startIndex;

  while (index < encoded.length) {
    const byte = encoded.charCodeAt(index) - 63;
    index += 1;
    if (byte < 0) {
      throw new Error('invalid_polyline');
    }
    result |= (byte & 0x1f) << shift;
    shift += 5;
    if (byte < 0x20) {
      const value = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
      retur { value, nextIndex: index };
    }
    if (shift > 30) {
      throw new Error('invalid_polyline');
    }
  }

  throw new Error('invalid_polyline');
}

async function readJsonObject(
  response: Response,
): Promise<Record<string, unknown>> {
  try {
    return record(await response.json());
  } catch {
    return {};
  }
}

function providerError(
  status: number,
  body: Record<string, unknown>,
): RoutePlaceProviderError {
  const rawError = body.error;
  const providerMessage =
    string(record(rawError).message) ??
    string(rawError) ??
    string(body.message);

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
  return Array.isArray(value) ? value.map(record) : [];
}

function string(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0
    ? value
    : null;
}

function nonNegativeNumber(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
    ? value
    : null;
}

function geoPoint(value: unknown): GeoPoint | null {
  const raw = record(value);
  const latitude = raw.lat ?? raw.latitude;
  const longitude = raw.lon ?? raw.longitude;
  if (
    typeof latitude !== 'number' ||
    !Number.isFinite(latitude) ||
    typeof longitude !== 'number' ||
    !Number.isFinite(longitude)
  ) {
    return null;
  }
  return { latitude, longitude };
}

function geometryPoint(value: unknown): GeoPoint | null {
  const geometry = record(value);
  const coordinates = geometry.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 2) {
    return null;
  }
  const longitude = coordinates[0];
  const latitude = coordinates[1];
  if (
    typeof latitude !== 'number' ||
    !Number.isFinite(latitude) ||
    typeof longitude !== 'number' ||
    !Number.isFinite(longitude)
  ) {
    return null;
  }
  return { latitude, longitude };
}
