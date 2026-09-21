import { afterEach, describe, expect, it, vi } from 'vitest';
import { GeoapifyProvider } from '../src/maps/geoapify-provider';
import { handleMapsRequest } from '../src/maps/handler';
import type { MapsHandlerDependencies } from '../src/maps/handler';
import type { ComputeRoutesInput, GeoPoint } from '../src/maps/models';
import { decodePolyline, encodePolyline } from '../src/maps/route-geometry';

const origin: GeoPoint = { latitude: -6.732, longitude: 108.552 };
const destination: GeoPoint = { latitude: -6.917, longitude: 107.619 };
const noAvoids = { avoidTolls: false, avoidHighways: false, avoidFerries: false };
const input: ComputeRoutesInput = {
  origin, destination, intermediates: [], travelMode: 'two_wheeler',
  computeAlternatives: false, modifiers: noAvoids,
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}
function route(distance = 100000, time = 7200, middle: GeoPoint = { latitude: -6.8, longitude: 108.2 }): Response {
  return json({ features: [{
    properties: { distance, time, legs: [{ distance, time }] },
    geometry: { type: 'MultiLineString', coordinates: [[origin, middle, destination].map((p) => [p.longitude, p.latitude])] },
  }] });
}

afterEach(() => vi.useRealTimers());

