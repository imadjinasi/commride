import { describe, expect, it } from 'vitest';

import {
  parseClientEvent,
  presenceView,
  quickActionPresenceContext,
  quickActionRaisedPayload,
  shouldAcceptPresence,
  type StoredPresence,
} from '../src/active-ride/protocol';

const now = new Date('2026-09-18T10:00:00Z');

function storedPresence(
  observedAt: string,
  connected = true,
): StoredPresence {
  return {
    riderId: 'rider-1',
    displayName: 'Rider One',
    role: 'member',
    latitude: -6.732,
    longitude: 108.552,
    observedAt,
    receivedAt: '2026-09-18T10:00:00Z',
    movement: 'moving',
    connected,
  };
}

describe('Active Ride protocol', () => {
  it('parses a valid v1 presence update', () => {
    const event = parseClientEvent(
      JSON.stringify({
        v: 1,
        type: 'presence.update',
        eventId: 'event-1',
        sentAt: '2026-09-18T10:00:00Z',
        payload: {
          latitude: -6.732,
          longitude: 108.552,
          observedAt: '2026-09-18T09:59:55Z',
          movement: 'moving',
        },
      }),
      now,
    );

    expect(event).toMatchObject({
      v: 1,
      type: 'presence.update',
      eventId: 'event-1',
      payload: {
        movement: 'moving',
      },
    });
  });

  it('rejects unsupported protocol versions before event handling', () => {
    const event = parseClientEvent(
      JSON.stringify({
        v: 2,
        type: 'presence.update',
        eventId: 'event-1',
        sentAt: '2026-09-18T10:00:00Z',
        payload: {},
      }),
      now,
    );

    expect(event).toEqual({
      code: 'unsupported_protocol_version',
      message: 'Unsupported Active Ride protocol version.',
    });
  });

  it('rejects implausibly old and future presence observations', () => {
    const oldEvent = parseClientEvent(
      JSON.stringify({
        v: 1,
        type: 'presence.update',
        eventId: 'old',
        sentAt: '2026-09-18T10:00:00Z',
        payload: {
          latitude: -6.732,
          longitude: 108.552,
          observedAt: '2026-09-18T09:40:00Z',
          movement: 'moving',
        },
      }),
      now,
    );
    expect(oldEvent).toMatchObject({ code: 'presence_too_old' });

    const futureEvent = parseClientEvent(
      JSON.stringify({
        v: 1,
        type: 'presence.update',
        eventId: 'future',
        sentAt: '2026-09-18T10:00:00Z',
        payload: {
          latitude: -6.732,
          longitude: 108.552,
          observedAt: '2026-09-18T10:03:00Z',
          movement: 'moving',
        },
      }),
      now,
    );
    expect(futureEvent).toMatchObject({ code: 'presence_from_future' });
  });

  it('never lets an older queued observation regress latest presence', () => {
    const current = storedPresence('2026-09-18T09:59:50Z');

    expect(
      shouldAcceptPresence(current, '2026-09-18T09:59:49Z'),
    ).toBe(false);
    expect(
      shouldAcceptPresence(current, '2026-09-18T09:59:50Z'),
    ).toBe(false);
    expect(
      shouldAcceptPresence(current, '2026-09-18T09:59:51Z'),
    ).toBe(true);
  });

  it('derives live, stale, and offline without fabricating freshness', () => {
    expect(
      presenceView(
        storedPresence('2026-09-18T09:59:45Z'),
        now,
      ).freshness,
    ).toBe('live');

    expect(
      presenceView(
        storedPresence('2026-09-18T09:59:00Z'),
        now,
      ).freshness,
    ).toBe('stale');

    expect(
      presenceView(
        storedPresence('2026-09-18T09:59:59Z', false),
        now,
      ).freshness,
    ).toBe('offline');
  });

  it('attaches only server-accepted latest presence to quick actions', () => {
    expect(
      quickActionPresenceContext(
        storedPresence('2026-09-18T09:59:50Z'),
        now,
      ),
    ).toMatchObject({
      riderId: 'rider-1',
      observedAt: '2026-09-18T09:59:50Z',
      freshness: 'live',
    });

    expect(
      quickActionPresenceContext(
        storedPresence('2026-09-18T09:59:00Z'),
        now,
      ),
    ).toMatchObject({
      riderId: 'rider-1',
      observedAt: '2026-09-18T09:59:00Z',
      freshness: 'stale',
    });

    expect(quickActionPresenceContext(undefined, now)).toBeNull();
  });

  it('builds quick-action broadcasts from trusted attachment identity', () => {
    const event = parseClientEvent(
      JSON.stringify({
        v: 1,
        type: 'quick_action.raise',
        eventId: 'quick-trusted',
        sentAt: '2026-09-18T10:00:00Z',
        payload: {
          kind: 'need_help',
          reason: 'Mechanical problem',
          riderId: 'spoofed-rider',
          latitude: 1,
          longitude: 2,
        },
      }),
      now,
    );

    expect('code' in event).toBe(false);
    if ('code' in event || event.type !== 'quick_action.raise') {
      throw new Error('Expected parsed quick action.');
    }

    const payload = quickActionRaisedPayload(
      {
        riderId: 'rider-1',
        displayName: 'Rider One',
        role: 'sweeper',
        lastPresence: storedPresence('2026-09-18T09:59:50Z'),
      },
      event,
      now,
    );

    expect(payload).toMatchObject({
      eventId: 'quick-trusted',
      rider: {
        riderId: 'rider-1',
        displayName: 'Rider One',
        role: 'sweeper',
      },
      kind: 'need_help',
      reason: 'Mechanical problem',
      raisedAt: '2026-09-18T10:00:00.000Z',
      presence: {
        riderId: 'rider-1',
        observedAt: '2026-09-18T09:59:50Z',
        freshness: 'live',
      },
    });
  });

  it('broadcasts quick actions even when no accepted presence exists', () => {
    const event = parseClientEvent(
      JSON.stringify({
        v: 1,
        type: 'quick_action.raise',
        eventId: 'quick-no-location',
        sentAt: '2026-09-18T10:00:00Z',
        payload: {
          kind: 'need_help',
          reason: null,
        },
      }),
      now,
    );

    expect('code' in event).toBe(false);
    if ('code' in event || event.type !== 'quick_action.raise') {
      throw new Error('Expected parsed quick action.');
    }

    expect(
      quickActionRaisedPayload(
        {
          riderId: 'rider-1',
          displayName: 'Rider One',
          role: 'member',
        },
        event,
        now,
      ).presence,
    ).toBeNull();
  });

  it('parses only the supported operational quick actions', () => {
    const event = parseClientEvent(
      JSON.stringify({
        v: 1,
        type: 'quick_action.raise',
        eventId: 'quick-1',
        sentAt: '2026-09-18T10:00:00Z',
        payload: {
          kind: 'left_behind',
          reason: 'Traffic light split',
        },
      }),
      now,
    );

    expect(event).toMatchObject({
      type: 'quick_action.raise',
      payload: {
        kind: 'left_behind',
        reason: 'Traffic light split',
      },
    });
  });
});
