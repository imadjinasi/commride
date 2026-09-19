import 'dart:convert';

import 'package:commride_mobile/src/api/http_ride_comms_api.dart';
import 'package:commride_mobile/src/api/ride_comms_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/ride_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

Map<String, Object?> messageJson({
  String id = 'message-1',
  String kind = 'chat',
  String body = 'Halo rombongan',
  String clientMessageId = 'client-1',
}) {
  return <String, Object?>{
    'id': id,
    'rideId': 'ride-1',
    'senderRiderId': 'rider-1',
    'senderDisplayName': 'Rider One',
    'senderRideRole': 'member',
    'kind': kind,
    'body': body,
    'clientMessageId': clientMessageId,
    'createdAt': '2026-09-18T10:00:00Z',
  };
}

void main() {
  test('fetchMessages sends auth and preserves pagination cursor', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'messages': <Object?>[messageJson()],
          'nextCursor': '2026-09-18T09:00:00.000Z|message-old',
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final HttpRideCommsApi api = HttpRideCommsApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    final RideMessagePage page = await api.fetchMessages(
      'ride-1',
      cursor: '2026-09-18T11:00:00.000Z|message/new',
      limit: 25,
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/v1/rides/ride-1/messages');
    expect(captured.url.queryParameters['limit'], '25');
    expect(
      captured.url.queryParameters['cursor'],
      '2026-09-18T11:00:00.000Z|message/new',
    );
    expect(
      captured.headers['authorization'],
      <String>['Bearer', 'token-1'].join(' '),
    );
    expect(page.messages, hasLength(1));
    expect(page.messages.single.body, 'Halo rombongan');
    expect(page.nextCursor, '2026-09-18T09:00:00.000Z|message-old');
  });

  test('sendChat posts idempotency key and parses created message', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'message': messageJson(
            body: 'Tunggu di SPBU',
            clientMessageId: 'client-chat',
          ),
        }),
        201,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final HttpRideCommsApi api = HttpRideCommsApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    final RideMessage message = await api.sendChat(
      rideId: 'ride-1',
      clientMessageId: 'client-chat',
      body: 'Tunggu di SPBU',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/rides/ride-1/messages');
    expect(captured.headers['content-type'], contains('application/json'));
    final Map<String, Object?> requestBody =
        jsonDecode(captured.body) as Map<String, Object?>;
    expect(requestBody['clientMessageId'], 'client-chat');
    expect(requestBody['body'], 'Tunggu di SPBU');
    expect(requestBody.containsKey('senderRiderId'), isFalse);
    expect(message.clientMessageId, 'client-chat');
  });

  test('sendAnnouncement uses Leader announcement endpoint', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'message': messageJson(
            kind: 'announcement',
            body: 'Regroup di checkpoint berikutnya',
            clientMessageId: 'client-announcement',
          ),
        }),
        200,
      );
    });
    final HttpRideCommsApi api = HttpRideCommsApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    final RideMessage message = await api.sendAnnouncement(
      rideId: 'ride-1',
      clientMessageId: 'client-announcement',
      body: 'Regroup di checkpoint berikutnya',
    );

    expect(captured.url.path, '/v1/rides/ride-1/announcements');
    expect(message.kind, RideMessageKind.announcement);
  });

  test('structured API error remains explicit', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'code': 'ride_state_conflict',
            'message': 'Messages can only be sent while the Ride is Active.',
          },
        }),
        409,
      );
    });
    final HttpRideCommsApi api = HttpRideCommsApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    await expectLater(
      api.sendChat(
        rideId: 'ride-1',
        clientMessageId: 'client-1',
        body: 'Late message',
      ),
      throwsA(
        isA<RideCommsApiException>()
            .having(
              (RideCommsApiException error) => error.statusCode,
              'statusCode',
              409,
            )
            .having(
              (RideCommsApiException error) => error.code,
              'code',
              'ride_state_conflict',
            ),
      ),
    );
  });
}
