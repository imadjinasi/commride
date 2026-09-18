import { describe, expect, it } from 'vitest';

import type {
  AuthenticatedIdentity,
  IdentityVerifier,
} from '../src/auth/identity';
import type {
  RiderProfile,
  UpsertRiderProfileInput,
} from '../src/riders/rider-profile';
import type { RiderRepository } from '../src/riders/rider-repository';
import { handleRequest } from '../src/router';
import type {
  VehicleProfile,
  VehicleProfileInput,
} from '../src/vehicles/vehicle-profile';
import type { VehicleRepository } from '../src/vehicles/vehicle-repository';

const riders: RiderProfile[] = [
  {
    id: 'rider-1',
    authSubject: 'auth-rider-1',
    displayName: 'Rider One',
    callsign: 'Lead',
    homeArea: 'Cirebon',
    createdAt: '2026-09-18T00:00:00Z',
    updatedAt: '2026-09-18T00:00:00Z',
  },
  {
    id: 'rider-2',
    authSubject: 'auth-rider-2',
    displayName: 'Rider Two',
    callsign: 'Sweep',
    homeArea: 'Cirebon',
    createdAt: '2026-09-18T00:00:00Z',
    updatedAt: '2026-09-18T00:00:00Z',
  },
];

class FakeIdentityVerifier implements IdentityVerifier {
  async verify(token: string): Promise<AuthenticatedIdentity> {
    if (token === 'token-1') {
      return { subject: 'auth-rider-1' };
    }
    if (token === 'token-2') {
      return { subject: 'auth-rider-2' };
    }
    throw new Error('Unexpected token.');
  }
}

class FakeRiderRepository implements RiderRepository {
  async findByAuthSubject(subject: string): Promise<RiderProfile | null> {
    return riders.find((rider) => rider.authSubject === subject) ?? null;
  }

  async findById(riderId: string): Promise<RiderProfile | null> {
    return riders.find((rider) => rider.id === riderId) ?? null;
  }

  async upsertProfile(
    _input: UpsertRiderProfileInput,
  ): Promise<RiderProfile> {
    throw new Error('Not used in Vehicle tests.');
  }
}

class MemoryVehicleRepository implements VehicleRepository {
  private readonly vehicles = new Map<string, VehicleProfile>();

  async listByRider(riderId: string): Promise<VehicleProfile[]> {
    return [...this.vehicles.values()].filter(
      (vehicle) => vehicle.riderId === riderId,
    );
  }

  async create(
    vehicleId: string,
    riderId: string,
    input: VehicleProfileInput,
  ): Promise<VehicleProfile> {
    const vehicle = this.makeVehicle(vehicleId, riderId, input);
    this.vehicles.set(vehicleId, vehicle);
    return vehicle;
  }

  async updateOwned(
    vehicleId: string,
    riderId: string,
    input: VehicleProfileInput,
  ): Promise<VehicleProfile | null> {
    const existing = this.vehicles.get(vehicleId);
    if (existing == null || existing.riderId !== riderId) {
      return null;
    }

    const vehicle: VehicleProfile = {
      ...this.makeVehicle(vehicleId, riderId, input),
      createdAt: existing.createdAt,
      updatedAt: '2026-09-18T01:00:00Z',
    };
    this.vehicles.set(vehicleId, vehicle);
    return vehicle;
  }

  async deleteOwned(vehicleId: string, riderId: string): Promise<boolean> {
    const existing = this.vehicles.get(vehicleId);
    if (existing == null || existing.riderId !== riderId) {
      return false;
    }

    return this.vehicles.delete(vehicleId);
  }

  private makeVehicle(
    vehicleId: string,
    riderId: string,
    input: VehicleProfileInput,
  ): VehicleProfile {
    return {
      id: vehicleId,
      riderId,
      kind: input.kind,
      make: input.make,
      model: input.model,
      nickname: input.nickname,
      fuelType: input.fuelType,
      safeRangeKm: input.safeRangeKm,
      createdAt: '2026-09-18T00:00:00Z',
      updatedAt: '2026-09-18T00:00:00Z',
    };
  }
}

