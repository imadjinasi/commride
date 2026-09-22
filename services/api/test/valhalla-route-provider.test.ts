import { describe, expect, it } from 'vitest';
import type { GeoPoint } from '../src/maps/models';
import { decodePolyline } from '../src/maps/route-geometry';
import { ValhallaRouteProvider } from '../src/maps/valhalla-route-provider';

const origin: GeoPoint = { latitude: -6.732, longitude: 108.552 };
const middle: GeoPoint = { latitude: -6.8, longitude: 108.2 };
const destination: GeoPoint = { latitude: -6.917, longitude: 107.619 };

function json(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'content-type': 'application/json' },
  });
}

describe('ValhallaRouteProvider', () => {
  it('uses motorcycle costing and normalizes polyline6 plus maneuvers', async () => {
    const shape = encode6([origin, middle, destination]);
    const provider = new ValhallaRouteProvider(
      'https://valhalla.example/commride/',
      async (request, init) => {
        expect(request.toString()).toBe(
          'https://valhalla.example/commride/route',
        );
        const payload = JSON.parse(String(init?.body));
        expect(payload).toMatchObject({
          costing: 'motorcycle',
          units: 'kilometers',
          alternates: 2,
          costing_options: {
            motorcycle: {
              use_highways: 1,
              use_tolls: 0,
              use_ferry: 1,
            },
          },
        });
        return json({
          trip: {
            summary: { length: 100, time: 7200 },
            legs: [{
              summary: { length: 100, time: 7200 },
              shape,
              maneuvers: [{
                type: 10,
                instruction: 'Turn right onto Jalan Contoh.',
                length: 0.4,
                time: 40,
                begin_shape_index: 1,
                end_shape_index: 2,
                verbal_pre_transition_instruction:
                  'In 400 meters, turn right.',
                verbal_transition_alert_instruction: 'Turn right.',
              }],
            }],
          },
        });
      },
    );

    const routes = await provider.computeRoutes({
      origin,
      destination,
      intermediates: [],
      travelMode: 'two_wheeler',
      computeAlternatives: true,
      modifiers: {
        avoidTolls: true,
        avoidHighways: false,
        avoidFerries: false,
      },
    });

    expect(routes).toHaveLength(1);
    expect(routes[0]).toMatchObject({
      distanceMeters: 100000,
      durationSeconds: 7200,
      routeToken: null,
    });
    expect(routes[0]!.maneuvers).toHaveLength(1);
    expect(routes[0]!.maneuvers?.[0]).toMatchObject({
      instruction: 'Turn right onto Jalan Contoh.',
      beginShapeIndex: 1,
      endShapeIndex: 2,
    });
    expect(decodePolyline(routes[0]!.encodedPolyline)).toHaveLength(3);
  });

  it('offsets maneuver indexes across multiple legs', async () => {
    const stop: GeoPoint = { latitude: -6.80, longitude: 108.20 };
    const beforeStop: GeoPoint = { latitude: -6.77, longitude: 108.35 };
    const afterStop: GeoPoint = { latitude: -6.86, longitude: 107.90 };
    const provider = new ValhallaRouteProvider(
      'https://valhalla.example/',
      async () => json({
        trip: {
          summary: { length: 100, time: 7200 },
          legs: [
            {
              summary: { length: 50, time: 3600 },
              shape: encode6([origin, beforeStop, stop]),
              maneuvers: [{
                type: 1,
                instruction: 'Reach stop.',
                length: 1,
                time: 60,
                begin_shape_index: 1,
                end_shape_index: 2,
              }],
            },
            {
              summary: { length: 50, time: 3600 },
              shape: encode6([stop, afterStop, destination]),
              maneuvers: [{
                type: 10,
                instruction: 'Continue after stop.',
                length: 1,
                time: 60,
                begin_shape_index: 1,
                end_shape_index: 2,
              }],
            },
          ],
        },
      }),
    );

    const [route] = await provider.computeRoutes({
      origin,
      destination,
      intermediates: [{ location: stop, via: false }],
      travelMode: 'two_wheeler',
      computeAlternatives: false,
      modifiers: {
        avoidTolls: false,
        avoidHighways: false,
        avoidFerries: false,
      },
    });

    expect(route?.maneuvers).toMatchObject([
      { instruction: 'Reach stop.', beginShapeIndex: 1, endShapeIndex: 2 },
      { instruction: 'Continue after stop.', beginShapeIndex: 3, endShapeIndex: 4 },
    ]);
    expect(decodePolyline(route!.encodedPolyline)).toHaveLength(5);
  });

  it('rejects credential-bearing or non-HTTPS base URLs', () => {
    expect(() => new ValhallaRouteProvider('http://example.test'))
      .toThrow();
    expect(() => new ValhallaRouteProvider(
      'https://user:secret@example.test/',
    )).toThrow();
  });
});

function encode6(points: readonly GeoPoint[]): string {
  let lat = 0;
  let lon = 0;
  let result = '';

  for (const point of points) {
    const nextLat = Math.round(point.latitude * 1e6);
    const nextLon = Math.round(point.longitude * 1e6);
    result += signed(nextLat - lat) + signed(nextLon - lon);
    lat = nextLat;
    lon = nextLon;
  }
  return result;
}

function signed(value: number): string {
  let n = value < 0 ? -value * 2 - 1 : value * 2;
  let part = '';
  while (n >= 32) {
    part += String.fromCharCode((n % 32) + 95);
    n = Math.floor(n / 32);
  }
  return part + String.fromCharCode(n + 63);
}
