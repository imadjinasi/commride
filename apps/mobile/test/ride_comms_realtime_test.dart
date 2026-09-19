import 'dart:async';
import 'dart:convert';

import 'package:commride_mobile/src/active_ride/io_active_ride_realtime_client.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/active_ride/socket.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/ride_message.dart';
import 'package:commride_mobile/src/models/ride_sos.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthGateway implements AuthGateway {
  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {}

  @override
  Future<String> idToken() async => 'token-1';

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class FakeSocket implements ActiveRideSocket {
  final StreamController<Object?> incoming =
      StreamController<Object?>.broadcast();
  final List<String> sent = <String>[];

  @override
  Stream<Object?> get messages => incoming.stream;

  @override
  void send(String message) {
    sent.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) async {}
}

class FakeConnector implements ActiveRideSocketConnector {
  FakeConnector(this.socket);

  final FakeSocket socket;

  @override
  Future<ActiveRideSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    return socket;
  }
}

Future<void> flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('ride.message_created maps a persisted Ride message', () async {
    final FakeSocket socket = FakeSocket();
    final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      socketConnector: FakeConnector(socket),
    );
    final List<ActiveRideRealtimeEvent> events = <ActiveRideRealtimeEvent>[];
    final StreamSubscription<ActiveRideRealtimeEvent> subscription = client
        .events
        .listen(events.add);

    await client.connect('ride-1');
    socket.incoming.add(
      jsonEncode(<String, Object?>{
        'v': 1,
        'type': 'ride.message_created',
        'sentAt': '2026-09-18T10:05:00Z',
        'payload': <String, Object?>{
          'id': 'message-1',
          'rideId': 'ride-1',
          'senderRiderId': 'rider-2',
          'senderDisplayName': 'Rider Two',
          'senderRideRole': 'member',
          'kind': 'chat',
          'body': 'Tunggu di SPBU depan.',
          'clientMessageId': 'client-message-1',
          'createdAt': '2026-09-18T10:05:00Z',
        },
      }),
    );
    await flushAsync();

    final ActiveRideMessageCreated created = events
        .whereType<ActiveRideMessageCreated>()
        .single;
    expect(created.message.id, 'message-1');
    expect(created.message.kind, RideMessageKind.chat);
    expect(created.message.senderDisplayName, 'Rider Two');
    expect(created.message.body, 'Tunggu di SPBU depan.');

    await subscription.cancel();
    await client.disconnect();
    await socket.incoming.close();
  });

  test('malformed ride.message_created does not fabricate state', () async {
    final FakeSocket socket = FakeSocket();
    final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      socketConnector: FakeConnector(socket),
    );
    final List<ActiveRideRealtimeEvent> events = <ActiveRideRealtimeEvent>[];
    final StreamSubscription<ActiveRideRealtimeEvent> subscription = client
        .events
        .listen(events.add);

    await client.connect('ride-1');
    socket.incoming.add(
      jsonEncode(<String, Object?>{
        'v': 1,
        'type': 'ride.message_created',
        'sentAt': '2026-09-18T10:05:00Z',
        'payload': <String, Object?>{
          'id': 'message-1',
          'rideId': 'ride-1',
          'kind': 'chat',
          'body': 'Missing sender fields',
        },
      }),
    );
    await flushAsync();

    expect(events.whereType<ActiveRideMessageCreated>(), isEmpty);

    await subscription.cancel();
    await client.disconnect();
    await socket.incoming.close();
  });

  test('ride.sos_raised maps persisted SOS with trusted freshness', () async {
    final FakeSocket socket = FakeSocket();
    final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      socketConnector: FakeConnector(socket),
    );
    final List<ActiveRideRealtimeEvent> events = <ActiveRideRealtimeEvent>[];
    final StreamSubscription<ActiveRideRealtimeEvent> subscription = client
        .events
        .listen(events.add);

    await client.connect('ride-1');
    socket.incoming.add(
      jsonEncode(<String, Object?>{
        'v': 1,
        'type': 'ride.sos_raised',
        'sentAt': '2026-09-18T10:05:00Z',
        'payload': <String, Object?>{
          'id': 'sos-1',
          'rideId': 'ride-1',
          'riderId': 'rider-2',
          'riderDisplayName': 'Rider Two',
          'riderRideRole': 'member',
          'state': 'active',
          'clientCommandId': 'client-sos-1',
          'reason': null,
          'raisedAt': '2026-09-18T10:05:00Z',
          'cancelledAt': null,
          'resolvedAt': null,
          'resolvedByRiderId': null,
          'presence': <String, Object?>{
            'latitude': -6.732,
            'longitude': 108.552,
            'observedAt': '2026-09-18T10:04:40Z',
            'receivedAt': '2026-09-18T10:04:41Z',
            'freshness': 'stale',
            'movement': 'stopped',
          },
        },
      }),
    );
    await flushAsync();

    final ActiveRideSosChanged changed = events
        .whereType<ActiveRideSosChanged>()
        .single;
    expect(changed.type, 'ride.sos_raised');
    expect(changed.sos.status, RideSosStatus.active);
    expect(changed.sos.presence?.freshness, RidePresenceFreshness.stale);

    await subscription.cancel();
    await client.disconnect();
    await socket.incoming.close();
  });

  test('malformed ride.sos_raised does not fabricate state', () async {
    final FakeSocket socket = FakeSocket();
    final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      socketConnector: FakeConnector(socket),
    );
    final List<ActiveRideRealtimeEvent> events = <ActiveRideRealtimeEvent>[];
    final StreamSubscription<ActiveRideRealtimeEvent> subscription = client
        .events
        .listen(events.add);

    await client.connect('ride-1');
    socket.incoming.add(
      jsonEncode(<String, Object?>{
        'v': 1,
        'type': 'ride.sos_raised',
        'sentAt': '2026-09-18T10:05:00Z',
        'payload': <String, Object?>{
          'id': 'sos-1',
          'rideId': 'ride-1',
          'state': 'active',
        },
      }),
    );
    await flushAsync();

    expect(events.whereType<ActiveRideSosChanged>(), isEmpty);

    await subscription.cancel();
    await client.disconnect();
    await socket.incoming.close();
  });

}
