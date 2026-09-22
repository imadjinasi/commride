import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type {
  ComputeRoutesInput,
  GeoPoint,
  RouteModifiers,
  RouteTravelMode,
  RouteWaypoint,
  SearchAlongRouteInput,
  TrafficIncidentInput,
} from './models';
import {
  type RoutePlaceProvider,
  RoutePlaceProviderError,
} from './provider';
import type { TrafficIncidentProvider } from './traffic-provider';

const MAX_INTERMEDIATE_STOPS = 10;
const MAX_ALONG_ROUTE_RESULTS = 10;
const MAX_TRAFFIC_INCIDENTS = 100;

export interface MapsHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly provider: RoutePlaceProvider;
  readonly trafficProvider?: TrafficIncidentProvider;
}

export function isMapsPath(pathname: string): boolean {
  return pathname === '/v1/maps/autocomplete' ||
    pathname === '/v1/maps/resolve-place' ||
    pathname === '/v1/maps/routes' ||
    pathname === '/v1/maps/search-along-route' ||
    pathname === '/v1/maps/traffic-incidents';
}

export async function handleMapsRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: MapsHandlerDependencies,
): Promise<Response | null> {
  if (!isMapsPath(url.pathname)) {
    return null;
  }

  if (request.method !== 'POST') {
    return errorResponse(
      'method_not_allowed',
      'Only POST is supported for this endpoint.',
      405,
      requestId,
    );
  }

  const authentication = await authenticateRider(
    request,
    dependencies.identityVerifier,
    dependencies.riderRepository,
  );
  if ('error' in authentication) {
    return errorResponse(
      authentication.error,
      authentication.message,
      authentication.status,
      requestId,
    );
  }

  let body: Record<string, unknown>;
  try {
    const value = await request.json();
    if (!isRecord(value)) {
      throw new Error('not_object');
    }
    body = value;
  } catch {
    return errorResponse(
      'invalid_maps_request',
      'Request body must be a JSON object.',
      400,
      requestId,
    );
  }

  try {
    // Await here so asynchronous provider failures reach the typed error boundary.
    if (url.pathname === '/v1/maps/autocomplete') {
      return await autocomplete(body, requestId, dependencies.provider);
    }

    if (url.pathname === '/v1/maps/resolve-place') {
      return await resolvePlace(body, requestId, dependencies.provider);
    }

    if (url.pathname === '/v1/maps/routes') {
      return await computeRoutes(body, requestId, dependencies.provider);
    }

    if (url.pathname === '/v1/maps/traffic-incidents') {
      if (dependencies.trafficProvider == null) {
        return errorResponse(
          'traffic_not_configured',
          'Realtime traffic data is not configured for this environment.',
          503,
          requestId,
        );
      }
      return await trafficIncidents(
        body,
        requestId,
        dependencies.trafficProvider,
      );
    }

    return await searchAlongRoute(body, requestId, dependencies.provider);
  } catch (error) {
    if (error instanceof RoutePlaceProviderError) {
      return errorResponse(
        error.code,
        error.message,
        error.status,
        requestId,
      );
    }
    throw error;
  }
}

async function autocomplete(
  body: Record<string, unknown>,
  requestId: string,
  provider: RoutePlaceProvider,
): Promise<Response> {
  const input = requiredString(body.input, 2, 120);
  const sessionToken = optionalString(body.sessionToken, 128);

  if (input == null || sessionToken === undefined) {
    return errorResponse(
      'invalid_maps_request',
      'Autocomplete requires input between 2 and 120 characters.',
      400,
      requestId,
    );
  }

  const suggestions = await provider.autocomplete({
    input,
    ...(sessionToken == null ? {} : { sessionToken }),
  });

  return jsonResponse({ suggestions }, 200, requestId);
}

async function resolvePlace(
  body: Record<string, unknown>,
  requestId: string,
  provider: RoutePlaceProvider,
): Promise<Response> {
  const reference = requiredString(body.reference, 1, 500);
  const sessionToken = optionalString(body.sessionToken, 128);

  if (reference == null || sessionToken === undefined) {
    return errorResponse(
      'invalid_maps_request',
      'A valid place reference is required.',
      400,
      requestId,
    );
  }

  const place = await provider.resolvePlace({
    reference,
    ...(sessionToken == null ? {} : { sessionToken }),
  });

  return jsonResponse({ place }, 200, requestId);
}

