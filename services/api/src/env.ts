export interface Env {
  readonly DB?: D1Database;
  readonly ACTIVE_RIDE_ROOM?: DurableObjectNamespace;
  readonly FIREBASE_PROJECT_ID?: string;
  readonly FIREBASE_SERVICE_ACCOUNT_CLIENT_EMAIL?: string;
  readonly FIREBASE_SERVICE_ACCOUNT_PRIVATE_KEY?: string;
  readonly GEOAPIFY_API_KEY?: string;
  readonly GOOGLE_MAPS_API_KEY?: string;
  readonly MAP_PROVIDER?: string;
  readonly LOCATION_SAMPLE_RETENTION_DAYS?: string;
}
