import 'package:commride_mobile/src/active_ride/navigation_route_matcher.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects the fresh token for the persisted alternative geometry', () {
    final RouteOption plannedRoute = _route(
      polyline: _encode(<GeoPoint>[
        const GeoPoint(latitude: -6.70, longitude: 108.55),
        const GeoPoint(latitude: -6.82, longitude: 108.10),
        const GeoPoint(latitude: -6.92, longitude: 107.62),
      ]),
      distanceMeters: 128000,
      durationSeconds: 10800,
    );
    final SavedRoutePlan plan = _plan(plannedRoute);

    final RouteOption differentDefault = _route(
      token: 'token-default',
      polyline: _encode(<GeoPoint>[
        const GeoPoint(latitude: -6.70, longitude: 108.55),
        const GeoPoint(latitude: -6.45, longitude: 108.05),
        const GeoPoint(latitude: -6.92, longitude: 107.62),
      ]),
      distanceMeters: 126000,
      durationSeconds: 10400,
    );
    final RouteOption selectedAlternative = _route(
      token: 'token-selected',
      polyline: _encode(<GeoPoint>[
        const GeoPoint(latitude: -6.70, longitude: 108.55),
        const GeoPoint(latitude: -6.81, longitude: 108.11),
        const GeoPoint(latitude: -6.92, longitude: 107.62),
      ]),
      distanceMeters: 129000,
      durationSeconds: 11000,
    );

    final RouteOption? selected = selectNavigationRoute(
      plan,
      <RouteOption>[differentDefault, selectedAlternative],
    );

    expect(selected?.routeToken, 'token-selected');
  });

  test('rejects a materially different fresh route instead of silently switching', () {
    final SavedRoutePlan plan = _plan(
      _route(
        polyline: _encode(<GeoPoint>[
          const GeoPoint(latitude: -6.70, longitude: 108.55),
          const GeoPoint(latitude: -6.82, longitude: 108.10),
          const GeoPoint(latitude: -6.92, longitude: 107.62),
        ]),
        distanceMeters: 128000,
        durationSeconds: 10800,
      ),
    );

    final RouteOption candidate = _route(
      token: 'token-other',
      polyline: _encode(<GeoPoint>[
        const GeoPoint(latitude: -6.70, longitude: 108.55),
        const GeoPoint(latitude: -5.95, longitude: 108.05),
        const GeoPoint(latitude: -6.92, longitude: 107.62),
      ]),
      distanceMeters: 165000,
      durationSeconds: 15000,
    );

    expect(selectNavigationRoute(plan, <RouteOption>[candidate]), isNull);
  });

  test('ignores candidates without a usable route token', () {
    final RouteOption route = _route(
      polyline: _encode(<GeoPoint>[
        const GeoPoint(latitude: -6.70, longitude: 108.55),
        const GeoPoint(latitude: -6.92, longitude: 107.62),
      ]),
      distanceMeters: 120000,
      durationSeconds: 10000,
    );

    expect(selectNavigationRoute(_plan(route), <RouteOption>[route]), isNull);
  });
}

SavedRoutePlan _plan(RouteOption route) {
  return SavedRoutePlan(
    revision: 3,
    travelMode: RouteTravelMode.twoWheeler,
    originLabel: 'Start',
    origin: const GeoPoint(latitude: -6.70, longitude: 108.55),
    destinationLabel: 'Finish',
    destination: const GeoPoint(latitude: -6.92, longitude: 107.62),
    route: route,
    stops: const <PlanningStop>[],
  );
}

RouteOption _route({
  String? token,
  required String polyline,
  required int distanceMeters,
  required int durationSeconds,
}) {
  return RouteOption(
    routeIndex: 0,
    labels: const <String>[],
    distanceMeters: distanceMeters,
    durationSeconds: durationSeconds,
    encodedPolyline: polyline,
    routeToken: token,
    legs: <RouteLeg>[
      RouteLeg(
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
      ),
    ],
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
