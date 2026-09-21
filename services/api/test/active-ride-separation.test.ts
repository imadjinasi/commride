import { describe, expect, it } from 'vitest';

import {
  DEFAULT_CONVOY_SEPARATION_POLICY,
  evaluateConvoySeparation,
  haversineDistanceMeters,
  separationStateMeaningfullyChanged,
  type ConvoySeparationState,
} from '../src/active-ride/separation';
import type { StoredPresence } from '../src/active-ride/protocol';

const baseTime = new Date('2026-09-18T10:00:00Z');

function presence(
  riderId: string,
  latitude: number,
  longitude: number,
  options: Partial<StoredPresence> = {},
): StoredPresence {
  return {
    riderId,
    displayName: riderId,
    role: 'member',
    latitude,
    longitude,
    observedAt: '2026-09-18T09:59:55Z',
    receivedAt: '2026-09-18T09:59:56Z',
    movement: 'moving',
    connected: true,
    ...options,
  };
}

function at(seconds: number): Date {
  return new Date(baseTime.valueOf() + seconds * 1000);
}

describe('Convoy separation engine', () => {
  it('keeps a stretched convoy normal when Riders bridge the chain', () => {
    const state = evaluateConvoySeparation(
      null,
      [
        presence('leader', -6.7320, 108.5520, { role: 'leader' }),
        presence('member-a', -6.7293, 108.5520),
        presence('member-b', -6.7266, 108.5520),
        presence('sweeper', -6.7239, 108.5520, { role: 'sweeper' }),
      ],
      baseTime,
    );

    expect(state.phase).toBe('normal');
    expect(state.components).toEqual([
      ['leader', 'member-a', 'member-b', 'sweeper'],
    ]);
    expect(state.sweeperComponentRiderIds).toEqual([
      'leader',
      'member-a',
      'member-b',
      'sweeper',
    ]);
  });

  it('detects an isolated Rider only as a candidate on first observation', () => {
    const state = evaluateConvoySeparation(
      null,
      [
        presence('leader', -6.7320, 108.5520, { role: 'leader' }),
        presence('member', -6.7300, 108.5520),
        presence('isolated', -6.7150, 108.5520),
      ],
      baseTime,
    );

    expect(state.phase).toBe('split_candidate');
    expect(state.isolatedRiderIds).toContain('isolated');
    expect(state.confirmedAt).toBeNull();
  });

  it('confirms a continuously split convoy only after debounce', () => {
    const presences = [
      presence('leader', -6.7320, 108.5520, { role: 'leader' }),
      presence('member', -6.7300, 108.5520),
      presence('isolated', -6.7150, 108.5520),
    ];

    const candidate = evaluateConvoySeparation(
      null,
      presences,
      baseTime,
    );
    const early = evaluateConvoySeparation(
      candidate,
      presences.map((item) => ({
        ...item,
        observedAt: '2026-09-18T10:00:05Z',
      })),
      at(10),
    );
    const confirmed = evaluateConvoySeparation(
      early,
      presences.map((item) => ({
        ...item,
        observedAt: '2026-09-18T10:00:19Z',
      })),
      at(20),
    );

    expect(early.phase).toBe('split_candidate');
    expect(confirmed.phase).toBe('separated_attention');
    expect(confirmed.confirmedAt).toBe(at(20).toISOString());
  });

  it('detects front and rear sub-groups, not only isolated Riders', () => {
    const state = evaluateConvoySeparation(
      null,
      [
        presence('front-1', -6.7320, 108.5520),
        presence('front-2', -6.7300, 108.5520),
        presence('rear-1', -6.7150, 108.5520),
        presence('rear-2', -6.7130, 108.5520),
      ],
      baseTime,
    );

    expect(state.phase).toBe('split_candidate');
    expect(state.components).toHaveLength(2);
    expect(state.isolatedRiderIds).toEqual([]);
  });

  it('excludes Stale and Offline Riders instead of converting them to separation', () => {
    const stale = presence('stale', -6.7150, 108.5520, {
      observedAt: '2026-09-18T09:59:00Z',
    });
    const offline = presence('offline', -6.7140, 108.5520, {
      connected: false,
    });

    const state = evaluateConvoySeparation(
      null,
      [
        presence('leader', -6.7320, 108.5520, { role: 'leader' }),
        stale,
        offline,
      ],
      baseTime,
    );

    expect(state.phase).toBe('insufficient_data');
    expect(state.dataSufficient).toBe(false);
    expect(state.components).toEqual([['leader']]);
  });

  it('does not confirm a one-sample GPS split', () => {
    const candidate = evaluateConvoySeparation(
      null,
      [
        presence('leader', -6.7320, 108.5520),
        presence('member', -6.7150, 108.5520),
      ],
      baseTime,
    );

    const recovered = evaluateConvoySeparation(
      candidate,
      [
        presence('leader', -6.7320, 108.5520, {
          observedAt: '2026-09-18T10:00:05Z',
        }),
        presence('member', -6.7300, 108.5520, {
          observedAt: '2026-09-18T10:00:05Z',
        }),
      ],
      at(5),
    );

    expect(candidate.phase).toBe('split_candidate');
    expect(recovered.phase).toBe('normal');
  });

  it('requires sustained recovery before clearing confirmed attention', () => {
    const separated: ConvoySeparationState = {
      phase: 'separated_attention',
      dataSufficient: true,
      components: [['leader'], ['member']],
      isolatedRiderIds: ['leader', 'member'],
      sweeperComponentRiderIds: null,
      firstSplitObservedAt: '2026-09-18T09:59:30.000Z',
      confirmedAt: '2026-09-18T09:59:50.000Z',
      recoveryObservedAt: null,
      lastUpdatedAt: '2026-09-18T09:59:50.000Z',
    };

    const together = [
      presence('leader', -6.7320, 108.5520, {
        observedAt: '2026-09-18T10:00:00Z',
      }),
      presence('member', -6.7300, 108.5520, {
        observedAt: '2026-09-18T10:00:00Z',
      }),
    ];

    const recovery = evaluateConvoySeparation(
      separated,
      together,
      baseTime,
    );
    const tooEarly = evaluateConvoySeparation(
      recovery,
      together.map((item) => ({
        ...item,
        observedAt: '2026-09-18T10:00:10Z',
      })),
      at(10),
    );
    const cleared = evaluateConvoySeparation(
      tooEarly,
      together.map((item) => ({
        ...item,
        observedAt: '2026-09-18T10:00:15Z',
      })),
      at(15),
    );

    expect(recovery.phase).toBe('separated_attention');
    expect(tooEarly.phase).toBe('separated_attention');
    expect(cleared.phase).toBe('normal');
  });

  it('does not claim recovery when confirmed separation loses fresh data', () => {
    const separated: ConvoySeparationState = {
      phase: 'separated_attention',
      dataSufficient: true,
      components: [['leader'], ['member']],
      isolatedRiderIds: ['leader', 'member'],
      sweeperComponentRiderIds: null,
      firstSplitObservedAt: '2026-09-18T09:59:30.000Z',
      confirmedAt: '2026-09-18T09:59:50.000Z',
      recoveryObservedAt: null,
      lastUpdatedAt: '2026-09-18T09:59:50.000Z',
    };

    const state = evaluateConvoySeparation(
      separated,
      [
        presence('leader', -6.7320, 108.5520),
        presence('member', -6.7300, 108.5520, {
          connected: false,
        }),
      ],
      baseTime,
    );

    expect(state.phase).toBe('separated_attention');
    expect(state.dataSufficient).toBe(false);
    expect(state.confirmedAt).toBe(separated.confirmedAt);
  });

  it('is stable regardless of input order', () => {
    const values = [
      presence('c', -6.7150, 108.5520),
      presence('a', -6.7320, 108.5520),
      presence('b', -6.7300, 108.5520),
    ];

    const left = evaluateConvoySeparation(null, values, baseTime);
    const right = evaluateConvoySeparation(
      null,
      [...values].reverse(),
      baseTime,
    );

    expect(left.components).toEqual(right.components);
    expect(left.isolatedRiderIds).toEqual(right.isolatedRiderIds);
  });

  it('ignores lastUpdatedAt-only changes for Durable Object writes', () => {
    const previous: ConvoySeparationState = {
      phase: 'normal',
      dataSufficient: true,
      components: [['leader', 'member']],
      isolatedRiderIds: [],
      sweeperComponentRiderIds: null,
      firstSplitObservedAt: null,
      confirmedAt: null,
      recoveryObservedAt: null,
      lastUpdatedAt: '2026-09-18T10:00:00.000Z',
    };
    const timestampOnly: ConvoySeparationState = {
      ...previous,
      lastUpdatedAt: '2026-09-18T10:00:05.000Z',
    };
    const changed: ConvoySeparationState = {
      ...timestampOnly,
      components: [['leader'], ['member']],
      isolatedRiderIds: ['leader', 'member'],
      phase: 'split_candidate',
      firstSplitObservedAt: '2026-09-18T10:00:05.000Z',
    };

    expect(
      separationStateMeaningfullyChanged(previous, timestampOnly),
    ).toBe(false);
    expect(
      separationStateMeaningfullyChanged(previous, changed),
    ).toBe(true);
    expect(
      separationStateMeaningfullyChanged(null, previous),
    ).toBe(true);
  });

  it('computes Haversine distance independently from map providers', () => {
    const distance = haversineDistanceMeters(
      presence('a', 0, 0),
      presence('b', 0, 0.001),
    );

    expect(distance).toBeGreaterThan(110);
    expect(distance).toBeLessThan(112);
    expect(
      DEFAULT_CONVOY_SEPARATION_POLICY.continuityDistanceMeters,
    ).toBe(600);
  });
});
