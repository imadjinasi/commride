import 'dart:async';

import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/active_ride/location_session_controller.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/screens/ride/active_ride_tracking_screen.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

class FakeLocationProvider implements RideLocationProvider {
  FakeLocationProvider({
    this.permission = RideLocationPermission.granted,
    this.requestedPermission = RideLocationPermission.granted,
  });

  RideLocationPermission permission;
  RideLocationPermission requestedPermission;
  int checkCalls = 0;
  int requestCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;

  final StreamController<RideLocationSample> controller =
      StreamController<RideLocationSample>.broadcast();

  @override
  Stream<RideLocationSample> get samples => controller.stream;

  @override
  Future<RideLocationPermission> checkPermission() async {
    checkCalls += 1;
    return permission;
  }

  @override
  Future<RideLocationPermission> requestPermission() async {
    requestCalls += 1;
    permission = requestedPermission;
    return permission;
  }

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  Future<void> close() => controller.close();
}

class FakeRealtimeClient implements ActiveRideRealtimeClient {
  int connectCalls = 0;
  int disconnectCalls = 0;

  final StreamController<ActiveRideRealtimeEvent> controller =
      StreamController<ActiveRideRealtimeEvent>.broadcast();

  @override
  Stream<ActiveRideRealtimeEvent> get events => controller.stream;

  @override
  Future<void> connect(String rideId) async {
    connectCalls += 1;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
  }

  @override
  Future<void> sendPresence(RideLocationSample sample) async {}

  Future<void> close() => controller.close();
}

Widget buildScreen({required RideLocationSessionController controller}) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: ActiveRideTrackingScreen(ride: activeRide(), controller: controller),
  );
}

Future<void> pumpUi(WidgetTester tester) async {
  for (int frame = 0; frame < 5; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  @override
  Future<void> sendQuickAction(
    LiveQuickActionKind kind, {
    String? reason,
  }) async {}
}

Future<void> closeFakes(
  WidgetTester tester,
  RideLocationSessionController controller,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  controller.dispose();
}

Future<void> pumpUntilPhase(
  WidgetTester tester,
  RideLocationSessionController controller,
  RideLocationSessionPhase phase,
) async {
  await tester.runAsync(() async {
    for (int attempt = 0; attempt < 20; attempt += 1) {
      if (controller.state.phase == phase) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pump();

  if (controller.state.phase != phase) {
    fail(
      'Expected Ride location phase $phase, '
      'got ${controller.state.phase}.',
    );
  }
}

void main() {
  testWidgets('opening Active Ride does not request location permission', (
    WidgetTester tester,
  ) async {
    final FakeLocationProvider location = FakeLocationProvider();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController controller =
        RideLocationSessionController(
          locationProvider: location,
          realtimeClient: realtime,
        );

    await tester.pumpWidget(buildScreen(controller: controller));
    await pumpUi(tester);

    expect(find.text('Tracking belum aktif'), findsOneWidget);
    expect(find.text('Aktifkan tracking'), findsOneWidget);
    expect(location.checkCalls, 0);
    expect(location.requestCalls, 0);
    expect(realtime.connectCalls, 0);

    await closeFakes(tester, controller);
  });

  testWidgets('permission request happens only after contextual confirmation', (
    WidgetTester tester,
  ) async {
    final FakeLocationProvider location = FakeLocationProvider();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController controller =
        RideLocationSessionController(
          locationProvider: location,
          realtimeClient: realtime,
        );

    await tester.pumpWidget(buildScreen(controller: controller));
    await tester.tap(find.text('Aktifkan tracking'));
    await pumpUi(tester);

    expect(find.text('Aktifkan lokasi untuk Ride?'), findsOneWidget);
    expect(location.checkCalls, 0);

    await tester.tap(find.text('Lanjutkan'));
    await pumpUi(tester);

    expect(location.checkCalls, 1);
    expect(location.startCalls, 1);
    expect(realtime.connectCalls, 1);
    expect(find.text('Tracking aktif'), findsOneWidget);

    await closeFakes(tester, controller);
  });

  testWidgets('dismissing explanation keeps permission untouched', (
    WidgetTester tester,
  ) async {
    final FakeLocationProvider location = FakeLocationProvider();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController controller =
        RideLocationSessionController(
          locationProvider: location,
          realtimeClient: realtime,
        );

    await tester.pumpWidget(buildScreen(controller: controller));
    await tester.tap(find.text('Aktifkan tracking'));
    await pumpUi(tester);
    await tester.tap(find.text('Nanti'));
    await pumpUi(tester);

    expect(location.checkCalls, 0);
    expect(location.requestCalls, 0);
    expect(location.startCalls, 0);
    expect(realtime.connectCalls, 0);

    await closeFakes(tester, controller);
  });

  testWidgets('denied permission stays recoverable and explicit', (
    WidgetTester tester,
  ) async {
    final FakeLocationProvider location = FakeLocationProvider(
      permission: RideLocationPermission.denied,
      requestedPermission: RideLocationPermission.denied,
    );
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController controller =
        RideLocationSessionController(
          locationProvider: location,
          realtimeClient: realtime,
        );

    await tester.pumpWidget(buildScreen(controller: controller));
    await tester.tap(find.text('Aktifkan tracking'));
    await pumpUi(tester);
    await tester.tap(find.text('Lanjutkan'));
    await pumpUi(tester);

    expect(find.text('Izin lokasi belum diberikan'), findsOneWidget);
    expect(find.text('Coba izin lokasi lagi'), findsOneWidget);
    expect(location.requestCalls, 1);
    expect(location.startCalls, 0);

    await closeFakes(tester, controller);
  });

  testWidgets('server Ride end visibly stops tracking', (
    WidgetTester tester,
  ) async {
    final FakeLocationProvider location = FakeLocationProvider();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController controller =
        RideLocationSessionController(
          locationProvider: location,
          realtimeClient: realtime,
        );

    await controller.startTracking(activeRide());
    await tester.pumpWidget(buildScreen(controller: controller));
    await pumpUi(tester);

    expect(find.text('Tracking aktif'), findsOneWidget);

    realtime.controller.add(
      ActiveRideEnded(endedAt: DateTime.utc(2026, 9, 18, 11)),
    );
    await pumpUntilPhase(
      tester,
      controller,
      RideLocationSessionPhase.stoppedByRideEnd,
    );

    expect(find.text('Tracking berhenti'), findsOneWidget);
    expect(location.stopCalls, 1);
    expect(realtime.disconnectCalls, 1);

    await closeFakes(tester, controller);
  });
}
