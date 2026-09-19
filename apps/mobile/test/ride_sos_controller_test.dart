import 'dart:async';

import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/active_ride/ride_sos_controller.dart';
import 'package:commride_mobile/src/api/ride_sos_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_sos.dart';
import 'package:flutter_test/flutter_test.dart';

RideSos sos({
  String id = 'sos-1',
  String rideId = 'ride-1',
  String riderId = 'rider-1',
  RideSosStatus status = RideSosStatus.active,
  String clientCommandId = 'client-1',
}) {
  return RideSos(
    id: id,
    rideId: rideId,
    riderId: riderId,
    riderDisplayName: 'Rider One',
    riderRideRole: RideRole.member,
    status: status,
    clientCommandId: clientCommandId,
    reason: null,
    raisedAt: DateTime.utc(2026, 9, 18, 10),
    cancelledAt: status == RideSosStatus.cancelled
        ? DateTime.utc(2026, 9, 18, 10, 10)
        : null,
    resolvedAt: status == RideSosStatus.resolved
        ? DateTime.utc(2026, 9, 18, 10, 10)
        : null,
    resolvedByRiderId: status == RideSosStatus.resolved ? 'leader-1' : null,
    presence: null,
  );
}

class FakeRideSosApi implements RideSosApi {
  List<RideSos> items = <RideSos>[];
  final List<String> sentIds = <String>[];
  int failRaises = 0;

  @override
  Future<List<RideSos>> fetchSos(String rideId) async => items;

  @override
  Future<RideSos> raiseSos({
    required String rideId,
    required String clientCommandId,
    required String? reason,
  }) async {
    sentIds.add(clientCommandId);
    if (failRaises > 0) {
      failRaises -= 1;
      throw const RideSosApiException(
        statusCode: 503,
        code: 'request_failed',
        message: 'Offline',
      );
    }
    return sos(clientCommandId: clientCommandId);
  }

  @override
  Future<RideSos> cancelSos({
    required String rideId,
    required String sosId,
  }) async {
    return sos(id: sosId, status: RideSosStatus.cancelled);
  }

  @override
  Future<RideSos> resolveSos({
    required String rideId,
    required String sosId,
  }) async {
    return sos(id: sosId, status: RideSosStatus.resolved);
  }
}

class FakeRealtimeClient implements ActiveRideRealtimeClient {
  final StreamController<ActiveRideRealtimeEvent> controller =
      StreamController<ActiveRideRealtimeEvent>.broadcast(sync: true);

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
  }) async {}

  Future<void> close() => controller.close();
}

void main() {
  test('load recovers authoritative SOS state', () async {
    final FakeRideSosApi api = FakeRideSosApi()..items = <RideSos>[sos()];
    final RideSosController controller = RideSosController(
      rideId: 'ride-1',
      api: api,
    );

    await controller.load();

    expect(controller.state.activeItems, hasLength(1));
    controller.dispose();
  });

  test('failed raise retries the exact same clientCommandId', () async {
    final FakeRideSosApi api = FakeRideSosApi()..failRaises = 1;
    final RideSosController controller = RideSosController(
      rideId: 'ride-1',
      api: api,
      clientCommandIdFactory: () => 'stable-sos-id',
    );

    await expectLater(
      controller.raise('Ban bocor'),
      throwsA(isA<RideSosApiException>()),
    );
    expect(controller.state.failedRaise?.clientCommandId, 'stable-sos-id');
    expect(controller.state.activeItems, isEmpty);

    await controller.retryFailedRaise();

    expect(api.sentIds, <String>['stable-sos-id', 'stable-sos-id']);
    expect(controller.state.activeItems, hasLength(1));
    controller.dispose();
  });

  test('realtime SOS update replaces HTTP state by incident id', () async {
    final FakeRideSosApi api = FakeRideSosApi()
      ..items = <RideSos>[sos()];
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideSosController controller = RideSosController(
      rideId: 'ride-1',
      api: api,
      realtimeClient: realtime,
    )..start();

    await controller.load();
    realtime.controller.add(
      ActiveRideSosChanged(
        type: 'ride.sos_resolved',
        sos: sos(status: RideSosStatus.resolved),
      ),
    );

    expect(controller.state.activeItems, isEmpty);
    expect(controller.state.items.single.status, RideSosStatus.resolved);

    controller.dispose();
    await realtime.close();
  });

  test('Completed Ride is read-only', () async {
    final FakeRideSosApi api = FakeRideSosApi();
    final RideSosController controller = RideSosController(
      rideId: 'ride-1',
      api: api,
      readOnly: true,
    );

    await expectLater(controller.raise(null), throwsStateError);
    expect(api.sentIds, isEmpty);
    controller.dispose();
  });
}
