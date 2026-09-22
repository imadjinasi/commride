import 'package:commride_mobile/src/active_ride/commride_navigation_engine.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GPS jitter near the route never becomes a reroute', () {
    final CommRideNavigationEngine engine = CommRideNavigationEngine(_plan());
    final DateTime start = DateTime.utc(2026, 9, 22, 8);

    for (int second = 0; second < 30; second += 3) {
      final CommRideNavigationSnapshot state = engine.update(
        GeoPoint(
          latitude: -6.7002,
          longitude: 108.01 + second / 10000,
        ),
        start.add(Duration(seconds: second)),
      );
      expect(state.phase, CommRideNavigationPhase.onRoute);
      expect(state.shouldOfferReroute, isFalse);
    }
  });

  test('sustained deviation becomes recovery without replacing the plan', () {
    final SavedRoutePlan plan = _plan();
    final CommRideNavigationEngine engine = CommRideNavigationEngine(plan);
    final DateTime start = DateTime.utc(2026, 9, 22, 8);

    final GeoPoint offRoute = const GeoPoint(
      latitude: -6.7010,
      longitude: 108.025,
    );

    final first = engine.update(offRoute, start);
    expect(first.phase, CommRideNavigationPhase.suspectedOffRoute);

    final confirmed = engine.update(
      offRoute,
      start.add(const Duration(seconds: 9)),
    );
    expect(confirmed.phase, CommRideNavigationPhase.confirmedOffRoute);
    expect(engine.plan.revision, plan.revision);
    expect(confirmed.rejoinTarget, isNotNull);

    final recovery = engine.update(
      offRoute,
      start.add(const Duration(seconds: 10)),
    );
    expect(recovery.phase, CommRideNavigationPhase.recovery);
    expect(recovery.rejoinTarget!.longitude, greaterThan(offRoute.longitude));
  });

  test('reroute is offered only after meaningful deviation', () {
    final CommRideNavigationEngine engine = CommRideNavigationEngine(_plan());
    final DateTime start = DateTime.utc(2026, 9, 22, 8);
    const GeoPoint offRoute = GeoPoint(
      latitude: -6.7010,
      longitude: 108.025,
    );

    engine.update(offRoute, start);
    engine.update(offRoute, start.add(const Duration(seconds: 9)));

    final early = engine.update(
      offRoute,
      start.add(const Duration(seconds: 15)),
    );
    expect(early.shouldOfferReroute, isFalse);

    final later = engine.update(
      offRoute,
      start.add(const Duration(seconds: 30)),
    );
    expect(later.shouldOfferReroute, isTrue);
  });

  test('rejoining the accepted route is explicit and stabilizes on-route', () {
    final CommRideNavigationEngine engine = CommRideNavigationEngine(_plan());
    final DateTime start = DateTime.utc(2026, 9, 22, 8);
    const GeoPoint offRoute = GeoPoint(
      latitude: -6.7010,
      longitude: 108.025,
    );
    const GeoPoint onRoute = GeoPoint(
      latitude: -6.7000,
      longitude: 108.030,
    );

    engine.update(offRoute, start);
    engine.update(offRoute, start.add(const Duration(seconds: 9)));
    engine.update(offRoute, start.add(const Duration(seconds: 10)));

    final rejoined = engine.update(
      onRoute,
      start.add(const Duration(seconds: 11)),
    );
    expect(rejoined.phase, CommRideNavigationPhase.rejoined);

    final stable = engine.update(
      onRoute,
      start.add(const Duration(seconds: 17)),
    );
    expect(stable.phase, CommRideNavigationPhase.onRoute);
  });

  test('selects the next normalized maneuver by route progress', () {
    final CommRideNavigationEngine engine = CommRideNavigationEngine(_plan());
    final state = engine.update(
      const GeoPoint(latitude: -6.7000, longitude: 108.005),
      DateTime.utc(2026, 9, 22, 8),
    );

    expect(state.nextManeuver?.instruction, 'Belok kanan ke Jalan B');
    expect(state.distanceToNextManeuverMeters, greaterThan(0));
    expect(state.routeBearingDegrees, closeTo(90, 2));
  });
}

SavedRoutePlan _plan() {
  final List<GeoPoint> points = <GeoPoint>[
    const GeoPoint(latitude: -6.7000, longitude: 108.000),
    const GeoPoint(latitude: -6.7000, longitude: 108.020),
    const GeoPoint(latitude: -6.7000, longitude: 108.040),
    const GeoPoint(latitude: -6.7000, longitude: 108.060),
  ];

  return SavedRoutePlan(
    revision: 4,
    travelMode: RouteTravelMode.twoWheeler,
    originLabel: 'Start',
    origin: points.first,
    destinationLabel: 'Finish',
    destination: points.last,
    route: RouteOption(
      routeIndex: 0,
      labels: const <String>['RECOMMENDED'],
      distanceMeters: 6600,
      durationSeconds: 600,
      encodedPolyline: _encode(points),
      legs: const <RouteLeg>[
        RouteLeg(distanceMeters: 6600, durationSeconds: 600),
      ],
      maneuvers: const <RouteManeuver>[
        RouteManeuver(
          instruction: 'Belok kanan ke Jalan B',
          type: 'right',
          distanceMeters: 200,
          durationSeconds: 20,
          beginShapeIndex: 1,
          endShapeIndex: 2,
          verbalPreTransitionInstruction:
              'Dalam 200 meter, belok kanan.',
          verbalTransitionInstruction: 'Belok kanan.',
          verbalPostTransitionInstruction: null,
        ),
      ],
    ),
    stops: const <PlanningStop>[],
  );
}

String _encode(List<GeoPoint> points) {
  int lastLatitude = 0;
  int lastLongitude = 0;
  final StringBuffer output = StringBuffer();

  for (final GeoPoint point in points) {
    final int latitude = (point.latitude * 1e5).round();
    final int longitude = (point.longitude * 1e5).round();
    _encodeValue(latitude - lastLatitude, output);
    _encodeValue(longitude - lastLongitude, output);
    lastLatitude = latitude;
    lastLongitude = longitude;
  }
  return output.toString();
}

void _encodeValue(int signed, StringBuffer output) {
  int value = signed < 0 ? ~(signed << 1) : signed << 1;
  while (value >= 0x20) {
    output.writeCharCode((0x20 | (value & 0x1f)) + 63);
    value >>= 5;
  }
  output.writeCharCode(value + 63);
}
