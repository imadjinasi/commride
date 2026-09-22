import type {
  TrafficIncident,
  TrafficIncidentInput,
} from './models';
import type { TrafficIncidentProvider } from './traffic-provider';

const DEFAULT_TTL_SECONDS = 600;
const CACHE_KEY_ORIGIN = 'https://traffic-cache.commride.invalid';

export interface TrafficResponseCache {
  match(request: Request): Promise<Response | undefined>;
  put(request: Request, response: Response): Promise<void>;
}

/**
 * Shares one normalized traffic result across Riders that request the exact
 * same RoutePlan. Cache failures are advisory and never block navigation.
 */
export class CachedTrafficIncidentProvider implements TrafficIncidentProvider {
  constructor(
    private readonly delegate: TrafficIncidentProvider,
    private readonly cache: TrafficResponseCache,
    private readonly ttlSeconds = DEFAULT_TTL_SECONDS,
  ) {
    if (!Number.isInteger(ttlSeconds) || ttlSeconds < 1 || ttlSeconds > 3600) {
      throw new Error('Traffic cache TTL must be between 1 and 3600 seconds.');
    }
  }

  async incidentsAlongRoute(
    input: TrafficIncidentInput,
  ): Promise<readonly TrafficIncident[]> {
    const key = await cacheKey(input);

    try {
      const response = await this.cache.match(key);
      if (response != null && response.ok) {
        const cached = parseCachedIncidents(await response.json());
        if (cached != null) return cached;
      }
    } catch {
      // A cache miss/failure must never turn traffic into a navigation outage.
    }

    const incidents = await this.delegate.incidentsAlongRoute(input);

    try {
      await this.cache.put(
        key,
        new Response(JSON.stringify(incidents), {
          status: 200,
          headers: {
            'content-type': 'application/json',
            'cache-control': `public, max-age=${this.ttlSeconds}`,
          },
        }),
      );
    } catch {
      // Upstream traffic remains usable even if edge cache storage is degraded.
    }

    return incidents;
  }
}

async function cacheKey(input: TrafficIncidentInput): Promise<Request> {
  const bytes = new TextEncoder().encode(
    `${input.maxResults}\n${input.encodedPolyline}`,
  );
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const hash = [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
  return new Request(`${CACHE_KEY_ORIGIN}/v1/${hash}`, { method: 'GET' });
}

function parseCachedIncidents(value: unknown): TrafficIncident[] | null {
  if (!Array.isArray(value)) return null;
  const result: TrafficIncident[] = [];

  for (const raw of value) {
    if (!isRecord(raw) ||
        typeof raw.id !== 'string' ||
        typeof raw.category !== 'string' ||
        !Array.isArray(raw.points)) {
      return null;
    }

    const points = raw.points.flatMap((point) => {
      if (!isRecord(point) ||
          typeof point.latitude !== 'number' ||
          !Number.isFinite(point.latitude) ||
          point.latitude < -90 ||
          point.latitude > 90 ||
          typeof point.longitude !== 'number' ||
          !Number.isFinite(point.longitude) ||
          point.longitude < -180 ||
          point.longitude > 180) {
        return [];
      }
      return [{
        latitude: point.latitude,
        longitude: point.longitude,
      }];
    });
    if (points.length !== raw.points.length) return null;

    result.push({
      id: raw.id,
      category: raw.category,
      magnitudeOfDelay: optionalString(raw.magnitudeOfDelay),
      description: optionalString(raw.description),
      from: optionalString(raw.from),
      to: optionalString(raw.to),
      delaySeconds: optionalInteger(raw.delaySeconds),
      lengthMeters: optionalInteger(raw.lengthMeters),
      startTime: optionalString(raw.startTime),
      endTime: optionalString(raw.endTime),
      probabilityOfOccurrence: optionalString(raw.probabilityOfOccurrence),
      numberOfReports: optionalInteger(raw.numberOfReports),
      lastReportTime: optionalString(raw.lastReportTime),
      points,
    });
  }

  return result;
}

function optionalString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function optionalInteger(value: unknown): number | null {
  return typeof value === 'number' &&
    Number.isInteger(value) &&
    value >= 0
    ? value
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value != null && !Array.isArray(value);
}
