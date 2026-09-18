import 'package:commride_mobile/src/api/route_planner_api.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:commride_mobile/src/screens/ride/route_planner_screen.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const SavedRoutePlan savedPlan = SavedRoutePlan(
  revision: 3,
  travelMode: RouteTravelMode.drive,
  originLabel: 'Cirebon',
  origin: GeoPoint(latitude: -6.732, longitude: 108.552),
  destinationLabel: 'Bandung',
  destination: GeoPoint(latitude: -6.917, longitude: 107.619),
  route: RouteOption(
    routeIndex: 0,
    labels: <String>[],
    distanceMeters: 130000,
    durationSeconds: 9000,
    encodedPolyline: 'saved-route',
    legs: <RouteLeg>[],
  ),
  stops: <PlanningStop>[
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

class FakeRoutePlannerApi implements RoutePlannerApi {
  FakeRoutePlannerApi({
    this.plan = savedPlan,
    this.failRecompute = false,
  });

  final SavedRoutePlan? plan;
  final bool failRecompute;

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    return const <PlaceSuggestion>[];
  }

  @override
  Future<List<RouteOption>> computeRoutes({
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required List<PlanningStop> stops,
    required RouteTravelMode travelMode,
    required bool computeAlternatives,
  }) async {
    if (failRecompute) {
      throw const RoutePlannerApiException(
        statusCode: 502,
        code: 'maps_provider_error',
        message: 'Provider unavailable.',
      );
    }

    return <RouteOption>[savedPlan.route];
  }

  @override
  Future<SavedRoutePlan?> fetchRoutePlan(String rideId) async => plan;

  @override
  Future<ResolvedPlace> resolvePlace({
    required String reference,
    required String sessionToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SavedRoutePlan> saveRoutePlan({
    required String rideId,
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required RouteOption route,
    required RouteTravelMode travelMode,
    required List<PlanningStop> stops,
  }) async {
    return savedPlan;
  }

  @override
  Future<List<AlongRoutePlace>> searchAlongRoute({
    required String textQuery,
    required RouteOption route,
    required RouteTravelMode travelMode,
  }) async {
    return const <AlongRoutePlace>[];
  }
}

Widget buildPlanner({
  required RoutePlannerApi api,
  required bool canEdit,
}) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: RoutePlannerScreen(
      rideId: 'ride-1',
      routePlannerApi: api,
      canEdit: canEdit,
    ),
  );
}

void main() {
  testWidgets('joined participant can read a saved RoutePlan', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildPlanner(
        api: FakeRoutePlannerApi(),
        canEdit: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RoutePlan revision 3'), findsOneWidget);
    expect(find.text('130 km · 2 j 30 mnt'), findsOneWidget);
    expect(find.text('Fuel One'), findsOneWidget);
    expect(find.text('Simpan RoutePlan'), findsNothing);
  });

  testWidgets('failed recalculation preserves the last valid Stop', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildPlanner(
        api: FakeRoutePlannerApi(failRecompute: true),
        canEdit: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fuel One'), findsOneWidget);

    await tester.tap(find.byTooltip('Hapus Stop'));
    await tester.pumpAndSettle();

    expect(find.text('Fuel One'), findsOneWidget);
    expect(
      find.textContaining('Route terakhir tetap dipakai'),
      findsOneWidget,
    );
  });
}