describe('GeoapifyProvider', () => {
  it('normalizes autocomplete and keeps the key only in provider requests', async () => {
    const provider = new GeoapifyProvider('fixture-key', async (request, init) => {
      const url = new URL(request.toString());
      expect(url.origin).toBe('https://api-eu.geoapify.com');
      expect(url.pathname).toBe('/v1/geocode/autocomplete');
      expect(url.searchParams.get('apiKey')).toBe('fixture-key');
      expect(url.searchParams.get('limit')).toBe('8');
      expect(init?.redirect).toBe('manual');
      return json({ results: [{ place_id: 'place-1', formatted: 'Cirebon' }] });
    });
    await expect(provider.autocomplete({ input: 'Cirebon' })).resolves.toEqual([
      { reference: 'place-1', text: 'Cirebon' },
    ]);
  });

  it('resolves provider place details and rejects missing coordinates', async () => {
    const provider = new GeoapifyProvider('fixture', async (request) => {
      const url = new URL(request.toString());
      expect(url.pathname).toBe('/v2/place-details');
      expect(url.searchParams.get('features')).toBe('details');
      return json({ features: [{ properties: {
        place_id: 'place-1', formatted: 'Cirebon', lat: origin.latitude, lon: origin.longitude,
      } }] });
    });
    await expect(provider.resolvePlace({ reference: 'place-1' })).resolves.toMatchObject({ location: origin });
    const malformed = new GeoapifyProvider('fixture', async () => json({ features: [{ properties: { lat: 200, lon: 300 } }] }));
    await expect(malformed.resolvePlace({ reference: 'x' })).rejects.toMatchObject({ code: 'provider_invalid_response', status: 502 });
  });

  it('uses motorcycle, metric routes and precision-five geometry', async () => {
    const provider = new GeoapifyProvider('fixture', async (request) => {
      const url = new URL(request.toString());
      expect(url.searchParams.get('mode')).toBe('motorcycle');
      expect(url.searchParams.get('units')).toBe('metric');
      expect(url.searchParams.get('type')).toBe('balanced');
      expect(url.searchParams.get('avoid')).toBe('ferries');
      return route();
    });
    const result = await provider.computeRoutes({ ...input, modifiers: { ...noAvoids, avoidFerries: true } });
    expect(result[0]).toMatchObject({ labels: ['RECOMMENDED'], distanceMeters: 100000, durationSeconds: 7200 });
    expect(decodePolyline(result[0]!.encodedPolyline)[0]).toEqual(origin);
  });

  it('preserves stopover order and suppresses alternatives with stops', async () => {
    let calls = 0;
    const provider = new GeoapifyProvider('fixture', async (request) => {
      calls++;
      const url = new URL(request.toString());
      expect(url.searchParams.get('intermediate_waypoint_mode')).toBe('stopover');
      expect(url.searchParams.get('waypoints')).toBe(`${origin.latitude},${origin.longitude}|-6.8,108.2|${destination.latitude},${destination.longitude}`);
      return route();
    });
    await provider.computeRoutes({ ...input, computeAlternatives: true, intermediates: [{ location: { latitude: -6.8, longitude: 108.2 }, via: false }] });
    expect(calls).toBe(1);
  });

  it('does not silently ignore unsupported motorcycle or mixed waypoint preferences', async () => {
    const provider = new GeoapifyProvider('fixture', async () => { throw new Error('must not fetch'); });
    await expect(provider.computeRoutes({ ...input, modifiers: { ...noAvoids, avoidTolls: true } })).rejects.toMatchObject({ code: 'route_modifier_not_supported', status: 400 });
    await expect(provider.computeRoutes({ ...input, intermediates: [{ location: origin, via: true }, { location: destination, via: false }] })).rejects.toMatchObject({ code: 'mixed_waypoint_modes_not_supported' });
  });

  it('keeps materially distinct short routes, not duplicate alternatives', async () => {
    const provider = new GeoapifyProvider('fixture', async (request) => {
      return new URL(request.toString()).searchParams.get('type') === 'short'
        ? route(96000, 7600, { latitude: -6.95, longitude: 108.0 }) : route();
    });
    const result = await provider.computeRoutes({ ...input, computeAlternatives: true });
    expect(result.map((r) => [r.routeIndex, r.labels[0]])).toEqual([[0, 'RECOMMENDED'], [1, 'SHORTEST']]);
    const duplicate = new GeoapifyProvider('fixture', async () => route());
    await expect(duplicate.computeRoutes({ ...input, computeAlternatives: true })).resolves.toHaveLength(1);
  });

  it('retains the valid primary route if only the optional alternative fails', async () => {
    const provider = new GeoapifyProvider('fixture', async (request) =>
      new URL(request.toString()).searchParams.get('type') === 'short' ? json({ message: 'private' }, 429) : route());
    await expect(provider.computeRoutes({ ...input, computeAlternatives: true })).resolves.toHaveLength(1);
  });

  it.each(['drive', 'two_wheeler'] as const)('bounds and deduplicates geographic corridor queries for %s', async (travelMode) => {
    let calls = 0;
    const provider = new GeoapifyProvider('fixture', async (request) => {
      calls++;
      const url = new URL(request.toString());
      expect(url.pathname).toBe('/v2/places');
      expect(url.searchParams.get('categories')).toBe('service.vehicle.fuel');
      expect(Number(url.searchParams.get('limit'))).toBeLessThanOrEqual(5);
      const [, lon, lat] = url.searchParams.get('filter')!.split(':').join(',').split(',');
      return json({ features: [
        { properties: { place_id: 'shared', name: 'Fuel', lat: Number(lat), lon: Number(lon) } },
        { properties: { place_id: 'far', name: 'Not along route', lat: 50, lon: -120 } },
      ] });
    });
    const results = await provider.searchAlongRoute({ textQuery: 'fuel station', encodedPolyline: encodePolyline([origin, destination]), travelMode, modifiers: noAvoids, maxResults: 5 });
    expect(calls).toBe(6);
    expect(results).toHaveLength(1);
    expect(results[0]).toMatchObject({ reference: 'shared', viaPlaceDistanceMeters: null, viaPlaceDurationSeconds: null });
  });

  it('uses bounded geocoding for custom text and supports empty valid responses', async () => {
    const provider = new GeoapifyProvider('fixture', async (request) => {
      const url = new URL(request.toString());
      expect(url.pathname).toBe('/v1/geocode/search');
      expect(url.searchParams.get('text')).toBe('rest area');
      expect(url.searchParams.get('filter')).toContain('circle:');
      return json({ results: [] });
    });
    await expect(provider.searchAlongRoute({ textQuery: 'rest area', encodedPolyline: encodePolyline([origin, destination]), travelMode: 'drive', modifiers: noAvoids, maxResults: 3 })).resolves.toEqual([]);
  });

  it('rejects malformed geometry before making paid calls', async () => {
    const fetcher = vi.fn(async () => json({}));
    const provider = new GeoapifyProvider('fixture', fetcher);
    await expect(provider.searchAlongRoute({ textQuery: 'fuel', encodedPolyline: '\u007f', travelMode: 'drive', modifiers: noAvoids, maxResults: 3 })).rejects.toMatchObject({ code: 'invalid_route_polyline' });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it.each([301, 302, 307, 308, 401, 403, 429, 500])('redacts provider errors for upstream status %s', async (status) => {
    const provider = new GeoapifyProvider('hidden-key', async () => json({ message: 'https://api.geoapify.com/?apiKey=hidden-key' }, status));
    const error = await provider.autocomplete({ input: 'Cirebon' }).catch((value: unknown) => value);
    expect(error).toMatchObject({ code: 'maps_provider_error', status: status === 429 ? 429 : status < 500 ? 503 : 502 });
    expect(String(error)).not.toContain('hidden-key');
    expect(String(error)).not.toContain('https://');
  });

  it.each(['not-json', '{}', '[]'])('rejects malformed successful payload %s', async (body) => {
    const provider = new GeoapifyProvider('fixture', async () => new Response(body));
    await expect(provider.autocomplete({ input: 'Cirebon' })).rejects.toMatchObject({ status: 502 });
  });

  it('bounds response size', async () => {
    const provider = new GeoapifyProvider('fixture', async () => new Response(' '.repeat(2 * 1024 * 1024 + 1)));
    await expect(provider.autocomplete({ input: 'Cirebon' })).rejects.toMatchObject({ code: 'provider_invalid_response' });
  });

  it('times out stalled providers without retries', async () => {
    vi.useFakeTimers();
    const fetcher = vi.fn(() => new Promise<Response>(() => {}));
    const provider = new GeoapifyProvider('fixture', fetcher);
    const result = provider.autocomplete({ input: 'Cirebon' });
    const assertion = expect(result).rejects.toMatchObject({ code: 'maps_provider_timeout', status: 504 });
    await vi.advanceTimersByTimeAsync(15001);
    await assertion;
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it('preserves asynchronous provider errors across the HTTP handler', async () => {
    const provider = new GeoapifyProvider('hidden-key', async () => json({ message: 'hidden-key' }, 429));
    const rider = { id: 'rider-1', authSubject: 'subject-1', displayName: 'Rider One', callsign: null, homeArea: null, createdAt: '2026-09-21T00:00:00Z', updatedAt: '2026-09-21T00:00:00Z' };
    const dependencies = {
      provider,
      identityVerifier: { verify: async () => ({ subject: 'subject-1' }) },
      riderRepository: { findByAuthSubject: async () => rider, findById: async () => rider, upsertProfile: async () => rider },
    } satisfies MapsHandlerDependencies;
    const request = new Request('https://commride.invalid/v1/maps/autocomplete', {
      method: 'POST', headers: { authorization: 'Bearer fixture', 'content-type': 'application/json' }, body: JSON.stringify({ input: 'Cirebon' }),
    });
    const response = await handleMapsRequest(request, new URL(request.url), 'request-1', dependencies);
    expect(response?.status).toBe(429);
    expect(await response?.text()).not.toContain('hidden-key');
  });
});
