export type VehicleKind = 'motorcycle' | 'car' | 'other';

export interface VehicleProfile {
  readonly id: string;
  readonly riderId: string;
  readonly kind: VehicleKind;
  readonly make: string | null;
  readonly model: string | null;
  readonly nickname: string | null;
  readonly fuelType: string | null;
  readonly safeRangeKm: number | null;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface VehicleProfileInput {
  readonly kind: VehicleKind;
  readonly make: string | null;
  readonly model: string | null;
  readonly nickname: string | null;
  readonly fuelType: string | null;
  readonly safeRangeKm: number | null;
}
