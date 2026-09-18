import 'dart:async';

import 'package:commride_mobile/src/active_ride/convoy_separation.dart';
import 'package:commride_mobile/src/active_ride/live_group_controller.dart';
import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/screens/ride/live_group_screen.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRealtimeClient implements ActiveRideRealtimeClient {
  final StreamController<ActiveRideRealtimeEvent> controller =
      StreamController<ActiveRideRealtimeEvent>.broadcast(sync: true);
  final List<LiveQuickActionKind> sentKinds = <LiveQuickActionKind>[];
  final List<String?> sentReasons = <String?>[];
  bool failQuickAction = false;

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
    if (failQuickAction) {
      throw StateError('offline');
    }
    sentKinds.add(kind);
    sentReasons.add(reason);
  }

  Future<void> close() => controller.close();
}

Ride activeRide() {
  return Ride(
    id: 'ride-1',
    clubId: 'club-1',
    title: 'Sunday Ride',
    status: RideStatus.active,
    scheduledStartAt: null,
    actualStartAt: DateTime.utc(2026, 9, 18, 9),
    endedAt: null,
    notes: null,
  );
}

LiveRiderPresence presence({
  required String riderId,
  required String displayName,
  required DateTime observedAt,
  LivePresenceFreshness freshness = LivePresenceFreshness.live,
  RideRole role = RideRole.member,
  RideMovementState movement = RideMovementState.moving,
}) {
  return LiveRiderPresence(
    riderId: riderId,
    displayName: displayName,
    role: role,
    latitude: -6.732,
    longitude: 108.552,
    observedAt: observedAt,
    receivedAt: observedAt.add(const Duration(seconds: 1)),
    movement: movement,
    freshness: freshness,
  );
}

LiveConvoySeparation separation({
  required ConvoySeparationPhase phase,
  required bool dataSufficient,
}) {
  return LiveConvoySeparation(
    phase: phase,
    dataSufficient: dataSufficient,
    components: const <List<String>>[
      <String>['leader', 'sweeper'],
      <String>['rider-3'],
    ],
    isolatedRiderIds: const <String>['rider-3'],
    sweeperComponentRiderIds: const <String>['leader', 'sweeper'],
    firstSplitObservedAt: DateTime.utc(2026, 9, 18, 10),
    confirmedAt: phase == ConvoySeparationPhase.separatedAttention
        ? DateTime.utc(2026, 9, 18, 10, 0, 20)
        : null,
    recoveryObservedAt: null,
    lastUpdatedAt: DateTime.utc(2026, 9, 18, 10, 0, 20),
  );
}

Widget buildScreen({
  required ActiveRideGroupController controller,
  required DateTime now,
}) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: LiveGroupScreen(
      ride: activeRide(),
      controller: controller,
      now: () => now,
      autoRefresh: false,
    ),
  );
}

Future<void> cleanup(
  WidgetTester tester,
  ActiveRideGroupController controller,
  FakeRealtimeClient realtime,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
  await realtime.close();
}

