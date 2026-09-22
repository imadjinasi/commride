import type {
  ComputeRoutesInput,
  GeoPoint,
  RouteManeuver,
  RouteOption,
} from './models';
import {
  type RouteProvider,
  RoutePlaceProviderError,
} from './provider';
import {
  decodePolyline6,
  encodePolyline,
  MAX_POLYLINE_LENGTH,
} from './route-geometry';

const REQUEST_TIMEOUT_MS = 15000;
const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;
const workerFetch: typeof fetch = (input, init) => fetch(input, init);

type JsonObject = Record<string, unknown>;

export class ValhallaRouteProvider implements RouteProvider {
  private readonly baseUrl: URL;

  constructor(
    baseUrl: string,
    private readonly fetcher: typeof fetch = workerFetch,
  ) {
    let parsed: URL;
    try {
      parsed = new URL(baseUrl);
    } catch {
      throw new Error('Valhalla base URL must be a valid HTTPS URL.');
    }
    if (
      parsed.protocol !== 'https:' ||
      parsed.username.length > 0 ||
      parsed.password.length > 0 ||
      parsed.search.length > 0 ||
      parsed.hash.length > 0
    ) {
      throw new Error(
        'Valhalla base URL must be a credential-free HTTPS URL.',
      );
    }
    if (!parsed.pathname.endsWith('/')) {
      parsed.pathname += '/';
    }
    this.baseUrl = parsed;
  }

  async computeRoutes(
    input: ComputeRoutesInput,
  ): Promise<readonly RouteOption[]> {
    const locations = [
      routeLocation(input.origin, 'break'),
      ...input.intermediates.map((waypoint) =>
        routeLocation(
          waypoint.location,
          waypoint.via ? 'through' : 'break',
        )),
      routeLocation(input.destination, 'break'),
    ];
    const costing = input.travelMode === 'two_wheeler'
      ? 'motorcycle'
      : 'auto';

    const body = await this.request({
      locations,
      costing,
      costing_options: {
        [costing]: {
          use_highways: input.modifiers.avoidHighways ? 0 : 1,
          use_tolls: input.modifiers.avoidTolls ? 0 : 1,
          use_ferry: input.modifiers.avoidFerries ? 0 : 1,
        },
      },
      units: 'kilometers',
      alternates: input.computeAlternatives ? 2 : 0,
      directions_options: {
        units: 'kilometers',
        language: 'en-US',
      },
    });

    const primary = object(body.trip);
    const candidates = [
      primary,
      ...array(body.alternates).flatMap((raw) => {
        const item = objectOrNull(raw);
        if (item == null) return [];
        return [objectOrNull(item.trip) ?? item];
      }),
    ];

    return candidates.map((trip, routeIndex) =>
      normalizeTrip(trip, routeIndex));
  }

  private async request(payload: JsonObject): Promise<JsonObject> {
    const url = new URL('route', this.baseUrl);
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new RoutePlaceProviderError(
          'maps_provider_timeout',
          'The route engine timed out. Try again later.',
          504,
        ));
      }, REQUEST_TIMEOUT_MS);
    });

    const operation = async (): Promise<JsonObject> => {
      const response = await this.fetcher(url, {
        method: 'POST',
        redirect: 'manual',
        signal: controller.signal,
        headers: {
          accept: 'application/json',
          'content-type': 'application/json',
        },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        const upstreamStatus = response.status;
        console.warn('valhalla_request_failed', {
          stage: upstreamStatus >= 300 && upstreamStatus < 400
            ? 'redirect'
            : 'http',
          status: upstreamStatus,
        });
        const status = upstreamStatus === 429
          ? 429
          : upstreamStatus >= 400 && upstreamStatus < 500
          ? 400
          : 502;
        throw new RoutePlaceProviderError(
          'maps_provider_error',
          status === 429
            ? 'The route engine quota is temporarily unavailable.'
            : 'The route engine request could not be completed.',
          status,
        );
      }
      return readBoundedJson(response);
    };

    try {
      return await Promise.race([operation(), deadline]);
    } catch (error) {
      if (error instanceof RoutePlaceProviderError) throw error;
      console.warn('valhalla_request_failed', {
        stage: 'network',
        errorName: error instanceof Error ? error.name : 'unknown',
      });
      throw new RoutePlaceProviderError(
        'maps_provider_error',
        'The route engine could not be reached.',
        502,
      );
    } finally {
      clearTimeout(timer);
      controller.abort();
    }
  }
}

