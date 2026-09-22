import 'package:commride_mobile/src/maps/commride_navigation_map_view.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(
      geometry['coordinates'],
      <Object>[
        <double>[108.50, -6.70],
        <double>[108.49, -6.71],
        <double>[108.48, -6.72],
      ],
    );
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
      points: const <GeoPoint>[
        GeoPoint(latitude: -6.70, longitude: 108.50),
      ],
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