async function computeRoutes(
  body: Record<string, unknown>,
  requestId: string,
  provider: RoutePlaceProvider,
): Promise<Response> {
  const origin = point(body.origin);
  const destination = point(body.destination);
  const travelMode = routeTravelMode(body.travelMode);
  const modifiers = routeModifiers(body.modifiers);
  const computeAlternatives = body.computeAlternatives === true;

  const rawIntermediates = Array.isArray(body.intermediates)
    ? body.intermediates
    : [];
  if (rawIntermediates.length > MAX_INTERMEDIATE_STOPS) {
    return errorResponse(
      'too_many_intermediate_stops',
      'The MVP supports at most 10 intermediate stops per route request.',
      400,
      requestId,
    );
  }

  const intermediates: RouteWaypoint[] = [];
  for (const raw of rawIntermediates) {
    if (!isRecord(raw)) {
      return invalidRoute(requestId);
    }
    const location = point(raw.location);
    if (location == null) {
      return invalidRoute(requestId);
    }
    intermediates.push({
      location,
      via: raw.via === true,
    });
  }

  if (
    origin == null ||
    destination == null ||
    travelMode == null ||
    modifiers == null
  ) {
    return invalidRoute(requestId);
  }

  if (computeAlternatives && intermediates.length > 0) {
    return errorResponse(
      'route_alternatives_with_stops_not_supported',
      'Alternative routes are available only before intermediate stops are added.',
      400,
      requestId,
    );
  }

  const input: ComputeRoutesInput = {
    origin,
    destination,
    intermediates,
    travelMode,
    computeAlternatives,
    modifiers,
  };

  const routes = await provider.computeRoutes(input);
  return jsonResponse({ routes }, 200, requestId);
}

async function searchAlongRoute(
  body: Record<string, unknown>,
  requestId: string,
  provider: RoutePlaceProvider,
): Promise<Response> {
  const textQuery = requiredString(body.textQuery, 2, 100);
  const encodedPolyline = requiredString(body.encodedPolyline, 1, 20000);
  const travelMode = routeTravelMode(body.travelMode);
  const modifiers = routeModifiers(body.modifiers);
  const maxResults = optionalPositiveInteger(
    body.maxResults,
    MAX_ALONG_ROUTE_RESULTS,
    5,
  );

  if (
    textQuery == null ||
    encodedPolyline == null ||
    travelMode == null ||
    modifiers == null ||
    maxResults == null
  ) {
    return errorResponse(
      'invalid_maps_request',
      'Search Along Route parameters are invalid.',
      400,
      requestId,
    );
  }

  const input: SearchAlongRouteInput = {
    textQuery,
    encodedPolyline,
    travelMode,
    modifiers,
    maxResults,
  };

  const places = await provider.searchAlongRoute(input);
  return jsonResponse({ places }, 200, requestId);
}

async function trafficIncidents(
  body: Record<string, unknown>,
  requestId: string,
  provider: TrafficIncidentProvider,
): Promise<Response> {
  const encodedPolyline = requiredString(body.encodedPolyline, 1, 20000);
  const maxResults = optionalPositiveInteger(
    body.maxResults,
    MAX_TRAFFIC_INCIDENTS,
    50,
  );

  if (encodedPolyline == null || maxResults == null) {
    return errorResponse(
      'invalid_maps_request',
      'Traffic lookup requires a valid route polyline and result limit.',
      400,
      requestId,
    );
  }

  const input: TrafficIncidentInput = {
    encodedPolyline,
    maxResults,
  };
  const incidents = await provider.incidentsAlongRoute(input);
  return jsonResponse({ incidents }, 200, requestId);
}

function invalidRoute(requestId: string): Response {
  return errorResponse(
    'invalid_maps_request',
    'Route origin, destination, travel mode, modifiers, or stops are invalid.',
    400,
    requestId,
  );
}

function point(value: unknown): GeoPoint | null {
  if (!isRecord(value)) {
    return null;
  }
  const latitude = value.latitude;
  const longitude = value.longitude;
  if (
    typeof latitude !== 'number' ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    typeof longitude !== 'number' ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }
  return { latitude, longitude };
}

function routeTravelMode(value: unknown): RouteTravelMode | null {
  return value === 'drive' || value === 'two_wheeler' ? value : null;
}

function routeModifiers(value: unknown): RouteModifiers | null {
  if (value == null) {
    return {
      avoidTolls: false,
      avoidHighways: false,
      avoidFerries: false,
    };
  }
  if (!isRecord(value)) {
    return null;
  }
  return {
    avoidTolls: value.avoidTolls === true,
    avoidHighways: value.avoidHighways === true,
    avoidFerries: value.avoidFerries === true,
  };
}

function requiredString(
  value: unknown,
  minLength: number,
  maxLength: number,
): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const normalized = value.trim();
  return normalized.length >= minLength && normalized.length <= maxLength
    ? normalized
    : null;
}

function optionalString(
  value: unknown,
  maxLength: number,
): string | null | undefined {
  if (value == null) {
    return null;
  }
  if (typeof value !== 'string') {
    return undefined;
  }
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maxLength) {
    return undefined;
  }
  return normalized;
}

function optionalPositiveInteger(
  value: unknown,
  max: number,
  fallback: number,
): number | null {
  if (value == null) {
    return fallback;
  }
  return typeof value === 'number' &&
    Number.isInteger(value) &&
    value >= 1 &&
    value <= max
    ? value
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
