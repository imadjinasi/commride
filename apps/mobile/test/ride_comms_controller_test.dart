import 'dart:async';

import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/active_ride/ride_comms_controller.dart';
import 'package:commride_mobile/src/api/ride_comms_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_message.dart';
import 'package:flutter_test/flutter_test.dart';

RideMessage message({
  required String id,
  required String clientMessageId,
  required DateTime createdAt,
  RideMessageKind kind = RideMessageKind.chat,
  String body = 'Message',
}) {
  return RideMessage(
    id: id,
    rideId: 'ride-1',
    senderRiderId: 'rider-1',
    senderDisplayName: 'Rider One',
    senderRideRole: RideRole.member,
    kind: kind,
    body: body,
    clientMessageId: clientMessageId,
    createdAt: createdAt,
  );
}

class FakeRideCommsApi implements RideCommsApi {
  RideMessagePage firstPage = const RideMessagePage(
    messages: <RideMessage>[],
    nextCursor: null,
  );
  final Map<String, RideMessagePage> pages = <String, RideMessagePage>{};
  final List<String> sentIds = <String>[];
  final List<String> sentBodies = <String>[];
  final List<RideMessageKind> sentKinds = <RideMessageKind>[];
  int failSends = 0;

  @override
  Future<RideMessagePage> fetchMessages(
    String rideId, {
    String? cursor,
    int limit = 50,
  }) async {
    if (cursor == null) {
      return firstPage;
    }
    return pages[cursor] ??
        const RideMessagePage(messages: <RideMessage>[], nextCursor: null);
  }

  @override
  Future<RideMessage> sendChat({
    required String rideId,
    required String clientMessageId,
    required String body,
  }) {
    return _send(
      kind: RideMessageKind.chat,
      clientMessageId: clientMessageId,
      body: body,
    );
  }

  @override
  Future<RideMessage> sendAnnouncement({
    required String rideId,
    required String clientMessageId,
    required String body,
  }) {
    return _send(
      kind: RideMessageKind.announcement,
      clientMessageId: clientMessageId,
      body: body,
    );
  }

