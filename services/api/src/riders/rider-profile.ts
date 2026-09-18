export interface RiderProfile {
  readonly id: string;
  readonly authSubject: string;
  readonly displayName: string;
  readonly callsign: string | null;
  readonly homeArea: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface UpsertRiderProfileInput {
  readonly newRiderId: string;
  readonly authSubject: string;
  readonly displayName: string;
  readonly callsign: string | null;
  readonly homeArea: string | null;
}
