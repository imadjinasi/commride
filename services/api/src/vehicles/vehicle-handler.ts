import { authenticateRider } from '../auth/authenticated-rider';
import type { IdentityVerifier } from '../auth/identity';
import { errorResponse, jsonResponse } from '../http/json';
import type { RiderRepository } from '../riders/rider-repository';
import type {
  VehicleKind,
  VehicleProfileInput,
} from './vehicle-profile';
import type { VehicleRepository } from './vehicle-repository';

export interface VehicleHandlerDependencies {
  readonly identityVerifier: IdentityVerifier;
  readonly riderRepository: RiderRepository;
  readonly vehicleRepository: VehicleRepository;
  readonly idFactory?: () => string;
}

export function isVehicleRequestPath(pathname: string): boolean {
  return matchVehiclePath(pathname) != null;
}

export async function handleVehicleRequest(
  request: Request,
  url: URL,
  requestId: string,
  dependencies: VehicleHandlerDependencies,
): Promise<Response | null> {
  const route = matchVehiclePath(url.pathname);
  if (route == null) {
    return null;
  }

  const authentication = await authenticateRider(
    request,
    dependencies.identityVerifier,
    dependencies.riderRepository,
  );
  if ('error' in authentication) {
    return errorResponse(
      authentication.error,
      authentication.message,
      authentication.status,
      requestId,
    );
  }

  const rider = authentication.rider;

  if (route.kind === 'collection') {
    if (request.method === 'GET') {
      const vehicles = await dependencies.vehicleRepository.listByRider(
        rider.id,
      );
      return jsonResponse({ vehicles }, 200, requestId);
    }

    if (request.method === 'POST') {
      const inputResult = await readVehicleInput(request);
      if ('error' in inputResult) {
        return errorResponse(
          'invalid_vehicle',
          inputResult.error,
          400,
          requestId,
        );
      }

      const vehicle = await dependencies.vehicleRepository.create(
        dependencies.idFactory?.() ?? crypto.randomUUID(),
        rider.id,
        inputResult.value,
      );
      return jsonResponse({ vehicle }, 201, requestId);
    }

    return errorResponse(
      'method_not_allowed',
      'Only GET and POST are supported for this endpoint.',
      405,
      requestId,
    );
  }

  if (request.method === 'PUT') {
    const inputResult = await readVehicleInput(request);
    if ('error' in inputResult) {
      return errorResponse(
        'invalid_vehicle',
        inputResult.error,
        400,
        requestId,
      );
    }

    const vehicle = await dependencies.vehicleRepository.updateOwned(
      route.vehicleId,
      rider.id,
      inputResult.value,
    );
    if (vehicle == null) {
      return errorResponse(
        'vehicle_not_found',
        'The Vehicle does not exist or is not owned by this Rider.',
        404,
        requestId,
      );
    }

    return jsonResponse({ vehicle }, 200, requestId);
  }

  if (request.method === 'DELETE') {
    const deleted = await dependencies.vehicleRepository.deleteOwned(
      route.vehicleId,
      rider.id,
    );
    if (!deleted) {
      return errorResponse(
        'vehicle_not_found',
        'The Vehicle does not exist or is not owned by this Rider.',
        404,
        requestId,
      );
    }

    return new Response(null, {
      status: 204,
      headers: {
        'cache-control': 'no-store',
        'x-request-id': requestId,
      },
    });
  }

  return errorResponse(
    'method_not_allowed',
    'Only PUT and DELETE are supported for this endpoint.',
    405,
    requestId,
  );
}

async function readVehicleInput(
  request: Request,
): Promise<{ value: VehicleProfileInput } | { error: string }> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { error: 'Request body must be valid JSON.' };
  }

  if (typeof body !== 'object' || body == null || Array.isArray(body)) {
    return { error: 'Request body must be a JSON object.' };
  }

  const input = body as Record<string, unknown>;
  const kind = readKind(input.kind);
  if (kind == null) {
    return { error: 'kind must be motorcycle, car, or other.' };
  }

  const make = optionalString(input.make, 80);
  const model = optionalString(input.model, 80);
  const nickname = optionalString(input.nickname, 80);
  const fuelType = optionalString(input.fuelType, 40);

  if (
    make === undefined ||
    model === undefined ||
    nickname === undefined ||
    fuelType === undefined
  ) {
    return {
      error: 'Vehicle text fields exceed the supported length or are invalid.',
    };
  }

  const safeRangeResult = optionalSafeRange(input.safeRangeKm);
  if ('error' in safeRangeResult) {
    return safeRangeResult;
  }

  return {
    value: {
      kind,
      make,
      model,
      nickname,
      fuelType,
      safeRangeKm: safeRangeResult.value,
    },
  };
}

function readKind(value: unknown): VehicleKind | null {
  if (value === 'motorcycle' || value === 'car' || value === 'other') {
    return value;
  }

  return null;
}

function optionalString(
  value: unknown,
  maxLength: number,
): string | null | undefined {
  if (value == null) {
    return null;
  }

  if (typeof value !== 'string') {
    return undefined;
  }

  const normalized = value.trim();
  if (normalized.length === 0) {
    return null;
  }

  if (normalized.length > maxLength) {
    return undefined;
  }

  return normalized;
}

function optionalSafeRange(
  value: unknown,
): { value: number | null } | { error: string } {
  if (value == null) {
    return { value: null };
  }

  if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value <= 0 ||
    value > 2000
  ) {
    return {
      error: 'safeRangeKm must be an integer between 1 and 2000, or null.',
    };
  }

  return { value };
}

type VehicleRoute =
  | { readonly kind: 'collection' }
  | { readonly kind: 'vehicle'; readonly vehicleId: string };

function matchVehiclePath(pathname: string): VehicleRoute | null {
  if (pathname === '/v1/me/vehicles') {
    return { kind: 'collection' };
  }

  const match = /^\/v1\/me\/vehicles\/([^/]+)$/.exec(pathname);
  if (match?.[1] == null) {
    return null;
  }

  return {
    kind: 'vehicle',
    vehicleId: decodeURIComponent(match[1]),
  };
}