function request(
  path: string,
  token: 'token-1' | 'token-2',
  method: string,
  body?: unknown,
): Request {
  return new Request(`https://commride.invalid${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body == null ? {} : { 'content-type': 'application/json' }),
    },
    ...(body == null ? {} : { body: JSON.stringify(body) }),
  });
}

function overrides(repository: VehicleRepository) {
  return {
    identityVerifier: new FakeIdentityVerifier(),
    riderRepository: new FakeRiderRepository(),
    vehicleRepository: repository,
    idFactory: () => 'vehicle-1',
  };
}

describe('Rider Vehicle profile API', () => {
  it('creates and lists only the authenticated Rider vehicles', async () => {
    const repository = new MemoryVehicleRepository();

    const createResponse = await handleRequest(
      request('/v1/me/vehicles', 'token-1', 'POST', {
        kind: 'motorcycle',
        make: 'Honda',
        model: 'CB',
        nickname: 'Daily',
        fuelType: 'gasoline',
        safeRangeKm: 220,
      }),
      {},
      overrides(repository),
    );

    expect(createResponse.status).toBe(201);

    const riderOneList = await handleRequest(
      request('/v1/me/vehicles', 'token-1', 'GET'),
      {},
      overrides(repository),
    );
    const riderOneBody = await riderOneList.json() as {
      vehicles: VehicleProfile[];
    };
    expect(riderOneBody.vehicles).toHaveLength(1);

    const riderTwoList = await handleRequest(
      request('/v1/me/vehicles', 'token-2', 'GET'),
      {},
      overrides(repository),
    );
    const riderTwoBody = await riderTwoList.json() as {
      vehicles: VehicleProfile[];
    };
    expect(riderTwoBody.vehicles).toEqual([]);
  });

  it('prevents another Rider from updating an owned Vehicle', async () => {
    const repository = new MemoryVehicleRepository();
    const deps = overrides(repository);

    await handleRequest(
      request('/v1/me/vehicles', 'token-1', 'POST', {
        kind: 'motorcycle',
        make: 'Honda',
        safeRangeKm: 220,
      }),
      {},
      deps,
    );

    const response = await handleRequest(
      request('/v1/me/vehicles/vehicle-1', 'token-2', 'PUT', {
        kind: 'motorcycle',
        make: 'Changed',
        safeRangeKm: 50,
      }),
      {},
      deps,
    );

    expect(response.status).toBe(404);

    const riderOneList = await handleRequest(
      request('/v1/me/vehicles', 'token-1', 'GET'),
      {},
      deps,
    );
    const body = await riderOneList.json() as {
      vehicles: VehicleProfile[];
    };
    expect(body.vehicles[0]?.make).toBe('Honda');
    expect(body.vehicles[0]?.safeRangeKm).toBe(220);
  });

  it('validates safeRangeKm for future group-aware planning', async () => {
    const repository = new MemoryVehicleRepository();

    const response = await handleRequest(
      request('/v1/me/vehicles', 'token-1', 'POST', {
        kind: 'motorcycle',
        safeRangeKm: 0,
      }),
      {},
      overrides(repository),
    );

    expect(response.status).toBe(400);
  });

  it('allows the owning Rider to delete a Vehicle', async () => {
    const repository = new MemoryVehicleRepository();
    const deps = overrides(repository);

    await handleRequest(
      request('/v1/me/vehicles', 'token-1', 'POST', {
        kind: 'car',
        nickname: 'Support',
      }),
      {},
      deps,
    );

    const deleteResponse = await handleRequest(
      request('/v1/me/vehicles/vehicle-1', 'token-1', 'DELETE'),
      {},
      deps,
    );

    expect(deleteResponse.status).toBe(204);

    const listResponse = await handleRequest(
      request('/v1/me/vehicles', 'token-1', 'GET'),
      {},
      deps,
    );
    const body = await listResponse.json() as {
      vehicles: VehicleProfile[];
    };
    expect(body.vehicles).toEqual([]);
  });
});
