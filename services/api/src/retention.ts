import type { Env } from './env';

const DEFAULT_LOCATION_SAMPLE_RETENTION_DAYS = 30;
const MIN_RETENTION_DAYS = 1;
const MAX_RETENTION_DAYS = 365;

export interface RetentionResult {
  readonly cutoff: string;
  readonly locationSamplesDeleted: number;
  readonly pushEventsDeleted: number;
}

export async function purgeExpiredOperationalData(
  env: Env,
  now: Date = new Date(),
): Promise<RetentionResult> {
  const database = env.DB;
  if (database == null) {
    return {
      cutoff: cutoffIso(now, retentionDays(env)),
      locationSamplesDeleted: 0,
      pushEventsDeleted: 0,
    };
  }

  const cutoff = cutoffIso(now, retentionDays(env));
  const results = await database.batch([
    database
      .prepare(
        `
        DELETE FROM ride_location_samples
        WHERE ride_id IN (
          SELECT id
          FROM rides
          WHERE ended_at IS NOT NULL AND ended_at < ?
        )
        `,
      )
      .bind(cutoff),
    database
      .prepare(
        `
        DELETE FROM push_notification_events
        WHERE created_at < ?
        `,
      )
      .bind(cutoff),
  ]);

  return {
    cutoff,
    locationSamplesDeleted: results[0]?.meta.changes ?? 0,
    pushEventsDeleted: results[1]?.meta.changes ?? 0,
  };
}

export function retentionDays(env: Env): number {
  const raw = env.LOCATION_SAMPLE_RETENTION_DAYS?.trim();
  if (raw == null || raw.length === 0) {
    return DEFAULT_LOCATION_SAMPLE_RETENTION_DAYS;
  }

  const parsed = Number.parseInt(raw, 10);
  if (
    !Number.isInteger(parsed) ||
    String(parsed) !== raw ||
    parsed < MIN_RETENTION_DAYS ||
    parsed > MAX_RETENTION_DAYS
  ) {
    return DEFAULT_LOCATION_SAMPLE_RETENTION_DAYS;
  }

  return parsed;
}

function cutoffIso(now: Date, days: number): string {
  return new Date(now.getTime() - days * 24 * 60 * 60 * 1000).toISOString();
}
