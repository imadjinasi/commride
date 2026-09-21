import type {
  VehicleProfile,
  VehicleProfileInput,
} from './vehicle-profile';

export interface VehicleRepository {
  listByRider(riderId: string): Promise<VehicleProfile[]>;

  create(
    vehicleId: string,
    riderId: string,
    input: VehicleProfileInput,
  ): Promise<VehicleProfile>;

  updateOwned(
    vehicleId: string,
    riderId: string,
    input: VehicleProfileInput,
  ): Promise<VehicleProfile | null>;

  deleteOwned(vehicleId: string, riderId: string): Promise<boolean>;
}

interface VehicleRow {
  readonly id: string;
  readonly rider_id: string;
  readonly kind: 'motorcycle' | 'car' | 'other';
  readonly make: string | null;
  readonly model: string | null;
  readonly nickname: string | null;
  readonly fuel_type: string | null;
  readonly safe_range_km: number | null;
  readonly created_at: string;
  readonly updated_at: string;
}

export class D1VehicleRepository implements VehicleRepository {
  constructor(private readonly database: D1Database) {}

  async listByRider(riderId: string): Promise<VehicleProfile[]> {
    const result = await this.database
      .prepare(
        `
        SELECT
          id,
          rider_id,
          kind,
          make,
          model,
          nickname,
          fuel_type,
          safe_range_km,
          created_at,
          updated_at
        FROM vehicles
        WHERE rider_id = ?
        ORDER BY created_at, id
        `,
      )
      .bind(riderId)
      .all<VehicleRow>();

    return result.results.map(mapVehicleRow);
  }

  async create(
    vehicleId: string,
    riderId: string,
    input: VehicleProfileInput,
  ): Promise<VehicleProfile> {
    await this.database
      .prepare(
        `
        INSERT INTO vehicles(
          id,
          rider_id,
          kind,
          make,
          model,
          nickname,
          fuel_type,
          safe_range_km
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `,
      )
      .bind(
        vehicleId,
        riderId,
        input.kind,
        input.make,
        input.model,
        input.nickname,
        input.fuelType,
        input.safeRangeKm,
      )
      .run();

    const vehicle = await this.findOwned(vehicleId, riderId);
    if (vehicle == null) {
      throw new Error('Vehicle was not persisted.');
    }

    return vehicle;
  }

  async updateOwned(
    vehicleId: string,
    riderId: string,
    input: VehicleProfileInput,
  ): Promise<VehicleProfile | null> {
    await this.database
      .prepare(
        `
        UPDATE vehicles
        SET
          kind = ?,
          make = ?,
          model = ?,
          nickname = ?,
          fuel_type = ?,
          safe_range_km = ?,
          updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE id = ? AND rider_id = ?
        `,
      )
      .bind(
        input.kind,
        input.make,
        input.model,
        input.nickname,
        input.fuelType,
        input.safeRangeKm,
        vehicleId,
        riderId,
      )
      .run();

    return this.findOwned(vehicleId, riderId);
  }

  async deleteOwned(vehicleId: string, riderId: string): Promise<boolean> {
    const existing = await this.findOwned(vehicleId, riderId);
    if (existing == null) {
      return false;
    }

    await this.database
      .prepare('DELETE FROM vehicles WHERE id = ? AND rider_id = ?')
      .bind(vehicleId, riderId)
      .run();

    return true;
  }

  private async findOwned(
    vehicleId: string,
    riderId: string,
  ): Promise<VehicleProfile | null> {
    const row = await this.database
      .prepare(
        `
        SELECT
          id,
          rider_id,
          kind,
          make,
          model,
          nickname,
          fuel_type,
          safe_range_km,
          created_at,
          updated_at
        FROM vehicles
        WHERE id = ? AND rider_id = ?
        LIMIT 1
        `,
      )
      .bind(vehicleId, riderId)
      .first<VehicleRow>();

    return row == null ? null : mapVehicleRow(row);
  }
}

function mapVehicleRow(row: VehicleRow): VehicleProfile {
  return {
    id: row.id,
    riderId: row.rider_id,
    kind: row.kind,
    make: row.make,
    model: row.model,
    nickname: row.nickname,
    fuelType: row.fuel_type,
    safeRangeKm: row.safe_range_km,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
