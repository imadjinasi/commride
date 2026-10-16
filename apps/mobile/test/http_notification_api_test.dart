import 'dart:convert';

import 'package:commride_mobile/src/api/http_notification_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/rider_notification.dart';
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

void main() {
  test('lists scoped notifications for the authenticated Rider', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'notifications': <Object?>[
            <String, Object?>{
              'id': 'notification-1',
              'riderId': 'rider-1',
              'scope': 'account',
              'clubId': 'club-1',
              'rideId': null,
              'eventKey': 'club-invite:club-1:rider-1',
              'kind': 'club_invite',
              'title': 'Undangan Club',
              'body': 'Anda diundang bergabung ke sebuah Club.',
              'data': <String, Object?>{
                'type': 'club.invite',
                'clubId': 'club-1',
              },
              'createdAt': '2026-09-23T10:00:00Z',
              'readAt': null,
            },
          ],
        }),
        200,
      );
    });
    final HttpNotificationApi api = HttpNotificationApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    final List<RiderNotification> result = await api.listNotifications(
      scope: RiderNotificationScope.account,
    );

    expect(captured.url.path, '/v1/me/notifications');
    expect(captured.url.queryParameters['scope'], 'account');
    expect(captured.headers['authorization'], 'Bearer token-1');
    expect(result.single.kind, 'club_invite');
    expect(result.single.isUnread, isTrue);
  });

  test('marks one notification as read', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(jsonEncode(<String, Object?>{'read': true}), 200);
    });
    final HttpNotificationApi api = HttpNotificationApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    await api.markRead('notification-1');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/me/notifications/notification-1/read');
  });
}
