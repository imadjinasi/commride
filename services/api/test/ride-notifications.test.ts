import { describe, expect, it } from 'vitest';

import type { Env } from '../src/env';
import type { Ride } from '../src/clubs-rides/models';
import type { RidePushNotifier } from '../src/push/notifier';
import type { PushDeliveryResult, RidePushMessage } from '../src/push/models';
import {
  notifyRideRecapAvailableBestEffort,
  sendUpcomingRideReminders,
} from '../src/ride-notifications';

class RecordingNotifier implements RidePushNotifier {
  readonly messages: RidePushMessage[] = [];
  fail = false;

  async notify(message: RidePushMessage): Promise<PushDeliveryResult> {
    this.messages.push(message);
    if (this.fail) {
      throw new Error('push unavailable');
    }
    return { delivered: 1, failed: 0 };
  }
}

function completedRide(): Ride {
  return {
    id: 'ride-1',
    clubId: 'club-1',
    createdByRiderId: 'rider-1',
    title: 'Sunday Ride',
    status: 'completed',
    scheduledStartAt: '2026-09-20T08:00:00Z',
    actualStartAt: '2026-09-20T08:05:00Z',
    endedAt: '2026-09-20T11:00:00Z',
    notes: null,
    createdAt: '2026-09-19T00:00:00Z',
    updatedAt: '2026-09-20T11:00:00Z',
  };
}

describe('Ride normal-priority notifications', () => {
  it('uses a stable Recap event key after completion', async () => {
    const notifier = new RecordingNotifier();

    await notifyRideRecapAvailableBestEffort(
      completedRide(),
      notifier,
    );

    expect(notifier.messages).toHaveLength(1);
    expect(notifier.messages[0]).toMatchObject({
      eventKey: 'ride-recap:ride-1:2026-09-20T11:00:00Z',
      rideId: 'ride-1',
      kind: 'ride_recap_available',
      data: {
        type: 'ride.recap_available',
        rideId: 'ride-1',
      },
    });
  });

  it('keeps Recap notification failure non-authoritative', async () => {
    const notifier = new RecordingNotifier();
    notifier.fail = true;

    await expect(
      notifyRideRecapAvailableBestEffort(
        completedRide(),
        notifier,
      ),
    ).resolves.toBeUndefined();
  });

  it('queries only Published Rides inside the next 60 minutes', async () => {
    const captured: {
      sql?: string;
      bindings?: readonly unknown[];
    } = {};
    const database = {
      prepare(sql: string) {
        captured.sql = sql;
        const statement = {
          bind(...bindings: unknown[]) {
            captured.bindings = bindings;
            return statement;
          },
          async all() {
            return {
              results: [
                {
                  id: 'ride-2',
                  title: 'Morning Ride',
                  scheduled_start_at: '2026-09-20T08:45:00.000Z',
                },
              ],
            };
          },
        };
        return statement;
      },
    } as unknown as D1Database;
    const notifier = new RecordingNotifier();
    const env: Env = { DB: database };

    const attempted = await sendUpcomingRideReminders(
      env,
      new Date('2026-09-20T08:00:00Z'),
      notifier,
    );

    expect(attempted).toBe(1);
    expect(captured.sql).toContain("status = 'published'");
    expect(captured.sql).toContain('scheduled_start_at > ?');
    expect(captured.sql).toContain('scheduled_start_at <= ?');
    expect(captured.bindings).toEqual([
      '2026-09-20T08:00:00.000Z',
      '2026-09-20T09:00:00.000Z',
    ]);
    expect(notifier.messages[0]).toMatchObject({
      eventKey:
        'ride-reminder:ride-2:2026-09-20T08:45:00.000Z',
      rideId: 'ride-2',
      kind: 'ride_reminder',
      data: {
        type: 'ride.reminder',
        rideId: 'ride-2',
      },
    });
  });

  it('does nothing when D1 or FCM is not configured', async () => {
    await expect(
      sendUpcomingRideReminders({}, new Date(), null),
    ).resolves.toBe(0);
  });
});
