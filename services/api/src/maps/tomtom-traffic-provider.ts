import type {
  GeoPoint,
  TrafficIncident,
  TrafficIncidentInput,
} from './models';
import { RoutePlaceProviderError } from './provider';
import {
  decodePolyline,
  distanceMeters,
  distanceToRoute,
  validPoint,
} from './route-geometry';
import type { TrafficIncidentProvider } from './traffic-provider';

const API_ORIGIN = 'https://api.tomtom.com';
const REQUEST_TIMEOUT_MS = 15000;
const MAX_RESPONSE_BYTES = 3 * 1024 * 1024;
const CORRIDOR_METERS = 5000;
const MAX_WINDOW_ROUTE_METERS = 80000;
const MAX_WINDOWS = 8;
const workerFetch: typeof fetch = (input, init) => fetch(input, init);

type JsonObject = Record<string, unknown>;

export class TomTomTrafficProvider implements TrafficIncidentProvider {
  constructor(
    private readonly apiKey: string,
    private readonly fetcher: typeof fetch = workerFetch,
  ) {
    if (apiKey.trim().length === 0) {
      throw new Error('TomTom API key must not be empty.');
    }
  }

  async incidentsAlongRoute(
    input: TrafficIncidentInput,
  ): Promise<readonly TrafficIncident[]> {
    const route = decodePolyline(input.encodedPolyline);
    if (route.length < 2) {
      throw new RoutePlaceProviderError(
        'invalid_route_polyline',
        'Traffic incidents require a valid route polyline.',
        400,
      );
    }

    const windows = routeWindows(route);
    if (windows.length > MAX_WINDOWS) {
      throw new RoutePlaceProviderError(
        'traffic_route_too_long',
        'Traffic lookup is limited to a 640 km Ride corridor in the pilot.',
        422,
      );
    }

    const results = await Promise.all(
      windows.map((points) => this.windowIncidents(points, route)),
    );
    const unique = new Map<string, TrafficIncident>();
    for (const incident of results.flat()) {
      if (!unique.has(incident.id)) unique.set(incident.id, incident);
    }
    return [...unique.values()].slice(0, input.maxResults);
  }

  private async windowIncidents(
    points: readonly GeoPoint[],
    fullRoute: readonly GeoPoint[],
  ): Promise<readonly TrafficIncident[]> {
    const url = new URL(
      '/maps/orbis/traffic/incidents/details',
      API_ORIGIN,
    );
    url.searchParams.set('apiVersion', '2');
    url.searchParams.set('timeValidity', 'present');
    url.searchParams.set('bbox', boundingBox(points));

    const body = await this.request(url);
    return arrayRequired(body.incidents).flatMap((raw) => {
      const item = objectOrNull(raw);
      const properties = objectOrNull(item?.properties);
      const geometry = objectOrNull(item?.geometry);
      if (item == null || properties == null || geometry == null) return [];

      const id = optionalText(properties.id);
      const category = optionalText(properties.iconCategory);
      const incidentPoints = geometryPoints(geometry);
      if (id == null || category == null || incidentPoints.length === 0) {
        return [];
      }

      const routeDistance = Math.min(
        ...incidentPoints.map((point) =>
          distanceToRoute(point, fullRoute)),
      );
      if (routeDistance > CORRIDOR_METERS) return [];

      const descriptions = array(properties.events).flatMap((event) => {
        const value = objectOrNull(event);
        const description = optionalText(value?.description);
        return description == null ? [] : [description];
      });

      return [{
        id,
        category,
        magnitudeOfDelay: optionalText(properties.magnitudeOfDelay),
        description: descriptions.length === 0
          ? null
          : descriptions.join(' · '),
        from: optionalText(properties.from),
        to: optionalText(properties.to),
        delaySeconds: optionalInteger(properties.delayInSeconds),
        lengthMeters: optionalMetric(properties.lengthInMeters),
        startTime: optionalText(properties.startTime),
        endTime: optionalText(properties.endTime),
        probabilityOfOccurrence:
          optionalText(properties.probabilityOfOccurrence),
        numberOfReports: optionalInteger(properties.numberOfReports),
        lastReportTime: optionalText(properties.lastReportTime),
        points: incidentPoints,
      }];
    });
  }

