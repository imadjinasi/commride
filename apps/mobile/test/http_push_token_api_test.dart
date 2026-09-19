import 'dart:convert';

import 'package:commride_mobile/src/api/http_push_token_api.dart';
import 'package:commride_mobile/src/api/push_token_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
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
  test('registerToken authenticates and sends platform without Rider identity', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'pushToken': <String, Object?>{
            'id': 'push-1',
            'platform': 'android',
            'updatedAt': '2026-09-19T06:00:00Z',
          },
        }),
        200,
      );
    });
    final HttpPushTokenApi api = HttpPushTokenApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    await api.registerToken(
      token: 'device-token',
      platform: RidePushPlatform.android,
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/me/push-tokens');
    expect(captured.headers['authorization'], 'Bearer token-1');

    final Map<String, Object?> body =
        jsonDecode(captured.body) as Map<String, Object?>;
    expect(body, <String, Object?>{
      'token': 'device-token',
      'platform': 'android',
    });
    expect(body.containsKey('riderId'), isFalse);
  });

  test('unregisterToken uses authenticated DELETE with the same token', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{'unregistered': true}),
        200,
      );
    });
    final HttpPushTokenApi api = HttpPushTokenApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    await api.unregisterToken(
      token: 'device-token',
      platform: RidePushPlatform.ios,
    );

    expect(captured.method, 'DELETE');
    final Map<String, Object?> body =
        jsonDecode(captured.body) as Map<String, Object?>;
    expect(body['token'], 'device-token');
    expect(body['platform'], 'ios');
  });

  test('preserves structured registration errors', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'code': 'invalid_push_token',
            'message': 'token is invalid',
          },
        }),
        400,
      );
    });
    final HttpPushTokenApi api = HttpPushTokenApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    expect(
      () => api.registerToken(
        token: 'bad',
        platform: RidePushPlatform.android,
      ),
      throwsA(
        isA<PushTokenApiException>().having(
          (PushTokenApiException error) => error.code,
          'code',
          'invalid_push_token',
        ),
      ),
    );
  });
}
