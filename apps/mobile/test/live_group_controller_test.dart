import 'dart:async';

import 'package:commride_mobile/src/active_ride/convoy_separation.dart';
import 'package:commride_mobile/src/active_ride/live_group_controller.dart';
import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRealtimeClient implements ActiveRideRealtimeClient {
  final StreamController<ActiveRideRealtimeEvent> controller =
      StreamController<ActiveRideRealtimeEvent>.broadcast(sync: true);
  final List<LiveQuickActionKind> sentKinds = <LiveQuickActionKind>[];
  final List<String?> sentReasons = <String?>[];

  @override
  Stream<ActiveRideRealtimeEvent> get events => controller.stream;

  @override
  Future<void> connect(String rideId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendPresence(RideLocationSample sample) async {}

  @override
  Future<void> sendQuickAction(
    LiveQuickActionKind kind, {
    String? reason,
  }) async {
    sentKinds.add(kind);
    sentReasons.add(reason);
  }

  Future<void> close() => controller.close();
}

LiveRiderPresence presence({
  required String riderId,
  required String displayName,
  required RideRole role,
  required DateTime observedAt,
  LivePresenceFreshness freshness = LivePresenceFreshness.live,
}) {
  return LiveRiderPresence(
    riderId: riderId,
    displayName: displayName,
    role: role,
    latitude: -6.732,
    longitude: 108.552,
    observedAt: observedAt,
    receivedAt: observedAt.add(const Duration(seconds: 1)),
    movement: RideMovementState.moving,
    freshness: freshness,
  );
}

LiveConvoySeparation separation(
  ConvoySeparationPhase phase, {
  bool dataSufficient = true,
}) {
  return LiveConvoySeparation(
    phase: phase,
    dataSufficient: dataSufficient,
    components: const <List<String>>[
      <String>['leader', 'sweeper'],
      <String>['member'],
    ],
    isolatedRiderIds: const <String>['member'],
    sweeperComponentRiderIds: const <String>['leader', 'sweeper'],
    firstSplitObservedAt: DateTime.utc(2026, 9, 18, 10),
    confirmedAt: phase == ConvoySeparationPhase.separatedAttention
        ? DateTime.utc(2026, 9, 18, 10, 0, 20)
        : null,
    recoveryObservedAt: null,
    lastUpdatedAt: DateTime.utc(2026, 9, 18, 10, 0, 20),
  );
}

LiveQuickAction quickAction({
  required String eventId,
  required DateTime raisedAt,
  LiveQuickActionKind kind = LiveQuickActionKind.stopping,
}) {
  return LiveQuickAction(
    eventId: eventId,
    riderId: 'rider-1',
    displayName: 'Rider One',
    role: RideRole.member,
    kind: kind,
    reason: null,
    raisedAt: raisedAt,
  );
}

void main() {
  test('snapshot replaces group state and sorts by Ride role', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    )..start();

    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    realtime.controller.add(
      ActiveRideSnapshotReceived(
        rideId: 'ride-1',
        separation: separation(ConvoySeparationPhase.splitCandidate),
        presences: <LiveRiderPresence>[
          presence(
            riderId: 'member',
            displayName: 'Member',
            role: RideRole.member,
            observedAt: now,
          ),
          presence(
            riderId: 'leader',
            displayName: 'Leader',
            role: RideRole.leader,
            observedAt: now,
          ),
          presence(
            riderId: 'sweeper',
            displayName: 'Sweeper',
            role: RideRole.sweeper,
            observedAt: now,
          ),
        ],
      ),
    );

    expect(
      controller.state.presences.map(
        (LiveRiderPresence value) => value.riderId,
      ),
      <String>['leader', 'sweeper', 'member'],
    );
    expect(
      controller.state.separation?.phase,
      ConvoySeparationPhase.splitCandidate,
    );

    realtime.controller.add(
      ActiveRideSnapshotReceived(
        rideId: 'ride-1',
        presences: <LiveRiderPresence>[
          presence(
            riderId: 'leader',
            displayName: 'Leader',
            role: RideRole.leader,
            observedAt: now,
          ),
        ],
      ),
    );

    expect(controller.state.presences, hasLength(1));

    controller.dispose();
    await realtime.close();
  });

  test('snapshot for another Ride is ignored', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    )..start();

    realtime.controller.add(
      ActiveRideSnapshotReceived(
        rideId: 'ride-2',
        presences: <LiveRiderPresence>[
          presence(
            riderId: 'other',
            displayName: 'Other Rider',
            role: RideRole.member,
            observedAt: DateTime.utc(2026, 9, 18, 10),
          ),
        ],
      ),
    );

    expect(controller.state.presences, isEmpty);

    controller.dispose();
    await realtime.close();
  });

  test('presence upsert ignores older observations', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    )..start();

    final DateTime newer = DateTime.utc(2026, 9, 18, 10, 0, 10);
    realtime.controller.add(
      ActiveRidePresenceUpdated(
        presence: presence(
          riderId: 'rider-1',
          displayName: 'Rider One',
          role: RideRole.member,
          observedAt: newer,
        ),
      ),
    );
    realtime.controller.add(
      ActiveRidePresenceUpdated(
        presence: presence(
          riderId: 'rider-1',
          displayName: 'Old Name',
          role: RideRole.member,
          observedAt: newer.subtract(const Duration(seconds: 1)),
        ),
      ),
    );

    expect(controller.state.presences, hasLength(1));
    expect(controller.state.presences.single.displayName, 'Rider One');

    controller.dispose();
    await realtime.close();
  });

  test('same observation may degrade from Live to Offline', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    )..start();

    final DateTime observedAt = DateTime.utc(2026, 9, 18, 10);
    realtime.controller.add(
      ActiveRidePresenceUpdated(
        presence: presence(
          riderId: 'rider-1',
          displayName: 'Rider One',
          role: RideRole.member,
          observedAt: observedAt,
        ),
      ),
    );
    realtime.controller.add(
      ActiveRidePresenceUpdated(
        presence: presence(
          riderId: 'rider-1',
          displayName: 'Rider One',
          role: RideRole.member,
          observedAt: observedAt,
          freshness: LivePresenceFreshness.offline,
        ),
      ),
    );

    expect(
      controller.state.presences.single.freshness,
      LivePresenceFreshness.offline,
    );

    controller.dispose();
    await realtime.close();
  });

  test('counts age only server-Live presence to Stale', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    )..start();

    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    realtime.controller.add(
      ActiveRideSnapshotReceived(
        rideId: 'ride-1',
        presences: <LiveRiderPresence>[
          presence(
            riderId: 'recent',
            displayName: 'Recent',
            role: RideRole.member,
            observedAt: now.subtract(const Duration(seconds: 10)),
          ),
          presence(
            riderId: 'aged-live',
            displayName: 'Aged Live',
            role: RideRole.member,
            observedAt: now.subtract(const Duration(seconds: 31)),
          ),
          presence(
            riderId: 'offline',
            displayName: 'Offline',
            role: RideRole.member,
            observedAt: now.subtract(const Duration(seconds: 1)),
            freshness: LivePresenceFreshness.offline,
          ),
        ],
      ),
    );

    final ActiveRideGroupCounts counts = controller.state.counts(now);
    expect(counts.live, 1);
    expect(counts.stale, 1);
    expect(counts.offline, 1);

    controller.dispose();
    await realtime.close();
  });

  test('separation updates replace the server-derived convoy state', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    )..start();

    realtime.controller.add(
      ActiveRideSeparationUpdated(
        separation: separation(ConvoySeparationPhase.separatedAttention),
      ),
    );

    expect(
      controller.state.separation?.phase,
      ConvoySeparationPhase.separatedAttention,
    );
    expect(controller.state.separation?.isolatedRiderIds, <String>['member']);

    controller.dispose();
    await realtime.close();
  });

  test('quick actions are idempotent and bounded', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
      quickActionLimit: 2,
    )..start();

    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    realtime.controller.add(
      ActiveRideQuickActionRaised(
        action: quickAction(eventId: 'one', raisedAt: now),
      ),
    );
    realtime.controller.add(
      ActiveRideQuickActionRaised(
        action: quickAction(eventId: 'one', raisedAt: now),
      ),
    );
    realtime.controller.add(
      ActiveRideQuickActionRaised(
        action: quickAction(
          eventId: 'two',
          raisedAt: now.add(const Duration(seconds: 1)),
        ),
      ),
    );
    realtime.controller.add(
      ActiveRideQuickActionRaised(
        action: quickAction(
          eventId: 'three',
          raisedAt: now.add(const Duration(seconds: 2)),
        ),
      ),
    );

    expect(
      controller.state.quickActions.map(
        (LiveQuickAction value) => value.eventId,
      ),
      <String>['three', 'two'],
    );

    controller.dispose();
    await realtime.close();
  });

  test('raiseQuickAction delegates typed action and reason', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await controller.raiseQuickAction(
      LiveQuickActionKind.stopping,
      reason: 'Isi BBM',
    );

    expect(realtime.sentKinds, <LiveQuickActionKind>[
      LiveQuickActionKind.stopping,
    ]);
    expect(realtime.sentReasons, <String?>['Isi BBM']);

    controller.dispose();
    await realtime.close();
  });

  test('raiseQuickAction is rejected after Ride end', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    )..start();

    realtime.controller.add(
      ActiveRideEnded(endedAt: DateTime.utc(2026, 9, 18, 11)),
    );

    await expectLater(
      controller.raiseQuickAction(LiveQuickActionKind.needHelp),
      throwsStateError,
    );
    expect(realtime.sentKinds, isEmpty);

    controller.dispose();
    await realtime.close();
  });

  test('Ride end marks group ended, disconnected, and Offline', () async {
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    )..start();

    final DateTime observedAt = DateTime.utc(2026, 9, 18, 10, 59, 59);
    realtime.controller.add(
      ActiveRidePresenceUpdated(
        presence: presence(
          riderId: 'rider-1',
          displayName: 'Rider One',
          role: RideRole.member,
          observedAt: observedAt,
        ),
      ),
    );
    realtime.controller.add(
      const ActiveRideConnectionChanged(
        ActiveRideRealtimeConnectionState.connected,
      ),
    );
    realtime.controller.add(
      ActiveRideSeparationUpdated(
        separation: separation(ConvoySeparationPhase.separatedAttention),
      ),
    );
    final DateTime endedAt = DateTime.utc(2026, 9, 18, 11);
    realtime.controller.add(ActiveRideEnded(endedAt: endedAt));

    expect(controller.state.endedAt, endedAt);
    expect(
      controller.state.connectionState,
      ActiveRideRealtimeConnectionState.disconnected,
    );
    expect(
      controller.state.presences.single.freshness,
      LivePresenceFreshness.offline,
    );
    expect(controller.state.presences.single.observedAt, observedAt);
    expect(controller.state.separation, isNull);

    controller.dispose();
    await realtime.close();
  });
}
