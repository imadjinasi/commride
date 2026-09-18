import 'dart:async';

import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/active_ride/location_session_controller.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:flutter_test/flutter_test.dart';

Ride ride(RideStatus status) {
  return Ride(
    id: 'ride-1',
    clubId: 'club-1',
    title: 'Sunday Ride',
    status: status,
    scheduledStartAt: null,
    actualStartAt: status == RideStatus.active
        ? DateTime.utc(2026, 9, 18, 9)
        : null,
    endedAt: null,
    notes: null,
  );
}

RideLocationSample sample(int second, {double latitude = -6.732}) {
  return RideLocationSample(
    latitude: latitude,
    longitude: 108.552,
    observedAt: DateTime.utc(2026, 9, 18, 10, 0, second),
    movement: RideMovementState.moving,
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
  bool failSend = false;
  final List<RideLocationSample> sent = <RideLocationSample>[];

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
  Future<void> sendPresence(RideLocationSample sample) async {
    if (failSend) {
      throw StateError('offline');
    }
    sent.add(sample);
  }

  Future<void> close() => controller.close();
}

Future<void> flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('does not request location or connect for a non-Active Ride', () async {
    final FakeLocationProvider location = FakeLocationProvider();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController session = RideLocationSessionController(
      locationProvider: location,
      realtimeClient: realtime,
    );

    await session.startTracking(ride(RideStatus.published));

    expect(session.state.phase, RideLocationSessionPhase.error);
    expect(location.checkCalls, 0);
    expect(location.requestCalls, 0);
    expect(location.startCalls, 0);
    expect(realtime.connectCalls, 0);

    session.dispose();
    await location.close();
    await realtime.close();
  });

  test(
    'requests permission only when Active Ride tracking is started',
    () async {
      final FakeLocationProvider location = FakeLocationProvider(
        permission: RideLocationPermission.denied,
        requestedPermission: RideLocationPermission.denied,
      );
      final FakeRealtimeClient realtime = FakeRealtimeClient();
      final RideLocationSessionController session =
          RideLocationSessionController(
            locationProvider: location,
            realtimeClient: realtime,
          );

      expect(location.requestCalls, 0);

      await session.startTracking(ride(RideStatus.active));

      expect(location.checkCalls, 1);
      expect(location.requestCalls, 1);
      expect(session.state.phase, RideLocationSessionPhase.denied);
      expect(location.startCalls, 0);
      expect(realtime.connectCalls, 0);

      session.dispose();
      await location.close();
      await realtime.close();
    },
  );

  test('starts provider and realtime only after granted permission', () async {
    final FakeLocationProvider location = FakeLocationProvider(
      permission: RideLocationPermission.denied,
      requestedPermission: RideLocationPermission.granted,
    );
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController session = RideLocationSessionController(
      locationProvider: location,
      realtimeClient: realtime,
    );

    await session.startTracking(ride(RideStatus.active));

    expect(session.state.phase, RideLocationSessionPhase.active);
    expect(
      session.state.connectionState,
      ActiveRideRealtimeConnectionState.connected,
    );
    expect(location.requestCalls, 1);
    expect(location.startCalls, 1);
    expect(realtime.connectCalls, 1);

    session.dispose();
    await flushAsync();
    await location.close();
    await realtime.close();
  });

  test(
    'publishes a location sample with its original observation time',
    () async {
      final FakeLocationProvider location = FakeLocationProvider();
      final FakeRealtimeClient realtime = FakeRealtimeClient();
      final RideLocationSessionController session =
          RideLocationSessionController(
            locationProvider: location,
            realtimeClient: realtime,
          );

      await session.startTracking(ride(RideStatus.active));
      final RideLocationSample observed = sample(7);
      location.controller.add(observed);
      await flushAsync();

      expect(realtime.sent, hasLength(1));
      expect(realtime.sent.single.observedAt, observed.observedAt);
      expect(session.state.lastSample?.observedAt, observed.observedAt);

      session.dispose();
      await flushAsync();
      await location.close();
      await realtime.close();
    },
  );

  test('keeps only the newest unsent presence while degraded', () async {
    final FakeLocationProvider location = FakeLocationProvider();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController session = RideLocationSessionController(
      locationProvider: location,
      realtimeClient: realtime,
    );

    await session.startTracking(ride(RideStatus.active));
    realtime.failSend = true;

    location.controller.add(sample(1, latitude: -6.731));
    await flushAsync();
    location.controller.add(sample(2, latitude: -6.730));
    await flushAsync();

    expect(session.state.phase, RideLocationSessionPhase.degraded);
    expect(session.state.pendingSample?.latitude, -6.730);
    expect(realtime.sent, isEmpty);

    realtime.failSend = false;
    realtime.controller.add(
      const ActiveRideConnectionChanged(
        ActiveRideRealtimeConnectionState.connected,
      ),
    );
    await flushAsync();

    expect(realtime.sent, hasLength(1));
    expect(realtime.sent.single.latitude, -6.730);
    expect(session.state.pendingSample, isNull);
    expect(session.state.phase, RideLocationSessionPhase.active);

    session.dispose();
    await flushAsync();
    await location.close();
    await realtime.close();
  });

  test(
    'server ride.ended stops local provider and realtime publishing',
    () async {
      final FakeLocationProvider location = FakeLocationProvider();
      final FakeRealtimeClient realtime = FakeRealtimeClient();
      final RideLocationSessionController session =
          RideLocationSessionController(
            locationProvider: location,
            realtimeClient: realtime,
          );

      await session.startTracking(ride(RideStatus.active));
      realtime.controller.add(
        ActiveRideEnded(endedAt: DateTime.utc(2026, 9, 18, 11)),
      );
      await flushAsync();

      expect(session.state.phase, RideLocationSessionPhase.stoppedByRideEnd);
      expect(location.stopCalls, 1);
      expect(realtime.disconnectCalls, 1);

      location.controller.add(sample(10));
      await flushAsync();
      expect(realtime.sent, isEmpty);

      session.dispose();
      await flushAsync();
      await location.close();
      await realtime.close();
    },
  );

  test('sign-out stop tears down provider and realtime session', () async {
    final FakeLocationProvider location = FakeLocationProvider();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideLocationSessionController session = RideLocationSessionController(
      locationProvider: location,
      realtimeClient: realtime,
    );

    await session.startTracking(ride(RideStatus.active));
    await session.stopForSignOut();

    expect(session.state.phase, RideLocationSessionPhase.inactive);
    expect(location.stopCalls, 1);
    expect(realtime.disconnectCalls, 1);

    session.dispose();
    await flushAsync();
    await location.close();
    await realtime.close();
  });
}
