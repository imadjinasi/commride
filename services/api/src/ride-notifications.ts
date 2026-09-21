import type { Env } from './env';
import type { Ride } from './clubs-rides/models';
import type { RidePushNotifier } from './push/notifier';
import { resolveRidePushNotifier } from './push/runtime';

const RIDE_REMINDER_WINDOW_MS = 60 * 60 * 1000;

interface UpcomingRideRow {
  readonly id: string;
  readonly title: string;
  readonly scheduled_start_at: string;
}

export async function notifyRideRecapAvailableBestEffort(
  ride: Ride,
  notifier: RidePushNotifier | null | undefined,
): Promise<void> {
  if (
    notifier == null ||
    ride.status !== 'completed' ||
    ride.endedAt == null
  ) {
    return;
  }

  try {
    await notifier.notify({
      eventKey: `ride-recap:${ride.id}:${ride.endedAt}`,
      rideId: ride.id,
      kind: 'ride_recap_available',
      title: 'Ride Recap tersedia',
      body: `${ride.title}: ringkasan Ride sudah siap dilihat.`,
      data: {
        type: 'ride.recap_available',
        rideId: ride.id,
        endedAt: ride.endedAt,
      },
    });
  } catch {
    // Completed Ride state remains authoritative.
  }
}

export async function sendUpcomingRideReminders(
  env: Env,
  now: Date = new Date(),
  notifier: RidePushNotifier | null = resolveRidePushNotifier(env),
): Promise<number> {
  const database = env.DB;
  if (database == null || notifier == null) {
    return 0;
  }

  const startAt = now.toISOString();
  const endAt = new Date(
    now.getTime() + RIDE_REMINDER_WINDOW_MS,
  ).toISOString();

  const rows = await database
    .prepare(
      `
      SELECT id, title, scheduled_start_at
      FROM rides
      WHERE
        status = 'published'
        AND scheduled_start_at IS NOT NULL
        AND scheduled_start_at > ?
        AND scheduled_start_at <= ?
      ORDER BY scheduled_start_at, id
      `,
    )
    .bind(startAt, endAt)
    .all<UpcomingRideRow>();

  let attempted = 0;
  for (const ride of rows.results) {
    attempted += 1;
    try {
      await notifier.notify({
        eventKey:
          `ride-reminder:${ride.id}:${ride.scheduled_start_at}`,
        rideId: ride.id,
        kind: 'ride_reminder',
        title: 'Ride sebentar lagi',
        body:
          `${ride.title} dijadwalkan mulai dalam kurang dari 60 menit.`,
        data: {
          type: 'ride.reminder',
          rideId: ride.id,
          scheduledStartAt: ride.scheduled_start_at,
        },
      });
    } catch {
      // Reminder fan-out is never authoritative for Ride state.
    }
  }

  return attempted;
}
