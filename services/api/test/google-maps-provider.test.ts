import { describe, expect, it, vi } from 'vitest';
import { GoogleMapsProvider } from '../src/maps/google-maps-provider';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

describe('GoogleMapsProvider', () => {
  it('uses Places Autocomplete New with a bounded field mask and session token', async () => {
    const provider = new GoogleMapsProvider('secret-key', async (request, init) => {
      const url = new URL(request.toString());
      expect(url.origin).toBe('https://places.googleapis.com');
      expect(url.pathname).toBe('/v1/places:autocomplete');
      const headers = new Headers(init?.headers);
      expect(headers.get('x-goog-api-key')).toBe('secret-key');
      expect(headers.get('x-goog-fieldmask')).toContain(
        'suggestions.placePrediction.placeId',
      );
      expect(JSON.parse(String(init?.body))).toMatchObject({
        input: 'Cirebon',
        sessionToken: 'session-1',
      });
      return json({
        suggestions: [{
          placePrediction: {
            placeId: 'place-1',
            text: { text: 'Cirebon, Jawa Barat' },
          },
        }],
      });
    });

    await expect(provider.autocomplete({
      input: 'Cirebon',
      sessionToken: 'session-1',
    })).resolves.toEqual([
      { reference: 'place-1', text: 'Cirebon, Jawa Barat' },
    ]);
  });

  it('resolves place coordinates without exposing the API key in the URL', async () => {
    const provider = new GoogleMapsProvider('secret-key', async (request, init) => {
      const url = new URL(request.toString());
      expect(url.pathname).toBe('/v1/places/place-1');
      expect(url.searchParams.get('sessionToken')).toBe('session-1');
      expect(url.toString()).not.toContain('secret-key');
      expect(new Headers(init?.headers).get('x-goog-api-key')).toBe('secret-key');
      return json({
        id: 'place-1',
        formattedAddress: 'Cirebon, West Java, Indonesia',
        location: { latitude: -6.732, longitude: 108.552 },
      });
    });

    await expect(provider.resolvePlace({
      reference: 'place-1',
      sessionToken: 'session-1',
    })).resolves.toMatchObject({
      reference: 'place-1',
      location: { latitude: -6.732, longitude: 108.552 },
    });
  });

  it('computes two-wheeler routes with traffic and returns a route token', async () => {
    const provider = new GoogleMapsProvider('secret-key', async (request, init) => {
      const url = new URL(request.toString());
      expect(url.origin).toBe('https://routes.googleapis.com');
      expect(url.pathname).toBe('/directions/v2:computeRoutes');
      const payload = JSON.parse(String(init?.body));
      expect(payload).toMatchObject({
        travelMode: 'TWO_WHEELER',
        routingPreference: 'TRAFFIC_AWARE',
        computeAlternativeRoutes: true,
      });
      expect(new Headers(init?.headers).get('x-goog-fieldmask')).toContain(
        'routes.routeToken',
      );
      return json({
        routes: [{
          routeLabels: ['DEFAULT_ROUTE'],
          distanceMeters: 123000,
          duration: '14400s',
          polyline: { encodedPolyline: 'encoded' },
          routeToken: 'opaque-route-token',
          legs: [{ distanceMeters: 123000, duration: '14400s' }],
        }],
      });
    });

    const routes = await provider.computeRoutes({
      origin: { latitude: -6.732, longitude: 108.552 },
      destination: { latitude: -6.917, longitude: 107.619 },
      intermediates: [],
      travelMode: 'two_wheeler',
      computeAlternatives: true,
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
    });
    expect(routes[0]).toMatchObject({
      distanceMeters: 123000,
      durationSeconds: 14400,
      encodedPolyline: 'encoded',
      routeToken: 'opaque-route-token',
    });
  });

  it('uses native Places search-along-route and exposes route-impact totals', async () => {
    const provider = new GoogleMapsProvider('secret-key', async (request, init) => {
      const url = new URL(request.toString());
      expect(url.pathname).toBe('/v1/places:searchText');
      const payload = JSON.parse(String(init?.body));
      expect(payload.searchAlongRouteParameters.polyline.encodedPolyline)
        .toBe('route-polyline');
      expect(payload.routingParameters.travelMode).toBe('TWO_WHEELER');
      return json({
        places: [{
          id: 'fuel-1',
          displayName: { text: 'SPBU Example' },
          formattedAddress: 'Jalan Contoh',
          location: { latitude: -6.8, longitude: 108.2 },
        }],
        routingSummaries: [{
          legs: [
            { distanceMeters: 10000, duration: '900s' },
            { distanceMeters: 20000, duration: '1800s' },
          ],
        }],
      });
    });

    const places = await provider.searchAlongRoute({
      textQuery: 'fuel station',
      encodedPolyline: 'route-polyline',
      travelMode: 'two_wheeler',
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
      maxResults: 5,
    });
    expect(places[0]).toMatchObject({
      reference: 'fuel-1',
      viaPlaceDistanceMeters: 30000,
      viaPlaceDurationSeconds: 2700,
    });
  });

  it('redacts provider errors and does not retry', async () => {
    const fetcher = vi.fn(async () =>
      json({ error: { message: 'secret-key' } }, 403));
    const provider = new GoogleMapsProvider('secret-key', fetcher);
    const error = await provider.autocomplete({ input: 'Cirebon' })
      .catch((value: unknown) => value);
    expect(error).toMatchObject({ code: 'maps_provider_error', status: 503 });
    expect(String(error)).not.toContain('secret-key');
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
});
