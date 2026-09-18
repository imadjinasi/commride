import 'dart:async';
import 'dart:convert';

import 'package:commride_mobile/src/active_ride/io_active_ride_realtime_client.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/active_ride/socket.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

class TokenAuthGateway implements AuthGateway {
  TokenAuthGateway(List<String> tokens) : _tokens = List<String>.of(tokens);

  final List<String> _tokens;
  int tokenCalls = 0;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {}

  @override
  Future<String> idToken() async {
    tokenCalls += 1;
    if (_tokens.isEmpty) {
      throw StateError('No token configured.');
    }
    if (_tokens.length == 1) {
      return _tokens.single;
    }
    return _tokens.removeAt(0);
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class FakeSocket implements ActiveRideSocket {
  final StreamController<Object?> controller =
      StreamController<Object?>.broadcast();
  final List<String> sent = <String>[];
  int closeCalls = 0;
  int? lastCloseCode;
  String? lastCloseReason;

  @override
  Stream<Object?> get messages => controller.stream;

  @override
  void send(String message) {
    sent.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCalls += 1;
    lastCloseCode = code;
    lastCloseReason = reason;
  }

  Future<void> closeIncoming() => controller.close();
}

class RecordingConnector implements ActiveRideSocketConnector {
  RecordingConnector(List<FakeSocket> sockets)
    : _sockets = List<FakeSocket>.of(sockets);

  final List<FakeSocket> _sockets;
  final List<Uri> uris = <Uri>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];

  @override
  Future<ActiveRideSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    uris.add(uri);
    this.headers.add(Map<String, String>.of(headers));
    if (_sockets.isEmpty) {
      throw StateError('No fake socket configured.');
    }
    return _sockets.removeAt(0);
  }
}

RideLocationSample sample() {
  return RideLocationSample(
    latitude: -6.732,
    longitude: 108.552,
    observedAt: DateTime.utc(2026, 9, 18, 10, 0, 5),
    movement: RideMovementState.moving,
  );
}

Future<void> flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('connect uses authenticated wss protocol-v1 endpoint', () async {
    final FakeSocket socket = FakeSocket();
    final RecordingConnector connector = RecordingConnector(<FakeSocket>[
      socket,
    ]);
    final TokenAuthGateway auth = TokenAuthGateway(<String>['token-1']);
    final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: auth,
      socketConnector: connector,
    );

    await client.connect('ride-1');

    expect(connector.uris, hasLength(1));
    expect(
      connector.uris.single.toString(),
      'wss://api.commride.invalid/v1/rides/ride-1/live?v=1',
    );
    expect(connector.headers.single['authorization'], '***');
    expect(auth.tokenCalls, 1);

    await client.disconnect();
    await socket.closeIncoming();
  });

  test(
    'sendPresence emits protocol v1 without client Rider identity',
    () async {
      final FakeSocket socket = FakeSocket();
      final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
        apiBaseUrl: Uri.parse('https://api.commride.invalid'),
        authGateway: TokenAuthGateway(<String>['token-1']),
        socketConnector: RecordingConnector(<FakeSocket>[socket]),
        now: () => DateTime.utc(2026, 9, 18, 10, 0, 10),
        eventIdFactory: () => 'event-1',
      );

      await client.connect('ride-1');
      await client.sendPresence(sample());

      expect(socket.sent, hasLength(1));
      final Object? decoded = jsonDecode(socket.sent.single);
      expect(decoded, isA<Map<String, Object?>>());
      final Map<String, Object?> event = decoded! as Map<String, Object?>;

      expect(event['v'], 1);
      expect(event['type'], 'presence.update');
      expect(event['eventId'], 'event-1');
      expect(event['sentAt'], '2026-09-18T10:00:10.000Z');

      final Map<String, Object?> payload =
          event['payload']! as Map<String, Object?>;
      expect(payload['latitude'], -6.732);
      expect(payload['longitude'], 108.552);
      expect(payload['observedAt'], '2026-09-18T10:00:05.000Z');
      expect(payload['movement'], 'moving');
      expect(payload.containsKey('riderId'), isFalse);
      expect(event.containsKey('riderId'), isFalse);

      await client.disconnect();
      await socket.closeIncoming();
    },
  );

  test('ride.ended emits lifecycle event and disables reconnect', () async {
    final FakeSocket socket = FakeSocket();
    final RecordingConnector connector = RecordingConnector(<FakeSocket>[
      socket,
    ]);
    final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(<String>['token-1']),
      socketConnector: connector,
      reconnectDelay: (_) async {},
    );
    final List<ActiveRideRealtimeEvent> events = <ActiveRideRealtimeEvent>[];
    final StreamSubscription<ActiveRideRealtimeEvent> subscription = client
        .events
        .listen(events.add);

    await client.connect('ride-1');

    socket.controller.add(
      jsonEncode(<String, Object?>{
        'v': 1,
        'type': 'ride.ended',
        'sentAt': '2026-09-18T11:00:00Z',
        'payload': <String, Object?>{
          'rideId': 'ride-1',
          'endedAt': '2026-09-18T11:00:00Z',
        },
      }),
    );
    await flushAsync();

    final ActiveRideEnded ended = events.whereType<ActiveRideEnded>().single;
    expect(ended.endedAt.toUtc(), DateTime.utc(2026, 9, 18, 11));
    expect(socket.closeCalls, 1);

    await socket.closeIncoming();
    await flushAsync();
    expect(connector.uris, hasLength(1));

    await subscription.cancel();
    await client.disconnect();
  });

  test('unexpected disconnect reconnects with a fresh auth token', () async {
    final FakeSocket first = FakeSocket();
    final FakeSocket second = FakeSocket();
    final RecordingConnector connector = RecordingConnector(<FakeSocket>[
      first,
      second,
    ]);
    final TokenAuthGateway auth = TokenAuthGateway(<String>[
      'token-1',
      'token-2',
    ]);
    final List<Duration> delays = <Duration>[];

    final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: auth,
      socketConnector: connector,
      reconnectDelay: (Duration duration) async {
        delays.add(duration);
      },
    );

    await client.connect('ride-1');
    await first.closeIncoming();
    await flushAsync();

    expect(delays, <Duration>[const Duration(seconds: 1)]);
    expect(connector.uris, hasLength(2));
    expect(connector.headers[1]['authorization'], '***');
    expect(auth.tokenCalls, 2);

    await client.disconnect();
    await second.closeIncoming();
  });

  test('structured server error is surfaced without disconnecting', () async {
    final FakeSocket socket = FakeSocket();
    final IoActiveRideRealtimeClient client = IoActiveRideRealtimeClient(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(<String>['token-1']),
      socketConnector: RecordingConnector(<FakeSocket>[socket]),
    );
    final List<ActiveRideRealtimeEvent> events = <ActiveRideRealtimeEvent>[];
    final StreamSubscription<ActiveRideRealtimeEvent> subscription = client
        .events
        .listen(events.add);

    await client.connect('ride-1');
    socket.controller.add(
      jsonEncode(<String, Object?>{
        'v': 1,
        'type': 'error',
        'sentAt': '2026-09-18T10:00:00Z',
        'payload': <String, Object?>{
          'code': 'presence_out_of_order',
          'message': 'Older presence observation was ignored.',
        },
      }),
    );
    await flushAsync();

    final ActiveRideServerError error = events
        .whereType<ActiveRideServerError>()
        .single;
    expect(error.code, 'presence_out_of_order');
    expect(error.message, 'Older presence observation was ignored.');

    await subscription.cancel();
    await client.disconnect();
    await socket.closeIncoming();
  });
}
