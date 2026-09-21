import { describe, expect, it } from 'vitest';

import { GeoapifyProvider } from '../src/maps/geoapify-provider';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function routeResponse({
  distance,
  time,
  coordinates,
}: {
  distance: number;
  time: number;
  coordinates: number[][][];
}): Response {
  return jsonResponse({
    type: 'FeatureCollection',
    features: [{
      type: 'Feature',
      properties: {
        distance,
        time,
        legs: [{ distance, time }],
      },
      geometry: {
        type: 'MultiLineString',
        coordinates,
      },
    }],
  });
}

describe('GeoapifyProvider', () => {
  it('maps autocomplete results to provider-indepent suggestions', async () => {
    const provider = new GeoapifyProvider('test-key', async (input) => {
      const url = new URL(input.toString());
      expect(url.origin + url.pathname).toBe(
        'https://api.geoapify.com/v1/geocode/autocomplete',
      );
      expect(url.searchParams.get('text')).toBe('Cirebon');
      expect(url.searchParams.get('format')).toBe('json');
      expect(url.searchParams.get('limit')).toBe('8');
      expect(url.searchParams.get('apiKey')).toBe('test-key');
      return jsonResponse({
        results: [{
          place_id: 'cirebon-1',
          formatted: 'Cirebon, West Java, Indonesia',
          lat: -6.732,
          lon: 108.552,
        }],
      });
    });

    await expect(provider.autocomplete({ input: 'Cirebon' })).resolves.toEqual([
      { reference: 'cirebon-1', text: 'Cirebon, West Java, Indonesia' },
    ]);
  });

  it('resolves Geoapify place details to a CommRide place', async () => {
    const provider = new GeoapifyProvider('test-key', async (input) => {
      const url = new URL(input.toString());
      expect(url.pathname).toBe('/v2/place-details');
      expect(url.searchParams.get('id')).toBe('place-1');
      expect(url.searchParams.get('features')).toBe('details');
      return jsonResponse({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          properties: {
            place_id: 'place-1',
            formatted: 'Cirebon, West Java, Indonesia',
            lat: -6.732,
            lon: 108.552,
          },
          geometry: { type: 'Point', coordinates: [108.552, -6.732] },
        }],
      });
    });

    await expect(provider.resolvePlace({ reference: 'place-1' })).resolves.toEqual({
      reference: 'place-1',
      formattedAddress: 'Cirebon, West Java, Indonesia',
      location: { latitude: -6.732, longitude: 108.552 },
    });
  });

  it('uses motorcycle mode for CommRide two_wheeler routing', async () => {
    const provider = new GeoapifyProvider('test-key', async (input) => {
      const url = new URL(input.toString());
      expect(url.pathname).toBe('/v1/routing');
      expect(url.searchParams.get('mode')).toBe('motorcycle');
      expect(url.searchParams.get('type')).toBe('balanced');
      expect(url.searchParams.get('avoid')).toBe('ferries');
      return routeResponse({
        distance: 120000,
        time: 7200,
        coordinates: [[
          [108.552, -6.732],
          [108.1, -6.81],
          [107.619, -6.917],
        ]],
      });
    });

    const routes = await provider.computeRoutes({
      origin: { latitude: -6.732, longitude: 108.552 },
      destination: { latitude: -6.917, longitude: 107.619 },
      intermediates: [],
      travelMode: 'two_wheeler',
      computeAlternatives: false,
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: true,
      },
    });

    expect(routes).toHaveLength(1);
    expect(routes[0]).toMatchObject({
      routeIndex: 0,
      labels: ['RECOMMENDED'],
      distanceMeters: 120000,
      durationSeconds: 7200,
    });
    expect(routes[0]?.encodedPolyline.length).toBeGreaterThan(0);
  });

  it('rejects unsupported motorcycle toll/highway modifiers explicitly', async () => {
    const provider = new GeoapifyProvider('test-key', async () => {
      throw new Error('fetch must not be called');
    });

    await expect(provider.computeRoutes({
      origin: { latitude: -6.732, longitude: 108.552 },
      destination: { latitude: -6.917, longitude: 107.619 },
      intermediates: [],
      travelMode: 'two_wheeler',
      computeAlternatives: false,
      modifiers: {
        avoidTolls: true,
        avoidHighways: false,
        avoidFerries: false,
      },
    })).rejects.toMatchObject({
      code: 'route_modifier_not_supported',
      status: 400,
    });
  });

  it('returns a materially distinct shortest alternative when requested', async () => {
    const seenTypes: string[] = [];
    const provider = new GeoapifyProvider('test-key', async (input) => {
      const url = new URL(input.toString());
      const type = url.searchParams.get('type') ?? '';
      seenTypes.push(type);
      return type === 'short'
        ? routeResponse({
            distance: 96000,
            time: 7600,
            coordinates: [[
              [108.552, -6.732],
              [108.0, -6.95],
              [107.619, -6.917],
            ]],
          })
        : routeResponse({
            distance: 100000,
            time: 7200,
            coordinates: [[
              [108.552, -6.732],
              [108.2, -6.75],
              [107.619, -6.917],
            ]],
          });
    });

    const routes = await provider.computeRoutes({
      origin: { latitude: -6.732, longitude: 108.552 },
      destination: { latitude: -6.917, longitude: 107.619 },
      intermediates: [],
      travelMode: 'drive',
      computeAlternatives: true,
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
    });

    expect(seenTypes.sort()).toEqual(['balanced', 'short']);
    expect(routes).toHaveLength(2);
    expect(routes.map((route) => route.labels[0])).toEqual([
      'RECOMMENDED',
      'SHORTEST',
    ]);
    expect(routes.map((route) => route.routeIndex)).toEqual([0, 1]);
  });

  it('searches a bounded route corridor and deduplicates places for motorcycle rides', async () => {
    let placesRequests = 0;
    const provider = new GeoapifyProvider('test-key', async (input) => {
      const url = new URL(input.toString());
      if (url.pathname === '/v1/routing') {
        return routeResponse({
          distance: 100000,
          time: 7200,
          coordinates: [[
            [108.552, -6.732],
            [108.4, -6.76],
            [108.2, -6.8],
            [108.0, -6.84],
            [107.8, -6.88],
            [107.619, -6.917],
          ]],
        });
      }

      expect(url.pathname).toBe('/v2/places');
      expect(url.searchParams.get('categories')).toBe('service.vehicle.fuel');
      expect(url.searchParams.get('filter')).toContain('circle:');
      placesRequests += 1;
      return jsonResponse({
        type: 'FeatureCollection',
        features: [{
          type: 'Feature',
          properties: {
            place_id: 'fuel-1',
            name: 'Fuel One',
            formatted: 'Route Road',
            lat: -6.8,
            lon: 108.2,
          },
          geometry: { type: 'Point', coordinates: [108.2, -6.8] },
        }],
      });
    });

    const [route] = await provider.computeRoutes({
      origin: { latitude: -6.732, longitude: 108.552 },
      destination: { latitude: -6.917, longitude: 107.619 },
      intermediates: [],
      travelMode: 'two_wheeler',
      computeAlternatives: false,
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
    });

    const results = await provider.searchAlongRoute({
      textQuery: 'fuel station',
      encodedPolyline: route!.encodedPolyline,
      travelMode: 'two_wheeler',
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
      maxResults: 5,
    });

    expect(placesRequests).toBeGreaterThan(0);
    expect(placesRequests).toBeLessThanOrEqual(6);
    expect(results).toEqual([{
      reference: 'fuel-1',
      displayName: 'Fuel One',
      formattedAddress: 'Route Road',
      location: { latitude: -6.8, longitude: 108.2 },
      viaPlaceDistanceMeters: null,
      viaPlaceDurationSeconds: null,
    }]);
  });

  it('uses bounded geocoding search for custom along-route text', async () => {
    const provider = new GeoapifyProvider('test-key', async (input) => {
      const url = new URL(input.toString());
      expect(url.pathname).toBe('/v1/geocode/search');
      expect(url.searchParams.get('text')).toBe('rest area');
      expect(url.searchParams.get('filter')).toContain('circle:');
      return jsonResponse({
        results: [{
          place_id: 'rest-1',
          name: 'Rest Area One',
          formatted: 'Toll Road',
          lat: -6.8,
          lon: 108.2,
        }],
      });
    });

    const results = await provider.searchAlongRoute({
      textQuery: 'rest area',
      encodedPolyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
      travelMode: 'drive',
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
      maxResults: 3,
    });

    expect(results[0]).toMatchObject({
      reference: 'rest-1',
      displayName: 'Rest Area One',
    });
  });

  it('maps provider failures to the stable CommRide error contract', async () => {
    const provider = new GeoapifyProvider(
      'test-key',
      async () => jsonResponse({ message: 'Quota exceeded.' }, 429),
    );

    await expect(provider.autocomplete({ input: 'Cirebon' })).rejects.toMatchObject({
      code: 'maps_provider_error',
      status: 400,
      message: 'Quota exceeded.',
    });
  });
});
