import { describe, expect, it } from 'vitest';

import { realtimeRateLimited } from '../src/active-ride/rate-limit';

describe('Active Ride realtime rate guard', () => {
  it('allows the first event', () => {
    expect(
      realtimeRateLimited(undefined, new Date('2026-09-19T06:00:00Z'), 1000),
    ).toBe(false);
  });

  it('rejects a new event inside the minimum interval', () => {
    expect(
      realtimeRateLimited(
        '2026-09-19T06:00:00.000Z',
        new Date('2026-09-19T06:00:00.500Z'),
        750,
      ),
    ).toBe(true);
  });

  it('accepts the event exactly at the minimum interval', () => {
    expect(
      realtimeRateLimited(
        '2026-09-19T06:00:00.000Z',
        new Date('2026-09-19T06:00:00.750Z'),
        750,
      ),
    ).toBe(false);
  });

  it('fails open for an invalid previous timestamp', () => {
    expect(
      realtimeRateLimited(
        'invalid',
        new Date('2026-09-19T06:00:00Z'),
        750,
      ),
    ).toBe(false);
  });
});
