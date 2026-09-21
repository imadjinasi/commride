import { describe, expect, it } from 'vitest';

import { GoogleMapsPlatformProvider } from '../src/maps/google-maps-platform-provider';
import { RoutePlaceProviderError } from '../src/maps/provider';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

describe('GoogleMapsPlatformProvider', () => {
  it('uses narrow field masks for route computation', async () => {
    let seenUrl = '';
    let seenInit: RequestInit | undefined;

    const fetcher: typeof fetch = async (
      input: RequestInfo | URL,
      init?: RequestInit,
    ) => {
      seenUrl = input.toString();
      seenInit = init;

      return jsonResponse({
        routes: [{
          distanceMeters: 120000,
          duration: '7200s',
          routeLabels: ['DEFAULT_ROUTE'],
          polyline: { encodedPolyline: 'encoded-route' },
          legs: [{
            distanceMeters: 120000,
            duration: '7200s',
          }],
        }],
      });
    };

    const provider = new GoogleMapsPlatformProvider(
      'test-key',
      fetcher,
    );

    const routes = await provider.computeRoutes({
      origin: { latitude: -6.732, longitude: 108.552 },
      destination: { latitude: -6.917, longitude: 107.619 },
      intermediates: [],
      travelMode: 'two_wheeler',
      computeAlternatives: true,
      modifiers: {
        avoidTolls: true,
        avoidHighways: false,
        avoidFerries: true,
      },
    });

    expect(seenUrl).toContain('directions/v2:computeRoutes');
    expect(seenInit?.method).toBe('POST');

    const headers = new Headers(seenInit?.headers);
    expect(headers.get('x-goog-api-key')).toBe('test-key');
    expect(headers.get('x-goog-fieldmask')).toContain(
      'routes.polyline.encodedPolyline',
    );
    expect(headers.get('x-goog-fieldmask')).not.toBe('*');

    const requestBody = JSON.parse(String(seenInit?.body)) as {
      travelMode: string;
      computeAlternativeRoutes: boolean;
      routeModifiers: {
        avoidTolls: boolean;
        avoidFerries: boolean;
      };
    };
    expect(requestBody.travelMode).toBe('TWO_WHEELER');
    expect(requestBody.computeAlternativeRoutes).toBe(true);
    expect(requestBody.routeModifiers.avoidTolls).toBe(true);
    expect(requestBody.routeModifiers.avoidFerries).toBe(true);

    expect(routes).toHaveLength(1);
    expect(routes[0]).toMatchObject({
      distanceMeters: 120000,
      durationSeconds: 7200,
      encodedPolyline: 'encoded-route',
    });
  });

  it('disables provider alternatives once intermediate stops exist', async () => {
    const requestBodies: Record<string, unknown>[] = [];

    const fetcher: typeof fetch = async (
      _input: RequestInfo | URL,
      init?: RequestInit,
    ) => {
      requestBodies.push(
        JSON.parse(String(init?.body)) as Record<string, unknown>,
      );
      return jsonResponse({
        routes: [{
          distanceMeters: 150000,
          duration: '9000s',
          polyline: { encodedPolyline: 'route-with-stop' },
          legs: [
            { distanceMeters: 50000, duration: '3000s' },
            { distanceMeters: 100000, duration: '6000s' },
          ],
        }],
      });
    };

    const provider = new GoogleMapsPlatformProvider('test-key', fetcher);
    await provider.computeRoutes({
      origin: { latitude: -6.732, longitude: 108.552 },
      destination: { latitude: -6.917, longitude: 107.619 },
      intermediates: [{
        location: { latitude: -6.8, longitude: 108.0 },
        via: false,
      }],
      travelMode: 'drive',
      computeAlternatives: true,
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
    });

    expect(requestBodies).toHaveLength(1);
    expect(requestBodies[0]?.computeAlternativeRoutes).toBe(false);
    expect(requestBodies[0]?.intermediates).toHaveLength(1);
  });

  it('maps Search Along Route routing summaries to via-place totals', async () => {
    const fetcher: typeof fetch = async (
      input: RequestInfo | URL,
      init?: RequestInit,
    ) => {
      expect(input.toString()).toContain('places:searchText');

      const requestBody = JSON.parse(String(init?.body)) as {
        textQuery: string;
        maxResultCount: number;
        searchAlongRouteParameters: {
          polyline: { encodedPolyline: string };
        };
        routingParameters: {
          travelMode: string;
        };
      };

      expect(requestBody.textQuery).toBe('fuel station');
      expect(requestBody.maxResultCount).toBe(5);
      expect(
        requestBody.searchAlongRouteParameters.polyline.encodedPolyline,
      ).toBe('encoded-route');
      expect(requestBody.routingParameters.travelMode).toBe('DRIVE');

      return jsonResponse({
        places: [{
          id: 'fuel-1',
          displayName: { text: 'Fuel One' },
          formattedAddress: 'Route Road',
          location: { latitude: -6.8, longitude: 108.0 },
        }],
        routingSummaries: [{
          legs: [
            { distanceMeters: 40000, duration: '1800s' },
            { distanceMeters: 62000, duration: '2700s' },
          ],
        }],
      });
    };

    const provider = new GoogleMapsPlatformProvider('test-key', fetcher);
    const places = await provider.searchAlongRoute({
      textQuery: 'fuel station',
      encodedPolyline: 'encoded-route',
      travelMode: 'drive',
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
      maxResults: 5,
    });

    expect(places).toEqual([{
      reference: 'fuel-1',
      displayName: 'Fuel One',
      formattedAddress: 'Route Road',
      location: { latitude: -6.8, longitude: 108.0 },
      viaPlaceDistanceMeters: 102000,
      viaPlaceDurationSeconds: 4500,
    }]);
  });

  it('fails explicitly instead of faking TWO_WHEELER along-route results', async () => {
    const provider = new GoogleMapsPlatformProvider(
      'test-key',
      async () => {
        throw new Error('fetch must not be called');
      },
    );

    await expect(
      provider.searchAlongRoute({
        textQuery: 'fuel',
        encodedPolyline: 'encoded-route',
        travelMode: 'two_wheeler',
        modifiers: {
          avoidTolls: false,
          avoidHighways: false,
          avoidFerries: false,
        },
        maxResults: 5,
      }),
    ).rejects.toMatchObject({
      code: 'search_along_route_mode_not_supported',
      status: 400,
    });
  });

  it('maps provider failures to a stable CommRide provider error', async () => {
    const provider = new GoogleMapsPlatformProvider(
      'test-key',
      async () => jsonResponse({
        error: { message: 'Quota exceeded.' },
      }, 429),
    );

    await expect(
      provider.autocomplete({ input: 'Cirebon' }),
    ).rejects.toMatchObject({
      code: 'maps_provider_error',
      status: 400,
      message: 'Quota exceeded.',
    });
  });
});