function normalizeTrip(trip: JsonObject, routeIndex: number): RouteOption {
  const rawLegs = arrayRequired(trip.legs);
  if (rawLegs.length === 0) throw invalidResponse();

  const routePoints: GeoPoint[] = [];
  const legs: { distanceMeters: number; durationSeconds: number }[] = [];
  const maneuvers: RouteManeuver[] = [];
  for (const raw of rawLegs) {
    const leg = object(raw);
    const summary = object(leg.summary);
    const legPoints = decodePolyline6(requiredText(leg.shape));
    if (legPoints.length < 2) throw invalidResponse();

    const duplicateFirst = routePoints.length > 0 &&
      routePoints.at(-1)!.latitude === legPoints[0]!.latitude &&
      routePoints.at(-1)!.longitude === legPoints[0]!.longitude;
    const legShapeOffset = duplicateFirst
      ? routePoints.length - 1
      : routePoints.length;
    const firstIndex = duplicateFirst ? 1 : 0;
    routePoints.push(...legPoints.slice(firstIndex));

    legs.push({
      distanceMeters: kilometersToMeters(summary.length),
      durationSeconds: integerMetric(summary.time),
    });

    for (const rawManeuver of array(leg.maneuvers)) {
      const maneuver = object(rawManeuver);
      const begin = indexMetric(maneuver.begin_shape_index);
      const end = indexMetric(maneuver.end_shape_index);
      maneuvers.push({
        instruction: requiredText(maneuver.instruction),
        type: numberOrText(maneuver.type),
        distanceMeters: kilometersToMeters(maneuver.length),
        durationSeconds: integerMetric(maneuver.time),
        beginShapeIndex: legShapeOffset + begin,
        endShapeIndex: legShapeOffset + end,
        verbalPreTransitionInstruction:
          optionalText(maneuver.verbal_pre_transition_instruction),
        verbalTransitionInstruction:
          optionalText(maneuver.verbal_transition_alert_instruction) ??
          optionalText(maneuver.verbal_transition_instruction),
        verbalPostTransitionInstruction:
          optionalText(maneuver.verbal_post_transition_instruction),
      });
    }

  }

  const encodedPolyline = encodePolyline(routePoints);
  if (encodedPolyline.length > MAX_POLYLINE_LENGTH) {
    throw new RoutePlaceProviderError(
      'route_geometry_too_large',
      'This route is too detailed for the pilot. Choose a shorter Ride segment.',
      422,
    );
  }

  const summary = object(trip.summary);
  return {
    routeIndex,
    labels: [routeIndex === 0 ? 'RECOMMENDED' : 'ALTERNATIVE'],
    distanceMeters: kilometersToMeters(summary.length),
    durationSeconds: integerMetric(summary.time),
    encodedPolyline,
    routeToken: null,
    legs,
    maneuvers,
  };
}

function routeLocation(point: GeoPoint, type: 'break' | 'through') {
  return { lat: point.latitude, lon: point.longitude, type };
}

async function readBoundedJson(response: Response): Promise<JsonObject> {
  if (response.body == null) throw invalidResponse();
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let length = 0;
  let body = '';
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
  } finally {
    reader.releaseLock();
  }
}

function object(value: unknown): JsonObject {
  const result = objectOrNull(value);
  if (result == null) throw invalidResponse();
  return result;
}

function objectOrNull(value: unknown): JsonObject | null {
  return typeof value === 'object' &&
    value != null &&
    !Array.isArray(value)
    ? value as JsonObject
    : null;
}

function array(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function arrayRequired(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw invalidResponse();
  return value;
}

function requiredText(value: unknown): string {
  const result = optionalText(value);
  if (result == null) throw invalidResponse();
  return result;
}

function optionalText(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : null;
}

function numberOrText(value: unknown): string | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }
  return optionalText(value);
}

function kilometersToMeters(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw invalidResponse();
  }
  return Math.round(value * 1000);
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

function indexMetric(value: unknown): number {
  if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value < 0 ||
    value > Number.MAX_SAFE_INTEGER
  ) {
    throw invalidResponse();
  }
  return value;
}

function invalidResponse(): RoutePlaceProviderError {
  return new RoutePlaceProviderError(
    'provider_invalid_response',
    'The route engine returned an incomplete or invalid response.',
    502,
  );
}
