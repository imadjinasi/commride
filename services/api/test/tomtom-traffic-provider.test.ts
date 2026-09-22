import { describe, expect, it } from 'vitest';
import { encodePolyline } from '../src/maps/route-geometry';
import { TomTomTrafficProvider } from '../src/maps/tomtom-traffic-provider';

describe('TomTomTrafficProvider', () => {
  it('keeps the API key out of the URL and normalizes route-near incidents', async () => {
    const route = [
      { latitude: -6.732, longitude: 108.552 },
      { latitude: -6.8, longitude: 108.2 },
    ];
    const provider = new TomTomTrafficProvider(
      'secret-key',
      async (request, init) => {
        const url = new URL(request.toString());
        expect(url.origin).toBe('https://api.tomtom.com');
        expect(url.pathname).toBe(
          '/maps/orbis/traffic/incidents/details',
        );
        expect(url.searchParams.get('timeValidity')).toBe('present');
        expect(url.toString()).not.toContain('secret-key');

        const headers = new Headers(init?.headers);
        expect(headers.get('TomTom-Api-Key')).toBe('secret-key');
        expect(headers.get('TomTom-Api-Version')).toBe('2');

        return new Response(JSON.stringify({
          incidents: [{
            type: 'Feature',
            properties: {
              id: 'incident-1',
              iconCategory: 'roadWorks',
              magnitudeOfDelay: 'minor',
              events: [{
                description: 'Road works',
                code: 1,
                iconCategory: 'roadWorks',
              }],
              delayInSeconds: 120,
              lengthInMeters: 300,
              probabilityOfOccurrence: 'certain',
              numberOfReports: 3,
            },
            geometry: {
              type: 'Point',
              coordinates: [108.4, -6.76],
            },
          }],
        }));
      },
    );

    const incidents = await provider.incidentsAlongRoute({
      encodedPolyline: encodePolyline(route),
      maxResults: 10,
    });

    expect(incidents).toHaveLength(1);
    expect(incidents[0]).toMatchObject({
      id: 'incident-1',
      category: 'roadWorks',
      description: 'Road works',
      delaySeconds: 120,
    });
  });

  it('rejects malformed route geometry before provider calls', async () => {
    let calls = 0;
    const provider = new TomTomTrafficProvider('secret-key', async () => {
      calls++;
      return new Response('{}');
    });

    await expect(provider.incidentsAlongRoute({
      encodedPolyline: '\u007f',
      maxResults: 10,
    })).rejects.toMatchObject({ code: 'invalid_route_polyline' });
    expect(calls).toBe(0);
  });
});
