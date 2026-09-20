import { describe, expect, it } from 'vitest';

import type { Env } from '../src/env';
import {
  purgeExpiredOperationalData,
  retentionDays,
} from '../src/retention';

interface CapturedStatement {
  readonly sql: string;
  readonly bindings: unknown[];
}

function fakeDatabase() {
  const captured: CapturedStatement[] = [];

  const database = {
    prepare(sql: string) {
      const statement = {
        sql,
        bindings: [] as unknown[],
        bind(...values: unknown[]) {
          statement.bindings = values;
          captured.push({
            sql: statement.sql,
            bindings: [...statement.bindings],
          });
          return statement;
        },
      };
      return statement;
    },
    async batch() {
      return [
        { meta: { changes: 7 } },
        { meta: { changes: 3 } },
      ];
    },
  } as unknown as D1Database;

  return { database, captured };
}

describe('operational retention', () => {
  it('defaults to a 30-day sample window', () => {
    expect(retentionDays({})).toBe(30);
  });

  it('accepts an explicit bounded retention window', () => {
    expect(
      retentionDays({ LOCATION_SAMPLE_RETENTION_DAYS: '14' }),
    ).toBe(14);
  });

  it('falls back when the configured window is unsafe', () => {
    expect(
      retentionDays({ LOCATION_SAMPLE_RETENTION_DAYS: '0' }),
    ).toBe(30);
    expect(
      retentionDays({ LOCATION_SAMPLE_RETENTION_DAYS: '366' }),
    ).toBe(30);
    expect(
      retentionDays({ LOCATION_SAMPLE_RETENTION_DAYS: '30.5' }),
    ).toBe(30);
  });

  it('purges completed-Ride samples and old push dedupe rows', async () => {
    const { database, captured } = fakeDatabase();
    const env: Env = {
      DB: database,
      LOCATION_SAMPLE_RETENTION_DAYS: '30',
    };

    const result = await purgeExpiredOperationalData(
      env,
      new Date('2026-09-19T00:00:00Z'),
    );

    expect(result).toEqual({
      cutoff: '2026-08-20T00:00:00.000Z',
      locationSamplesDeleted: 7,
      pushEventsDeleted: 3,
    });
    expect(captured).toHaveLength(2);
    expect(captured[0].sql).toContain('DELETE FROM ride_location_samples');
    expect(captured[0].sql).toContain('ended_at IS NOT NULL');
    expect(captured[0].bindings).toEqual([
      '2026-08-20T00:00:00.000Z',
    ]);
    expect(captured[1].sql).toContain(
      'DELETE FROM push_notification_events',
    );
  });
});
