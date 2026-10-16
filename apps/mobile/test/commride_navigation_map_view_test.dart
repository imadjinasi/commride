import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/maps/commride_navigation_map_view.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LiveRiderPresence rider(
    String id,
    String name,
    RideRole role, {
    LivePresenceFreshness freshness = LivePresenceFreshness.live,
    double latitude = -6.73,
  }) {
    final DateTime at = DateTime.utc(2026, 10, 16, 8);
    return LiveRiderPresence(
      riderId: id,
      displayName: name,
      role: role,
      latitude: latitude,
      longitude: 108.55,
      observedAt: at,
      receivedAt: at,
      movement: RideMovementState.moving,
      freshness: freshness,
    );
  }

  test('group markers skip this phone and show role and freshness', () {
    final Map<String, dynamic> data = riderMarkersGeoJson(
      <LiveRiderPresence>[
        rider('me', 'Saya', RideRole.member),
        rider('lead', 'Andi', RideRole.leader),
        rider(
          'sweep',
          'Budi',
          RideRole.sweeper,
          freshness: LivePresenceFreshness.stale,
        ),
      ],
      DateTime.utc(2026, 10, 16, 8),
      selfRiderId: 'me',
    );
    final List<Map<String, dynamic>> props = (data['features'] as List<Object?>)
        .map(
          (Object? f) =>
              (f! as Map<String, dynamic>)['properties']
                  as Map<String, dynamic>,
        )
        .toList();

    expect(props, hasLength(2));
    expect(props[0]['initial'], 'L');
    expect(props[0]['label'], 'Andi');
    expect(props[1]['initial'], 'S');
    expect(props[1]['label'], 'Budi\nlama');
    expect(props[1]['color'], isNot(props[0]['color']));
  });

  test('group framing covers every Rider and this phone', () {
    final bounds = groupBounds(<LiveRiderPresence>[
      rider('a', 'A', RideRole.member, latitude: -6.70),
      rider('b', 'B', RideRole.member, latitude: -6.80),
    ], const GeoPoint(latitude: -6.75, longitude: 108.60))!;

    expect(bounds.southwest.latitude, closeTo(-6.80, 1e-9));
    expect(bounds.northeast.latitude, closeTo(-6.70, 1e-9));
    expect(bounds.northeast.longitude, closeTo(108.60, 1e-9));
    expect(groupBounds(const <LiveRiderPresence>[], null), isNull);
  });

  test('traffic line GeoJSON follows the reported affected road geometry', () {
    final TrafficIncident incident = _incident(
      category: 'roadClosed',
      points: const <GeoPoint>[
        GeoPoint(latitude: -6.70, longitude: 108.50),
        GeoPoint(latitude: -6.71, longitude: 108.49),
        GeoPoint(latitude: -6.72, longitude: 108.48),
      ],
    );

    final Map<String, dynamic> data = trafficIncidentLineGeoJson(
      <TrafficIncident>[incident],
    );
    final List<Object?> features = data['features'] as List<Object?>;
    final Map<String, dynamic> feature =
        features.single as Map<String, dynamic>;
    final Map<String, dynamic> geometry =
        feature['geometry'] as Map<String, dynamic>;
    final Map<String, dynamic> properties =
        feature['properties'] as Map<String, dynamic>;

    expect(geometry['type'], 'LineString');
    expect(geometry['coordinates'], <Object>[
      <double>[108.50, -6.70],
      <double>[108.49, -6.71],
      <double>[108.48, -6.72],
    ]);
    expect(properties['color'], '#B71C1C');
  });

  test('point traffic GeoJSON keeps category label and first location', () {
    final TrafficIncident incident = _incident(
      category: 'roadWorks',
      description: 'Perbaikan jembatan',
      points: const <GeoPoint>[
        GeoPoint(latitude: -6.70, longitude: 108.50),
        GeoPoint(latitude: -6.71, longitude: 108.49),
      ],
    );

    final Map<String, dynamic> data = trafficIncidentPointGeoJson(
      <TrafficIncident>[incident],
    );
    final List<Object?> features = data['features'] as List<Object?>;
    final Map<String, dynamic> feature =
        features.single as Map<String, dynamic>;
    final Map<String, dynamic> properties =
        feature['properties'] as Map<String, dynamic>;

    expect(properties['label'], 'Perbaikan jalan · Perbaikan jembatan');
    expect(properties['color'], '#F57C00');
  });

  test('point-only incident is not fabricated as an affected road line', () {
    final TrafficIncident incident = _incident(
      category: 'accident',
      points: const <GeoPoint>[GeoPoint(latitude: -6.70, longitude: 108.50)],
    );

    final Map<String, dynamic> data = trafficIncidentLineGeoJson(
      <TrafficIncident>[incident],
    );

    expect(data['features'], isEmpty);
  });
}

TrafficIncident _incident({
  required String category,
  required List<GeoPoint> points,
  String? description,
}) {
  return TrafficIncident(
    id: 'incident-1',
    category: category,
    magnitudeOfDelay: null,
    description: description,
    from: null,
    to: null,
    delaySeconds: null,
    lengthMeters: null,
    startTime: null,
    endTime: null,
    probabilityOfOccurrence: null,
    numberOfReports: null,
    lastReportTime: null,
    points: points,
  );
}
