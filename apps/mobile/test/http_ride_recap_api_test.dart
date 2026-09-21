import 'dart:convert';

import 'package:commride_mobile/src/api/http_ride_recap_api.dart';
import 'package:commride_mobile/src/api/ride_recap_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/ride_recap.dart';
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

Map<String, Object?> recapJson({
  int sampleCount = 0,
  int trackedRiderCount = 0,
  int? leaderTrackedDistanceMeters,
}) {
  return <String, Object?>{
    'rideId': 'ride-1',
    'title': 'Sunday Ride',
    'actualStartAt': '2026-09-18T09:00:00Z',
    'endedAt': '2026-09-18T12:00:00Z',
    'durationSeconds': 10800,
    'participants': <Object?>[
      <String, Object?>{
        'riderId': 'rider-1',
        'displayName': 'Rider One',
        'role': 'leader',
        'membershipStatus': 'active',
      },
    ],
    'plannedRoute': <String, Object?>{
      'routePlanId': 'plan-1',
      'revision': 2,
      'originLabel': 'Cirebon',
      'destinationLabel': 'Kuningan',
      'distanceMeters': 42000,
      'durationSeconds': 3600,
      'stopCount': 2,
    },
    'journey': <String, Object?>{
      'sampleCount': sampleCount,
      'trackedRiderCount': trackedRiderCount,
      'firstObservedAt': sampleCount == 0 ? null : '2026-09-18T09:01:00Z',
      'lastObservedAt': sampleCount == 0 ? null : '2026-09-18T11:59:00Z',
      'leaderTrackedDistanceMeters': leaderTrackedDistanceMeters,
    },
    'checkpoints': <Object?>[
      <String, Object?>{
        'checkpointId': 'stop-1',
        'label': 'Regroup 1',
        'checkpointType': 'regroup',
        'checkInCount': 8,
        'participantCount': 10,
        'releasedAt': '2026-09-18T10:30:00Z',
      },
    ],
    'incidents': <Object?>[
      <String, Object?>{
        'sosId': 'sos-1',
        'riderId': 'rider-2',
        'riderDisplayName': 'Rider Two',
        'state': 'resolved',
        'reason': 'Ban bocor',
        'raisedAt': '2026-09-18T10:45:00Z',
        'closedAt': '2026-09-18T10:52:00Z',
      },
    ],
    'generatedAt': '2026-09-18T12:00:01Z',
  };
}

void main() {
  test(
    'fetchRecap authenticates and preserves no-sample truthfulness',
    () async {
      late http.Request captured;
      final MockClient client = MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{'recap': recapJson()}),
          200,
        );
      });
      final HttpRideRecapApi api = HttpRideRecapApi(
        apiBaseUrl: Uri.parse('https://api.commride.invalid'),
        authGateway: FakeAuthGateway(),
        client: client,
      );

      final RideRecap recap = await api.fetchRecap('ride-1');

      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/rides/ride-1/recap');
      expect(captured.headers['authorization'], 'Bearer token-1');
      expect(recap.durationSeconds, 10800);
      expect(recap.journey.hasSamples, isFalse);
      expect(recap.journey.leaderTrackedDistanceMeters, isNull);
      expect(recap.checkpoints.single.checkInCount, 8);
      expect(recap.incidents.single.state, 'resolved');
    },
  );

  test(
    'fetchRecap preserves sampled journey separately from planned route',
    () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'recap': recapJson(
              sampleCount: 60,
              trackedRiderCount: 9,
              leaderTrackedDistanceMeters: 39750,
            ),
          }),
          200,
        );
      });
      final HttpRideRecapApi api = HttpRideRecapApi(
        apiBaseUrl: Uri.parse('https://api.commride.invalid'),
        authGateway: FakeAuthGateway(),
        client: client,
      );

      final RideRecap recap = await api.fetchRecap('ride-1');

      expect(recap.plannedRoute?.distanceMeters, 42000);
      expect(recap.journey.leaderTrackedDistanceMeters, 39750);
      expect(recap.journey.sampleCount, 60);
      expect(recap.journey.trackedRiderCount, 9);
    },
  );

  test('fetchRecap keeps structured API errors', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'error': <String, Object?>{
            'code': 'ride_not_completed',
            'message': 'Ride Recap is available after the Ride is completed.',
          },
        }),
        409,
      );
    });
    final HttpRideRecapApi api = HttpRideRecapApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: FakeAuthGateway(),
      client: client,
    );

    expect(
      () => api.fetchRecap('ride-1'),
      throwsA(
        isA<RideRecapApiException>().having(
          (RideRecapApiException error) => error.code,
          'code',
          'ride_not_completed',
        ),
      ),
    );
  });
}
