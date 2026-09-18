import 'package:commride_mobile/src/api/http_rider_profile_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/rider_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TokenAuthGateway implements AuthGateway {
  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {}

  @override
  Future<String> idToken() async => 'firebase-id-token';

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  test('fetchProfile sends Bearer token and maps Rider response', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.url.path, '/v1/me');
      expect(
        request.headers['authorization'],
        'Bearer firebase-id-token',
      );

      return http.Response(
        '{"rider":{"id":"rider-1","displayName":"Rider One",'
        '"callsign":"Lead","homeArea":"Cirebon"}}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpRiderProfileApi api = HttpRiderProfileApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final RiderProfile? profile = await api.fetchProfile();

    expect(profile?.id, 'rider-1');
    expect(profile?.callsign, 'Lead');
  });

  test('fetchProfile maps API 404 to onboarding state', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        '{"error":{"code":"rider_profile_not_found",'
        '"message":"Profile not found","requestId":"test"}}',
        404,
      );
    });

    final HttpRiderProfileApi api = HttpRiderProfileApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    await expectLater(api.fetchProfile(), completion(isNull));
  });
}
