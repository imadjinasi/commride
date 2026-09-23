import 'package:commride_mobile/src/api/ride_briefing_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_briefing.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:commride_mobile/src/screens/ride/ride_pre_start_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Ride testRide = Ride(
  id: 'ride-1',
  clubId: 'club-1',
  title: 'Morning Ride',
  status: RideStatus.published,
  scheduledStartAt: null,
  actualStartAt: null,
  endedAt: null,
  notes: null,
);

const SavedRoutePlan testPlan = SavedRoutePlan(
  revision: 3,
  travelMode: RouteTravelMode.twoWheeler,
  originLabel: 'Start',
  origin: GeoPoint(latitude: -6.7, longitude: 108.5),
  destinationLabel: 'Finish',
  destination: GeoPoint(latitude: -6.8, longitude: 108.6),
  route: RouteOption(
    routeIndex: 0,
    labels: <String>[],
    distanceMeters: 12000,
    durationSeconds: 1800,
    encodedPolyline: '',
    legs: <RouteLeg>[],
  ),
  stops: <PlanningStop>[],
);

RideBriefingView briefingView({bool routePlanIsCurrent = true}) {
  return RideBriefingView(
    briefing: RideBriefing(
      id: 'briefing-1',
      rideId: 'ride-1',
      revision: 2,
      routePlanId: 'route-3',
      createdByRiderId: 'leader-1',
      scheduledStartAt: null,
      leader: const BriefingRoleIdentity(
        riderId: 'leader-1',
        displayName: 'Leader',
      ),
      sweeper: null,
      notes: null,
      isCurrent: true,
      publishedAt: DateTime.utc(2026, 9, 23, 1),
    ),
    routePlan: testPlan,
    readiness: const BriefingReadiness(
      expectedCount: 4,
      readyCount: 3,
      currentRiderAcknowledged: true,
    ),
    routePlanIsCurrent: routePlanIsCurrent,
  );
}

class FakeBriefingApi implements RideBriefingApi {
  FakeBriefingApi(this.view);

  final RideBriefingView? view;

  @override
  Future<RideBriefingView?> fetchBriefing(String rideId) async => view;

  @override
  Future<RideBriefingView> acknowledgeBriefing(String rideId) {
    throw UnimplementedError();
  }

  @override
  Future<RideBriefingView> publishBriefing({
    required String rideId,
    required String? notes,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('pre-start shows advisory readiness without blocking start', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RidePreStartScreen(
          ride: testRide,
          rideBriefingApi: FakeBriefingApi(briefingView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3/4 Rider Ready'), findsOneWidget);
    expect(find.text('1 Rider belum menandai Ready.'), findsOneWidget);
    expect(
      find.text('Readiness bersifat advisory dan tidak memblokir Start Ride.'),
      findsOneWidget,
    );
    expect(find.text('Start Ride'), findsOneWidget);
  });

  testWidgets('missing briefing is explicit but remains advisory', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RidePreStartScreen(
          ride: testRide,
          rideBriefingApi: FakeBriefingApi(null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Briefing belum dipublikasikan'), findsOneWidget);
    expect(find.text('Tetap Start Ride'), findsOneWidget);
  });

  testWidgets('stale briefing warns that RoutePlan changed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RidePreStartScreen(
          ride: testRide,
          rideBriefingApi: FakeBriefingApi(
            briefingView(routePlanIsCurrent: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('RoutePlan sudah berubah'), findsOneWidget);
    expect(find.text('Tetap Start Ride'), findsOneWidget);
  });
}
