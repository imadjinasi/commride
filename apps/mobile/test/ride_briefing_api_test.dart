import 'package:commride_mobile/src/api/http_ride_briefing_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/ride_briefing.dart';
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

String briefingResponse({
  int revision = 1,
  bool acknowledged = false,
  bool routePlanIsCurrent = true,
}) {
  return '''
{
  "briefingView": {
    "briefing": {
      "id": "briefing-$revision",
      "rideId": "ride-1",
      "revision": $revision,
      "routePlanId": "plan-1",
      "createdByRiderId": "rider-leader",
      "scheduledStartAt": "2026-09-20T00:00:00Z",
      "leader": {
        "riderId": "rider-leader",
        "displayName": "Leader One"
      },
      "sweeper": null,
      "notes": "Meet at 05:30.",
      "isCurrent": true,
      "publishedAt": "2026-09-18T09:00:00Z"
    },
    "routePlan": {
      "id": "plan-1",
      "rideId": "ride-1",
      "revision": 1,
      "createdByRiderId": "rider-leader",
      "travelMode": "drive",
      "originLabel": "Cirebon",
      "origin": {"latitude": -6.732, "longitude": 108.552},
      "destinationLabel": "Bandung",
      "destination": {"latitude": -6.917, "longitude": 107.619},
      "distanceMeters": 130000,
      "durationSeconds": 9000,
      "encodedPolyline": "encoded-route",
      "isCurrent": true,
      "createdAt": "2026-09-18T00:00:00Z",
      "stops": [
        {
          "id": "stop-1",
          "sequence": 0,
          "label": "Fuel One",
          "formattedAddress": "Route Road",
          "location": {"latitude": -6.8, "longitude": 108.0},
          "stopType": "fuel",
          "checkpointType": "fuel",
          "plannedDurationMinutes": 15
        }
      ]
    },
    "readiness": {
      "expectedCount": 2,
      "readyCount": ${acknowledged ? 1 : 0},
      "currentRiderAcknowledged": $acknowledged
    },
    "routePlanIsCurrent": $routePlanIsCurrent
  }
}
''';
}

void main() {
  test('fetchBriefing uses Bearer token and maps the full view', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/rides/ride-1/briefing');
      expect(request.headers['authorization'], 'Bearer firebase-id-token');

      return http.Response(
        briefingResponse(),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpRideBriefingApi api = HttpRideBriefingApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final RideBriefingView? view = await api.fetchBriefing('ride-1');

    expect(view, isNotNull);
    expect(view!.briefing.revision, 1);
    expect(view.routePlan.stops.single.label, 'Fuel One');
    expect(view.readiness.readyCount, 0);
    expect(view.routePlanIsCurrent, isTrue);
  });

  test('fetchBriefing maps briefing_not_found to null', () async {
    final MockClient client = MockClient((http.Request request) async {
      return http.Response(
        '{"error":{"code":"briefing_not_found",'
        '"message":"This Ride does not have a published Briefing yet.",'
        '"requestId":"req-1"}}',
        404,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpRideBriefingApi api = HttpRideBriefingApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    expect(await api.fetchBriefing('ride-1'), isNull);
  });

  test('publishBriefing sends notes and maps a new revision', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/v1/rides/ride-1/briefing/publish',
      );
      expect(request.headers['authorization'], 'Bearer firebase-id-token');
      expect(request.body, contains('"notes":"Fuel before departure."'));

      return http.Response(
        briefingResponse(revision: 2),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpRideBriefingApi api = HttpRideBriefingApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final RideBriefingView view = await api.publishBriefing(
      rideId: 'ride-1',
      notes: 'Fuel before departure.',
    );

    expect(view.briefing.revision, 2);
  });

  test('acknowledgeBriefing maps current Rider readiness', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/v1/rides/ride-1/briefing/acknowledge',
      );
      expect(request.headers['authorization'], 'Bearer firebase-id-token');

      return http.Response(
        briefingResponse(acknowledged: true),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpRideBriefingApi api = HttpRideBriefingApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final RideBriefingView view =
        await api.acknowledgeBriefing('ride-1');

    expect(view.readiness.currentRiderAcknowledged, isTrue);
    expect(view.readiness.readyCount, 1);
  });
}