  Future<RideMessage> _send({
    required RideMessageKind kind,
    required String clientMessageId,
    required String body,
  }) async {
    sentIds.add(clientMessageId);
    sentBodies.add(body);
    sentKinds.add(kind);

    if (failSends > 0) {
      failSends -= 1;
      throw const RideCommsApiException(
        statusCode: 503,
        code: 'request_failed',
        message: 'Offline',
      );
    }

    return message(
      id: 'server-$clientMessageId',
      clientMessageId: clientMessageId,
      createdAt: DateTime.utc(2026, 9, 18, 10, sentIds.length),
      kind: kind,
      body: body,
    );
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
  test('initial history and older page remain chronological', () async {
    final FakeRideCommsApi api = FakeRideCommsApi()
      ..firstPage = RideMessagePage(
        messages: <RideMessage>[
          message(
            id: 'm2',
            clientMessageId: 'c2',
            createdAt: DateTime.utc(2026, 9, 18, 10, 2),
            body: 'Second',
          ),
          message(
            id: 'm3',
            clientMessageId: 'c3',
            createdAt: DateTime.utc(2026, 9, 18, 10, 3),
            body: 'Third',
          ),
        ],
        nextCursor: 'older',
      )
      ..pages['older'] = RideMessagePage(
        messages: <RideMessage>[
          message(
            id: 'm1',
            clientMessageId: 'c1',
            createdAt: DateTime.utc(2026, 9, 18, 10, 1),
            body: 'First',
          ),
        ],
        nextCursor: null,
      );
    final RideCommsController controller = RideCommsController(
      rideId: 'ride-1',
      api: api,
    );

    await controller.loadInitial();
    expect(
      controller.state.messages.map((RideMessage value) => value.body),
      <String>['Second', 'Third'],
    );
    expect(controller.state.nextCursor, 'older');

    await controller.loadOlder();
    expect(
      controller.state.messages.map((RideMessage value) => value.body),
      <String>['First', 'Second', 'Third'],
    );
    expect(controller.state.nextCursor, isNull);

    controller.dispose();
  });

  test('failed send retries the exact same clientMessageId', () async {
    final FakeRideCommsApi api = FakeRideCommsApi()..failSends = 1;
    final RideCommsController controller = RideCommsController(
      rideId: 'ride-1',
      api: api,
      clientMessageIdFactory: () => 'client-stable',
    );

    await expectLater(
      controller.sendChat('Tunggu di SPBU'),
      throwsA(isA<RideCommsApiException>()),
    );

    expect(controller.state.failedSend?.clientMessageId, 'client-stable');
    expect(controller.state.errorMessage, 'Pesan belum terkirim.');

    await controller.retryFailed();

    expect(api.sentIds, <String>['client-stable', 'client-stable']);
    expect(controller.state.failedSend, isNull);
    expect(controller.state.messages.single.body, 'Tunggu di SPBU');

    controller.dispose();
  });

  test('HTTP success and matching realtime event do not duplicate', () async {
    final FakeRideCommsApi api = FakeRideCommsApi();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideCommsController controller = RideCommsController(
      rideId: 'ride-1',
      api: api,
      realtimeClient: realtime,
      clientMessageIdFactory: () => 'client-1',
    )..start();

    await controller.sendChat('Hello');
    final RideMessage persisted = controller.state.messages.single;

    realtime.controller.add(ActiveRideMessageCreated(message: persisted));

    expect(controller.state.messages, hasLength(1));
    expect(controller.state.messages.single.id, persisted.id);

    controller.dispose();
    await realtime.close();
  });

  test('realtime message for another Ride is ignored', () async {
    final FakeRideCommsApi api = FakeRideCommsApi();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideCommsController controller = RideCommsController(
      rideId: 'ride-1',
      api: api,
      realtimeClient: realtime,
    )..start();

    realtime.controller.add(
      ActiveRideMessageCreated(
        message: RideMessage(
          id: 'other-message',
          rideId: 'ride-2',
          senderRiderId: 'rider-2',
          senderDisplayName: 'Other Rider',
          senderRideRole: RideRole.member,
          kind: RideMessageKind.chat,
          body: 'Wrong Ride',
          clientMessageId: 'other-client',
          createdAt: DateTime.utc(2026, 9, 18, 10),
        ),
      ),
    );

    expect(controller.state.messages, isEmpty);

    controller.dispose();
    await realtime.close();
  });

  test('latestAnnouncement returns newest announcement only', () async {
    final FakeRideCommsApi api = FakeRideCommsApi()
      ..firstPage = RideMessagePage(
        messages: <RideMessage>[
          message(
            id: 'announcement-1',
            clientMessageId: 'a1',
            createdAt: DateTime.utc(2026, 9, 18, 9),
            kind: RideMessageKind.announcement,
            body: 'First announcement',
          ),
          message(
            id: 'chat-1',
            clientMessageId: 'c1',
            createdAt: DateTime.utc(2026, 9, 18, 9, 30),
            body: 'Chat',
          ),
          message(
            id: 'announcement-2',
            clientMessageId: 'a2',
            createdAt: DateTime.utc(2026, 9, 18, 10),
            kind: RideMessageKind.announcement,
            body: 'Latest announcement',
          ),
        ],
        nextCursor: null,
      );
    final RideCommsController controller = RideCommsController(
      rideId: 'ride-1',
      api: api,
    );

    await controller.loadInitial();

    expect(controller.state.latestAnnouncement?.body, 'Latest announcement');

    controller.dispose();
  });

  test('Completed Ride starts read-only before any realtime event', () async {
    final FakeRideCommsApi api = FakeRideCommsApi();
    final RideCommsController controller = RideCommsController(
      rideId: 'ride-1',
      api: api,
      readOnly: true,
    );

    expect(controller.state.rideEnded, isTrue);
    await expectLater(controller.sendChat('Too late'), throwsStateError);
    expect(api.sentIds, isEmpty);

    controller.dispose();
  });

  test('Ride end makes sending read-only', () async {
    final FakeRideCommsApi api = FakeRideCommsApi();
    final FakeRealtimeClient realtime = FakeRealtimeClient();
    final RideCommsController controller = RideCommsController(
      rideId: 'ride-1',
      api: api,
      realtimeClient: realtime,
    )..start();

    realtime.controller.add(
      ActiveRideEnded(endedAt: DateTime.utc(2026, 9, 18, 11)),
    );

    expect(controller.state.rideEnded, isTrue);
    await expectLater(controller.sendChat('Too late'), throwsStateError);
    expect(api.sentIds, isEmpty);

    controller.dispose();
    await realtime.close();
  });
}
