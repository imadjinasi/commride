import 'package:commride_mobile/src/api/http_checkpoint_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/ride_checkpoint.dart';
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

String checkpointResponse({
  bool currentRiderCheckedIn = false,
  bool firstReleased = false,
}) {
  return '''
{
  "checkpointView": {
    "rideId": "ride-1",
    "routePlanId": "plan-2",
    "routePlanRevision": 2,
    "checkpoints": [
      {
        "checkpointId": "cp-fuel",
        "sequence": 0,
        "label": "Fuel One",
        "formattedAddress": "SPBU One",
        "latitude": -6.8,
        "longitude": 108.0,
        "checkpointType": "fuel",
        "plannedDurationMinutes": 15,
        "state": "${firstReleased ? 'released' : 'current'}",
        "expectedCount": 2,
        "checkedInCount": ${currentRiderCheckedIn ? 1 : 0},
        "missingCount": ${currentRiderCheckedIn ? 1 : 2},
        "currentRiderCheckedIn": $currentRiderCheckedIn,
        "releasedAt": ${firstReleased ? '"2026-09-18T10:05:00Z"' : 'null'},
        "participants": [
          {
            "riderId": "rider-leader",
            "displayName": "Leader One",
            "role": "leader",
            "membershipStatus": "joined",
            "checkedInAt": null
          },
          {
            "riderId": "rider-member",
            "displayName": "Member One",
            "role": "member",
            "membershipStatus": "joined",
            "checkedInAt": ${currentRiderCheckedIn ? '"2026-09-18T10:00:00Z"' : 'null'}
          }
        ]
      }
    ]
  }
}
''';
}

void main() {
  test('fetchCheckpoints uses *** and maps Checkpoint state', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/rides/ride-1/checkpoints');
      expect(
        request.headers['authorization'],
        <String>['Bearer', 'firebase-id-token'].join(' '),
      );
      return http.Response(checkpointResponse(), 200);
    });

    final HttpCheckpointApi api = HttpCheckpointApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final RideCheckpointView view = await api.fetchCheckpoints('ride-1');

    expect(view.routePlanRevision, 2);
    expect(view.checkpoints.single.label, 'Fuel One');
    expect(view.checkpoints.single.state, RideCheckpointState.current);
    expect(view.checkpoints.single.missingCount, 2);
  });

  test('checkIn calls the authenticated self check-in endpoint', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/rides/ride-1/checkpoints/cp-fuel/check-in');
      return http.Response(
        checkpointResponse(currentRiderCheckedIn: true),
        200,
      );
    });

    final HttpCheckpointApi api = HttpCheckpointApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final RideCheckpointView view = await api.checkIn(
      rideId: 'ride-1',
      checkpointId: 'cp-fuel',
    );

    expect(view.checkpoints.single.currentRiderCheckedIn, isTrue);
    expect(view.checkpoints.single.checkedInCount, 1);
  });

  test('release maps released state without sending a request body', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/rides/ride-1/checkpoints/cp-fuel/release');
      expect(request.body, isEmpty);
      return http.Response(checkpointResponse(firstReleased: true), 200);
    });

    final HttpCheckpointApi api = HttpCheckpointApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final RideCheckpointView view = await api.release(
      rideId: 'ride-1',
      checkpointId: 'cp-fuel',
    );

    expect(view.checkpoints.single.state, RideCheckpointState.released);
    expect(view.checkpoints.single.releasedAt, isNotNull);
  });

  test('structured API errors remain explicit', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        '{"error":{"code":"checkpoint_release_order_conflict",'
        '"message":"Earlier Checkpoints must be released first."}}',
        409,
      );
    });

    final HttpCheckpointApi api = HttpCheckpointApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    await expectLater(
      () => api.release(rideId: 'ride-1', checkpointId: 'cp-regroup'),
      throwsA(
        isA<Object>().having(
          (Object error) => error.toString(),
          'error',
          contains('checkpoint_release_order_conflict'),
        ),
      ),
    );
  });
}
