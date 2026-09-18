import 'package:commride_mobile/src/api/http_club_ride_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
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
  test('listClubs uses Bearer token and maps membership-scoped items', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/clubs');
      expect(request.headers['authorization'], 'Bearer firebase-id-token');

      return http.Response(
        '{"clubs":[{"club":{"id":"club-1","createdByRiderId":"rider-1",'
        '"name":"Cirebon Riders","slug":"cirebon-riders",'
        '"homeArea":"Cirebon","description":null,"visibility":"private",'
        '"createdAt":"2026-09-18T00:00:00Z",'
        '"updatedAt":"2026-09-18T00:00:00Z"},'
        '"membership":{"clubId":"club-1","riderId":"rider-1",'
        '"role":"owner","status":"active"}}]}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpClubRideApi api = HttpClubRideApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final List<ClubListItem> clubs = await api.listClubs();

    expect(clubs, hasLength(1));
    expect(clubs.single.club.name, 'Cirebon Riders');
    expect(clubs.single.membership.role, ClubRole.owner);
  });

  test('publishRide uses explicit lifecycle command endpoint', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/rides/ride-1/publish');
      expect(request.headers['authorization'], 'Bearer firebase-id-token');

      return http.Response(
        '{"ride":{"id":"ride-1","clubId":"club-1",'
        '"createdByRiderId":"rider-1","title":"Sunday Morning Ride",'
        '"status":"published","scheduledStartAt":null,'
        '"actualStartAt":null,"endedAt":null,"notes":null,'
        '"createdAt":"2026-09-18T00:00:00Z",'
        '"updatedAt":"2026-09-18T00:00:00Z"}}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpClubRideApi api = HttpClubRideApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final Ride ride = await api.publishRide('ride-1');

    expect(ride.status, RideStatus.published);
  });

  test('client refuses to invite a second Leader', () async {
    final HttpClubRideApi api = HttpClubRideApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    expect(
      () => api.inviteRideMember(
        rideId: 'ride-1',
        riderId: 'rider-2',
        role: RideRole.leader,
      ),
      throwsArgumentError,
    );
  });
}
