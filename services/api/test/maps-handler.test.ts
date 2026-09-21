import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type {
  AlongRoutePlace,
  ComputeRoutesInput,
  PlaceSuggestion,
  ResolvedPlace,
  RouteOption,
  SearchAlongRouteInput,
} from '../src/maps/models';
import type {
  PlaceAutocompleteInput,
  ResolvePlaceInput,
  RoutePlaceProvider,
} from '../src/maps/provider';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import { handleRequest } from '../src/router';

const rider: RiderProfile = {
  id: 'rider-1',
  authSubject: 'auth-rider-1',
  displayName: 'Rider One',
  callsign: null,
  homeArea: 'Cirebon',
  createdAt: '2026-09-18T00:00:00Z',
  updatedAt: '2026-09-18T00:00:00Z',
};

class TestIdentityVerifier implements IdentityVerifier {
  async verify(_token: string): Promise<AuthenticatedIdentity> {
    return { subject: rider.authSubject };
  }
}

class TestRiderRepository implements RiderRepository {
  async findByAuthSubject(subject: string): Promise<RiderProfile | null> {
    return subject === rider.authSubject ? rider : null;
  }

  async findById(riderId: string): Promise<RiderProfile | null> {
    return riderId === rider.id ? rider : null;
  }

  async upsertProfile(
    _input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    throw new Error('Not used.');
  }
}

class RecordingProvider implements RoutePlaceProvider {
  computeInput: ComputeRoutesInput | null = null;
  searchInput: SearchAlongRouteInput | null = null;

  async autocomplete(
    _input: PlaceAutocompleteInput,
  ): Promise<readonly PlaceSuggestion[]> {
    return [{ reference: 'place-1', text: 'Cirebon, West Java' }];
  }

  async resolvePlace(
    _input: ResolvePlaceInput,
  ): Promise<ResolvedPlace> {
    return {
      reference: 'place-1',
      formattedAddress: 'Cirebon, West Java, Indonesia',
      location: { latitude: -6.732, longitude: 108.552 },
    };
  }

  async computeRoutes(
    input: ComputeRoutesInput,
  ): Promise<readonly RouteOption[]> {
    this.computeInput = input;
    return [{
      routeIndex: 0,
      labels: ['DEFAULT_ROUTE'],
      distanceMeters: 100000,
      durationSeconds: 7200,
      encodedPolyline: 'encoded-route',
      legs: [{
        distanceMeters: 100000,
        durationSeconds: 7200,
      }],
    }];
  }

  async searchAlongRoute(
    input: SearchAlongRouteInput,
  ): Promise<readonly AlongRoutePlace[]> {
    this.searchInput = input;
    return [{
      reference: 'fuel-1',
      displayName: 'Fuel Stop',
      formattedAddress: 'Route Road',
      location: { latitude: -6.8, longitude: 108.6 },
      viaPlaceDistanceMeters: 102000,
      viaPlaceDurationSeconds: 7380,
    }];
  }
}

function request(path: string, body: unknown): Request {
  return new Request(`https://commride.invalid${path}`, {
    method: 'POST',
    headers: {
      authorization: 'Bearer test-token',
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
}

function overrides(provider: RoutePlaceProvider) {
  return {
    identityVerifier: new TestIdentityVerifier(),
    riderRepository: new TestRiderRepository(),
    routePlaceProvider: provider,
  };
}

describe('maps API', () => {
  it('computes route alternatives before intermediate stops are added', async () => {
    const provider = new RecordingProvider();

    const response = await handleRequest(
      request('/v1/maps/routes', {
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
      }),
      {},
      overrides(provider),
    );

    expect(response.status).toBe(200);
    expect(provider.computeInput).toMatchObject({
      travelMode: 'two_wheeler',
      computeAlternatives: true,
      intermediates: [],
    });
  });

  it('rejects alternatives after an intermediate stop is added', async () => {
    const provider = new RecordingProvider();

    const response = await handleRequest(
      request('/v1/maps/routes', {
        origin: { latitude: -6.732, longitude: 108.552 },
        destination: { latitude: -6.917, longitude: 107.619 },
        intermediates: [{
          location: { latitude: -6.85, longitude: 108.1 },
          via: false,
        }],
        travelMode: 'drive',
        computeAlternatives: true,
      }),
      {},
      overrides(provider),
    );

    expect(response.status).toBe(400);
    expect(provider.computeInput).toBeNull();
  });

  it('caps the MVP at ten intermediate stops', async () => {
    const provider = new RecordingProvider();
    const intermediates = Array.from({ length: 11 }, (_, index) => ({
      location: {
        latitude: -6.7 - index * 0.01,
        longitude: 108.5 - index * 0.01,
      },
      via: false,
    }));

    const response = await handleRequest(
      request('/v1/maps/routes', {
        origin: { latitude: -6.732, longitude: 108.552 },
        destination: { latitude: -6.917, longitude: 107.619 },
        intermediates,
        travelMode: 'drive',
      }),
      {},
      overrides(provider),
    );

    expect(response.status).toBe(400);
    expect(provider.computeInput).toBeNull();
  });

  it('does not fake motorcycle Search Along Route with DRIVE results', async () => {
    const provider = new RecordingProvider();

    const response = await handleRequest(
      request('/v1/maps/search-along-route', {
        textQuery: 'fuel',
        encodedPolyline: 'encoded-route',
        travelMode: 'two_wheeler',
        modifiers: {
          avoidTolls: true,
        },
      }),
      {},
      overrides(provider),
    );

    expect(response.status).toBe(400);
    expect(provider.searchInput).toBeNull();

    const body = await response.json() as {
      error: { code: string };
    };
    expect(body.error.code).toBe('search_along_route_mode_not_supported');
  });

  it('searches along a DRIVE route with a bounded result count', async () => {
    const provider = new RecordingProvider();

    const response = await handleRequest(
      request('/v1/maps/search-along-route', {
        textQuery: 'fuel station',
        encodedPolyline: 'encoded-route',
        travelMode: 'drive',
        maxResults: 6,
      }),
      {},
      overrides(provider),
    );

    expect(response.status).toBe(200);
    expect(provider.searchInput).toMatchObject({
      textQuery: 'fuel station',
      travelMode: 'drive',
      maxResults: 6,
    });
  });
});