  private async request(url: URL): Promise<JsonObject> {
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => {
        controller.abort();
        reject(new RoutePlaceProviderError(
          'maps_provider_timeout',
          'The traffic provider timed out. Try again later.',
          504,
        ));
      }, REQUEST_TIMEOUT_MS);
    });

    const operation = async (): Promise<JsonObject> => {
      const response = await this.fetcher(url, {
        redirect: 'manual',
        signal: controller.signal,
        headers: {
          accept: 'application/json',
          'accept-language': 'id-ID,en-GB;q=0.8',
          'TomTom-Api-Key': this.apiKey,
          'TomTom-Api-Version': '2',
          Attributes:
            'incidents(type,geometry(type,coordinates),properties(' +
            'id,iconCategory,magnitudeOfDelay,' +
            'events(description,code,iconCategory),' +
            'startTime,endTime,from,to,lengthInMeters,delayInSeconds,' +
            'roadNumbers,timeValidity,probabilityOfOccurrence,' +
            'numberOfReports,lastReportTime))',
        },
      });

      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        const upstreamStatus = response.status;
        console.warn('tomtom_traffic_request_failed', {
          stage: upstreamStatus >= 300 && upstreamStatus < 400
            ? 'redirect'
            : 'http',
          status: upstreamStatus,
        });
        const status = upstreamStatus === 429
          ? 429
          : upstreamStatus === 401 || upstreamStatus === 403
          ? 503
          : upstreamStatus >= 400 && upstreamStatus < 500
          ? 400
          : 502;
        throw new RoutePlaceProviderError(
          'traffic_provider_error',
          status === 429
            ? 'Traffic data quota is temporarily unavailable.'
            : 'Traffic data could not be loaded.',
          status,
        );
      }
      return readBoundedJson(response);
    };

    try {
      return await Promise.race([operation(), deadline]);
    } catch (error) {
      if (error instanceof RoutePlaceProviderError) throw error;
      console.warn('tomtom_traffic_request_failed', {
        stage: 'network',
        errorName: error instanceof Error ? error.name : 'unknown',
      });
      throw new RoutePlaceProviderError(
        'traffic_provider_error',
        'The traffic provider could not be reached.',
        502,
      );
    } finally {
      clearTimeout(timer);
      controller.abort();
    }
  }
}

function routeWindows(route: readonly GeoPoint[]): GeoPoint[][] {
  const windows: GeoPoint[][] = [[route[0]!]];
  let current = windows[0]!;
  let travelled = 0;

  for (let i = 1; i < route.length; i++) {
    const previous = route[i - 1]!;
    const point = route[i]!;
    travelled += distanceMeters(previous, point);
    current.push(point);

    if (travelled >= MAX_WINDOW_ROUTE_METERS && i < route.length - 1) {
      current = [point];
      windows.push(current);
      travelled = 0;
    }
  }

  return windows;
}

function boundingBox(points: readonly GeoPoint[]): string {
  let minLat = 90;
  let maxLat = -90;
  let minLon = 180;
  let maxLon = -180;

  for (const point of points) {
    minLat = Math.min(minLat, point.latitude);
    maxLat = Math.max(maxLat, point.latitude);
    minLon = Math.min(minLon, point.longitude);
    maxLon = Math.max(maxLon, point.longitude);
  }

  const centerLat = (minLat + maxLat) / 2;
  const latPad = CORRIDOR_METERS / 111320;
  const lonScale = Math.max(
    0.15,
    Math.cos(centerLat * Math.PI / 180),
  );
  const lonPad = CORRIDOR_METERS / (111320 * lonScale);

  return [
    Math.max(-180, minLon - lonPad),
    Math.max(-90, minLat - latPad),
    Math.min(180, maxLon + lonPad),
    Math.min(90, maxLat + latPad),
  ].join(',');
}

function geometryPoints(geometry: JsonObject): GeoPoint[] {
  if (geometry.type === 'Point' && Array.isArray(geometry.coordinates)) {
    const point = validPoint(
      geometry.coordinates[1],
      geometry.coordinates[0],
    );
    return point == null ? [] : [point];
  }

  if (
    geometry.type === 'LineString' &&
    Array.isArray(geometry.coordinates)
  ) {
    return geometry.coordinates.flatMap((raw) => {
      if (!Array.isArray(raw)) return [];
      const point = validPoint(raw[1], raw[0]);
      return point == null ? [] : [point];
    });
  }

  return [];
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

function optionalText(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : null;
}

function optionalInteger(value: unknown): number | null {
  return typeof value === 'number' &&
    Number.isInteger(value) &&
    value >= 0
    ? value
    : null;
}

function optionalMetric(value: unknown): number | null {
  return typeof value === 'number' &&
    Number.isFinite(value) &&
    value >= 0
    ? Math.round(value)
    : null;
}

function invalidResponse(): RoutePlaceProviderError {
  return new RoutePlaceProviderError(
    'provider_invalid_response',
    'The traffic provider returned an incomplete or invalid response.',
    502,
  );
}
