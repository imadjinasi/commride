export interface Env {
  readonly DB?: D1Database;
  readonly ACTIVE_RIDE_ROOM?: DurableObjectNamespace;
  readonly FIREBASE_PROJECT_ID?: string;
  readonly GOOGLE_MAPS_PLATFORM_API_KEY?: string;
}
