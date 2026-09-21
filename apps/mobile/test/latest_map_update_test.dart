import 'dart:async';

import 'package:commride_mobile/src/maps/latest_map_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes native writes and coalesces waiting snapshots', () async {
    final Completer<void> firstWrite = Completer<void>();
    final List<int> applied = <int>[];
    final LatestMapUpdate<int> updates = LatestMapUpdate<int>(
      apply: (int value) async {
        applied.add(value);
        if (value == 1) {
          await firstWrite.future;
        }
      },
      onError: () => fail('Unexpected native failure'),
    );
    updates.submit(1);
    updates.submit(2);
    updates.submit(3);
    expect(applied, <int>[1]);
    firstWrite.complete();
    await updates.idle;
    expect(applied, <int>[1, 3]);
  });

  test('disposal drops queued snapshots', () async {
    final Completer<void> firstWrite = Completer<void>();
    final List<int> applied = <int>[];
    final LatestMapUpdate<int> updates = LatestMapUpdate<int>(
      apply: (int value) async {
        applied.add(value);
        await firstWrite.future;
      },
      onError: () => fail('Unexpected native failure'),
    );
    updates.submit(1);
    updates.submit(2);
    updates.dispose();
    firstWrite.complete();
    await updates.idle;
    updates.submit(3);
    expect(applied, <int>[1]);
  });

  test('native failure is handled once and stops further writes', () async {
    int failures = 0;
    int calls = 0;
    final LatestMapUpdate<int> updates = LatestMapUpdate<int>(
      apply: (int value) async {
        calls += 1;
        throw StateError('native failure');
      },
      onError: () {
        failures += 1;
      },
    );
    updates.submit(1);
    updates.submit(2);
    await updates.idle;
    updates.submit(3);
    expect(failures, 1);
    expect(calls, 1);
  });
}
