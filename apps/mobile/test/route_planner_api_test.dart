import 'package:commride_mobile/src/api/http_route_planner_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
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
  test('computeRoutes uses Bearer token and maps route alternatives', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/maps/routes');
      expect(request.headers['authorization'], 'Bearer firebase-id-token');
      expect(request.body, contains('"computeAlternatives":true'));
      expect(request.body, contains('"travelMode":"two_wheeler"'));

      return http.Response(
        '{"routes":[{"routeIndex":0,"labels":["DEFAULT_ROUTE"],'
        '"distanceMeters":120000,"durationSeconds":7200,'
        '"encodedPolyline":"encoded-route",'
        '"legs":[{"distanceMeters":120000,"durationSeconds":7200}]}]}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpRoutePlannerApi api = HttpRoutePlannerApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final List<RouteOption> routes = await api.computeRoutes(
      origin: const ResolvedPlace(
        reference: 'origin',
        formattedAddress: 'Cirebon',
        location: GeoPoint(latitude: -6.732, longitude: 108.552),
      ),
      destination: const ResolvedPlace(
        reference: 'destination',
        formattedAddress: 'Bandung',
        location: GeoPoint(latitude: -6.917, longitude: 107.619),
      ),
      stops: const <PlanningStop>[],
      travelMode: RouteTravelMode.twoWheeler,
      computeAlternatives: true,
    );

    expect(routes, hasLength(1));
    expect(routes.single.distanceMeters, 120000);
    expect(routes.single.durationSeconds, 7200);
  });

  test('fetchRoutePlan maps route_plan_not_found to null', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/rides/ride-1/route-plan');
      expect(request.headers['authorization'], 'Bearer firebase-id-token');

      return http.Response(
        '{"error":{"code":"route_plan_not_found",'
        '"message":"This Ride does not have a saved RoutePlan yet.",'
        '"requestId":"req-1"}}',
        404,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpRoutePlannerApi api = HttpRoutePlannerApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    expect(await api.fetchRoutePlan('ride-1'), isNull);
  });

  test('saveRoutePlan sends ordered stops and maps saved revision', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/v1/rides/ride-1/route-plan');
      expect(request.headers['authorization'], 'Bearer firebase-id-token');

      expect(request.body, contains('"label":"Fuel One"'));
      expect(request.body, contains('"checkpointType":"fuel"'));

      return http.Response(
        '{"routePlan":{"id":"plan-1","rideId":"ride-1","revision":2,'
        '"createdByRiderId":"rider-1","travelMode":"drive",'
        '"originLabel":"Cirebon","origin":{"latitude":-6.732,"longitude":108.552},'
        '"destinationLabel":"Bandung",'
        '"destination":{"latitude":-6.917,"longitude":107.619},'
        '"distanceMeters":130000,"durationSeconds":9000,'
        '"encodedPolyline":"encoded-saved","isCurrent":true,'
        '"createdAt":"2026-09-18T00:00:00Z",'
        '"stops":[{"id":"stop-1","sequence":0,"label":"Fuel One",'
        '"formattedAddress":"Route Road",'
        '"location":{"latitude":-6.8,"longitude":108.0},'
        '"stopType":"fuel","checkpointType":"fuel",'
        '"plannedDurationMinutes":15}]}}',
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });

    final HttpRoutePlannerApi api = HttpRoutePlannerApi(
      apiBaseUrl: Uri.parse('https://api.commride.invalid'),
      authGateway: TokenAuthGateway(),
      client: client,
    );

    final SavedRoutePlan saved = await api.saveRoutePlan(
      rideId: 'ride-1',
      origin: const ResolvedPlace(
        reference: 'origin',
        formattedAddress: 'Cirebon',
        location: GeoPoint(latitude: -6.732, longitude: 108.552),
      ),
      destination: const ResolvedPlace(
        reference: 'destination',
        formattedAddress: 'Bandung',
        location: GeoPoint(latitude: -6.917, longitude: 107.619),
      ),
      route: const RouteOption(
        routeIndex: 0,
        labels: <String>[],
        distanceMeters: 130000,
        durationSeconds: 9000,
        encodedPolyline: 'encoded-saved',
        legs: <RouteLeg>[],
      ),
      travelMode: RouteTravelMode.drive,
      stops: const <PlanningStop>[
        PlanningStop(
          label: 'Fuel One',
          formattedAddress: 'Route Road',
          location: GeoPoint(latitude: -6.8, longitude: 108.0),
          stopType: StopType.fuel,
          checkpointType: CheckpointType.fuel,
          plannedDurationMinutes: 15,
        ),
      ],
    );

    expect(saved.revision, 2);
    expect(saved.stops.single.checkpointType, CheckpointType.fuel);
  });
}