void main() {
  testWidgets('shows Live Stale Offline summary and observation age', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    realtime.controller.add(
      const ActiveRideConnectionChanged(
        ActiveRideRealtimeConnectionState.connected,
      ),
    );
    realtime.controller.add(
      ActiveRideSnapshotReceived(
        rideId: 'ride-1',
        presences: <LiveRiderPresence>[
          presence(
            riderId: 'leader',
            displayName: 'Leader One',
            role: RideRole.leader,
            observedAt: now.subtract(const Duration(seconds: 10)),
          ),
          presence(
            riderId: 'stale',
            displayName: 'Stale Rider',
            observedAt: now.subtract(const Duration(seconds: 45)),
          ),
          presence(
            riderId: 'offline',
            displayName: 'Offline Rider',
            observedAt: now.subtract(const Duration(minutes: 3)),
            freshness: LivePresenceFreshness.offline,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Live Group terhubung'), findsOneWidget);
    expect(find.text('Leader One'), findsOneWidget);
    expect(find.text('Stale Rider'), findsOneWidget);
    expect(find.text('Offline Rider'), findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Stale'), findsWidgets);
    expect(find.text('Offline'), findsWidgets);
    expect(find.textContaining('observasi 3 mnt lalu'), findsOneWidget);

    await cleanup(tester, controller, realtime);
  });

  testWidgets('shows confirmed separation as factual attention', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10, 0, 20);
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    realtime.controller.add(
      ActiveRideSeparationUpdated(
        separation: separation(
          phase: ConvoySeparationPhase.separatedAttention,
          dataSufficient: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Jarak rombongan melebar'), findsOneWidget);
    expect(
      find.textContaining('mungkin terbagi menjadi 2 kelompok'),
      findsOneWidget,
    );
    expect(find.textContaining('bukan kepastian'), findsOneWidget);
    expect(
      find.textContaining('1 Rider terisolasi secara posisi'),
      findsOneWidget,
    );
    expect(find.textContaining('Komponen Sweeper: 2 Rider'), findsOneWidget);

    await cleanup(tester, controller, realtime);
  });

  testWidgets('confirmed separation does not claim recovery with insufficient data', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10, 0, 30);
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    realtime.controller.add(
      ActiveRideSeparationUpdated(
        separation: separation(
          phase: ConvoySeparationPhase.separatedAttention,
          dataSufficient: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Perhatian rombongan belum dapat diverifikasi ulang'),
      findsOneWidget,
    );
    expect(find.text('Rombongan terhubung'), findsNothing);

    await cleanup(tester, controller, realtime);
  });

  testWidgets('shows structured quick action as attention state', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    realtime.controller.add(
      ActiveRideQuickActionRaised(
        action: LiveQuickAction(
          eventId: 'quick-1',
          riderId: 'rider-2',
          displayName: 'Rider Two',
          role: RideRole.member,
          kind: LiveQuickActionKind.leftBehind,
          reason: 'Terpisah di lampu merah.',
          raisedAt: now.subtract(const Duration(seconds: 20)),
          presence: presence(
            riderId: 'rider-2',
            displayName: 'Rider Two',
            observedAt: now.subtract(const Duration(seconds: 45)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Perlu perhatian'), findsOneWidget);
    expect(find.text('Saya Tertinggal'), findsOneWidget);
    expect(find.textContaining('Rider Two'), findsOneWidget);
    expect(find.text('Terpisah di lampu merah.'), findsOneWidget);
    expect(find.text('Lokasi Stale · observasi 45 dtk lalu'), findsOneWidget);

    await cleanup(tester, controller, realtime);
  });

  testWidgets('one-tap Quick Action sends without location claim', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    await tester.tap(find.text('Quick Actions'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saya Berhenti'));
    await tester.pumpAndSettle();

    expect(realtime.sentKinds, <LiveQuickActionKind>[
      LiveQuickActionKind.stopping,
    ]);
    expect(realtime.sentReasons, <String?>[null]);
    expect(find.text('Saya Berhenti terkirim.'), findsOneWidget);

    await cleanup(tester, controller, realtime);
  });

  testWidgets('canceling optional Quick Action reason does not send', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    await tester.tap(find.text('Quick Actions'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Kirim Saya Tertinggal dengan alasan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lampu merah');
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(realtime.sentKinds, isEmpty);
    expect(find.text('Quick Actions'), findsWidgets);

    await cleanup(tester, controller, realtime);
  });

  testWidgets('Quick Action can send an optional reason', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    await tester.tap(find.text('Quick Actions'));
    await tester.pumpAndSettle();

    final Finder reasonButton = find.byTooltip(
      'Kirim Butuh Bantuan dengan alasan',
    );
    await tester.ensureVisible(reasonButton);
    await tester.pumpAndSettle();
    await tester.tap(reasonButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ban bocor');
    await tester.tap(find.text('Kirim'));
    await tester.pumpAndSettle();

    expect(realtime.sentKinds, <LiveQuickActionKind>[
      LiveQuickActionKind.needHelp,
    ]);
    expect(realtime.sentReasons, <String?>['Ban bocor']);
    expect(find.text('Butuh Bantuan terkirim.'), findsOneWidget);

    await cleanup(tester, controller, realtime);
  });

  testWidgets('Quick Action failure stays explicit when realtime is down', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final FakeRealtimeClient realtime = FakeRealtimeClient()
      ..failQuickAction = true;
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    await tester.tap(find.text('Quick Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Butuh Bantuan'));
    await tester.pumpAndSettle();

    expect(realtime.sentKinds, isEmpty);
    expect(
      find.text('Quick action belum terkirim. Periksa koneksi realtime.'),
      findsOneWidget,
    );

    await cleanup(tester, controller, realtime);
  });

  testWidgets('Ride end makes last positions explicitly non-live', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final ActiveRideGroupController controller = ActiveRideGroupController(
      rideId: 'ride-1',
      realtimeClient: realtime,
    );

    await tester.pumpWidget(buildScreen(controller: controller, now: now));
    realtime.controller.add(
      ActiveRideSnapshotReceived(
        rideId: 'ride-1',
        presences: <LiveRiderPresence>[
          presence(
            riderId: 'rider-1',
            displayName: 'Rider One',
            observedAt: now,
          ),
        ],
      ),
    );
    realtime.controller.add(ActiveRideEnded(endedAt: now));
    await tester.pumpAndSettle();

    expect(find.text('Ride selesai'), findsOneWidget);
    expect(
      find.textContaining('Posisi terakhir tidak dianggap live'),
      findsOneWidget,
    );
    expect(find.text('Offline'), findsWidgets);
    expect(find.text('Live'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Quick Actions'),
      findsNothing,
    );

    await cleanup(tester, controller, realtime);
  });
}
