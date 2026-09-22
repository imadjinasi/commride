import { describe, expect, it } from 'vitest';
import {
  CachedTrafficIncidentProvider,
  type TrafficResponseCache,
} from '../src/maps/cached-traffic-provider';
import type {
  TrafficIncident,
  TrafficIncidentInput,
} from '../src/maps/models';
import type { TrafficIncidentProvider } from '../src/maps/traffic-provider';

class MemoryCache implements TrafficResponseCache {
  readonly values = new Map<string, Response>();

  async match(request: Request): Promise<Response | undefined> {
    return this.values.get(request.url)?.clone();
  }

  async put(request: Request, response: Response): Promise<void> {
    this.values.set(request.url, response.clone());
  }
}

class RecordingProvider implements TrafficIncidentProvider {
  calls = 0;

  async incidentsAlongRoute(
    _input: TrafficIncidentInput,
  ): Promise<readonly TrafficIncident[]> {
    this.calls++;
    return [{
      id: 'incident-1',
      category: 'roadWorks',
      magnitudeOfDelay: 'minor',
      description: 'Perbaikan jalan',
      from: null,
      to: null,
      delaySeconds: 120,
      lengthMeters: 300,
      startTime: null,
      endTime: null,
      probabilityOfOccurrence: 'certain',
      numberOfReports: 2,
      lastReportTime: null,
      points: [{ latitude: -6.76, longitude: 108.4 }],
    }];
  }
}

describe('CachedTrafficIncidentProvider', () => {
  it('shares the exact RoutePlan traffic result instead of refetching upstream', async () => {
    const upstream = new RecordingProvider();
    const cache = new MemoryCache();
    const provider = new CachedTrafficIncidentProvider(upstream, cache, 600);
    const input = {
      encodedPolyline: 'route-polyline',
      maxResults: 50,
    };

    const first = await provider.incidentsAlongRoute(input);
    const second = await provider.incidentsAlongRoute(input);

    expect(first).toEqual(second);
    expect(upstream.calls).toBe(1);
    expect(cache.values.size).toBe(1);
    const response = [...cache.values.values()][0]!;
    expect(response.headers.get('cache-control')).toBe('public, max-age=600');
  });

  it('separates cache entries when the route request changes', async () => {
    const upstream = new RecordingProvider();
    const provider = new CachedTrafficIncidentProvider(
      upstream,
      new MemoryCache(),
    );

    await provider.incidentsAlongRoute({
      encodedPolyline: 'route-a',
      maxResults: 50,
    });
    await provider.incidentsAlongRoute({
      encodedPolyline: 'route-b',
      maxResults: 50,
    });

    expect(upstream.calls).toBe(2);
  });

  it('falls back to upstream when a cached payload is malformed', async () => {
    const upstream = new RecordingProvider();
    const cache = new MemoryCache();
    const provider = new CachedTrafficIncidentProvider(upstream, cache);
    const input = {
      encodedPolyline: 'route-a',
      maxResults: 50,
    };

    await provider.incidentsAlongRoute(input);
    const key = [...cache.values.keys()][0]!;
    cache.values.set(
      key,
      new Response(JSON.stringify([{ id: 'broken' }]), { status: 200 }),
    );

    const incidents = await provider.incidentsAlongRoute(input);

    expect(incidents).toHaveLength(1);
    expect(upstream.calls).toBe(2);
  });
});
