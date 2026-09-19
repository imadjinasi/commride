import 'dart:convert';

import 'package:commride_mobile/src/api/http_ride_sos_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/ride_sos.dart';
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

Map<String, Object?> sosJson({
  String state = 'active',
  Object? presence,
}) {
  return <String, Object?>{
    'id': 'sos-1',
    'rideId': 'ride-1',
    'riderId': 'rider-1',
    'riderDisplayName': 'Rider One',
    'riderRideRole': 'member',
    'state': state,
    'clientCommandId': 'client-sos-1',
    'reason': 'Ban bocor',
    'raisedAt': '2026-09-18T10:00:00Z',
    'cancelledAt': state == 'cancelled' ? '2026-09-18T10:10:00Z' : null,
    'resolvedAt': null,
    'resolvedByRiderId': null,
    'presence': presence,
  };
}

void main() {
  test('fetchSos uses auth and preserves trusted presence freshness', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.headers['authorization'], 'Bearer token-1');
      return http.Response(
        jsonEncode(<String, Object?>{
          'sos': <Object?>[
            sosJson(
              presence: <String, Object?>{
                'latitude': -6.732,
                'longitude': 108.552,
                'observedAt': '2026-09-18T09:59:55Z',
                'receivedAt': '2026-09-18T09:59:56Z',
                'freshness': 'stale',
                'movement': 'stopped',
              },
            ),
          ],
        }),
        200,
      );
    });
    final HttpRideSosApi api = HttpRideSosApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    final List<RideSos> result = await api.fetchSos('ride-1');

    expect(result, hasLength(1));
    expect(result.single.presence?.freshness, RidePresenceFreshness.stale);
    expect(result.single.presence?.latitude, -6.732);
  });

  test('raiseSos sends idempotency key without client identity/location', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{'sos': sosJson(presence: null)}),
        201,
      );
    });
    final HttpRideSosApi api = HttpRideSosApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    await api.raiseSos(
      rideId: 'ride-1',
      clientCommandId: 'client-sos-1',
      reason: 'Ban bocor',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/rides/ride-1/sos');
    final Map<String, Object?> body =
        jsonDecode(captured.body) as Map<String, Object?>;
    expect(body['clientCommandId'], 'client-sos-1');
    expect(body['reason'], 'Ban bocor');
    expect(body.containsKey('riderId'), isFalse);
    expect(body.containsKey('latitude'), isFalse);
  });

  test('cancelSos uses dedicated incident endpoint', () async {
    late http.Request captured;
    final MockClient client = MockClient((http.Request request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'sos': sosJson(state: 'cancelled', presence: null),
        }),
        200,
      );
    });
    final HttpRideSosApi api = HttpRideSosApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    final RideSos result = await api.cancelSos(
      rideId: 'ride-1',
      sosId: 'sos-1',
    );

    expect(captured.url.path, '/v1/rides/ride-1/sos/sos-1/cancel');
    expect(result.status, RideSosStatus.cancelled);
  });
}
