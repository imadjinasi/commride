import 'package:commride_mobile/src/api/ride_briefing_api.dart';
import 'package:commride_mobile/src/api/route_planner_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_briefing.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:commride_mobile/src/screens/ride/ride_briefing_screen.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SavedRoutePlan routePlan() {
  return const SavedRoutePlan(
    revision: 1,
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
      encodedPolyline: 'encoded-route',
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
}

Ride ride() {
  return Ride(
    id: 'ride-1',
    clubId: 'club-1',
    title: 'Sunday Ride',
    status: RideStatus.published,
    scheduledStartAt: DateTime.utc(2026, 9, 20),
    actualStartAt: null,
    endedAt: null,
    notes: 'Initial Ride note.',
  );
}

RideBriefingView briefingView({
  bool acknowledged = false,
  bool routePlanIsCurrent = true,
  int revision = 1,
  int readyCount = 0,
}) {
  return RideBriefingView(
    briefing: RideBriefing(
      id: 'briefing-$revision',
      rideId: 'ride-1',
      revision: revision,
      routePlanId: 'plan-1',
      createdByRiderId: 'rider-leader',
      scheduledStartAt: DateTime.utc(2026, 9, 20),
      leader: const BriefingRoleIdentity(
        riderId: 'rider-leader',
        displayName: 'Leader One',
      ),
      sweeper: const BriefingRoleIdentity(
        riderId: 'rider-sweeper',
        displayName: 'Sweeper One',
      ),
      notes: 'Meet at 05:30.',
      isCurrent: true,
      publishedAt: DateTime.utc(2026, 9, 18, 9),
    ),
    routePlan: routePlan(),
    readiness: BriefingReadiness(
      expectedCount: 2,
      readyCount: readyCount,
      currentRiderAcknowledged: acknowledged,
    ),
    routePlanIsCurrent: routePlanIsCurrent,
  );
}

class FakeRoutePlannerApi implements RoutePlannerApi {
  FakeRoutePlannerApi(this.plan);

  final SavedRoutePlan? plan;

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<RouteOption>> computeRoutes({
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required List<PlanningStop> stops,
    required RouteTravelMode travelMode,
    required bool computeAlternatives,
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AlongRoutePlace>> searchAlongRoute({
    required String textQuery,
    required RouteOption route,
    required RouteTravelMode travelMode,
  }) {
    throw UnimplementedError();
  }
}

class FakeRideBriefingApi implements RideBriefingApi {
  FakeRideBriefingApi(this.view);

  RideBriefingView? view;
  int publishCalls = 0;
  int acknowledgeCalls = 0;
  String? lastPublishedNotes;

  @override
  Future<RideBriefingView?> fetchBriefing(String rideId) async => view;

  @override
  Future<RideBriefingView> publishBriefing({
    required String rideId,
    required String? notes,
  }) async {
    publishCalls += 1;
    lastPublishedNotes = notes;
    view = briefingView();
    return view!;
  }

  @override
  Future<RideBriefingView> acknowledgeBriefing(String rideId) async {
    acknowledgeCalls += 1;
    view = briefingView(acknowledged: true, readyCount: 1);
    return view!;
  }
}

Widget buildScreen({
  required RideBriefingApi briefingApi,
  SavedRoutePlan? currentPlan,
  bool canPublish = false,
  bool canAcknowledge = true,
}) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: RideBriefingScreen(
      ride: ride(),
      rideBriefingApi: briefingApi,
      routePlannerApi: FakeRoutePlannerApi(currentPlan),
      canPublish: canPublish,
      canAcknowledge: canAcknowledge,
    ),
  );
}

void main() {
  testWidgets('Leader can publish Briefing from the current RoutePlan', (
    WidgetTester tester,
  ) async {
    final FakeRideBriefingApi api = FakeRideBriefingApi(null);

    await tester.pumpWidget(
      buildScreen(briefingApi: api, currentPlan: routePlan(), canPublish: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Publish Briefing'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Fuel One'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Fuel One'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Publish Briefing'),
      -240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Publish Briefing'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Fuel before departure.');
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await tester.pumpAndSettle();

    expect(api.publishCalls, 1);
    expect(api.lastPublishedNotes, 'Fuel before departure.');
    expect(find.text('Briefing v1'), findsOneWidget);
  });

  testWidgets('dismissing publish dialog does not publish', (
    WidgetTester tester,
  ) async {
    final FakeRideBriefingApi api = FakeRideBriefingApi(null);

    await tester.pumpWidget(
      buildScreen(briefingApi: api, currentPlan: routePlan(), canPublish: true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publish Briefing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    expect(api.publishCalls, 0);
  });

  testWidgets('joined Rider can acknowledge the current Briefing', (
    WidgetTester tester,
  ) async {
    final FakeRideBriefingApi api = FakeRideBriefingApi(briefingView());

    await tester.pumpWidget(buildScreen(briefingApi: api));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Ready · Sudah dibaca'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Ready · Sudah dibaca'));
    await tester.pumpAndSettle();

    expect(api.acknowledgeCalls, 1);
    await tester.scrollUntilVisible(
      find.text('1/2 Rider sudah membaca Briefing ini.'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1/2 Rider sudah membaca Briefing ini.'), findsOneWidget);
  });

  testWidgets('stale Briefing blocks Ready and explains republish', (
    WidgetTester tester,
  ) async {
    final FakeRideBriefingApi api = FakeRideBriefingApi(
      briefingView(routePlanIsCurrent: false),
    );

    await tester.pumpWidget(buildScreen(briefingApi: api));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('RoutePlan sudah berubah setelah Briefing'),
      findsOneWidget,
    );
    expect(find.text('Ready · Sudah dibaca'), findsNothing);
  });
}
