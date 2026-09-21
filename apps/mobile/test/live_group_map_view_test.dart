import 'package:commride_mobile/src/active_ride/live_group_map_models.dart';
import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/maps/live_group_map_view.dart';
import 'package:commride_mobile/src/maps/map_style_scope.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 9, 21, 8);
  LiveGroupMapPresentation presentation({bool offline = false}) {
    return LiveGroupMapPresentation.fromPresences(
      presences: <LiveRiderPresence>[
        LiveRiderPresence(
          riderId: 'rider-1',
          displayName: 'Rider One',
          role: RideRole.leader,
          latitude: -6.732,
          longitude: 108.552,
          observedAt: now.subtract(const Duration(seconds: 45)),
          receivedAt: now.subtract(const Duration(seconds: 44)),
          movement: RideMovementState.stopped,
          freshness: offline
              ? LivePresenceFreshness.offline
              : LivePresenceFreshness.live,
        ),
      ],
      now: now,
    );
  }

  test('GeoJSON keeps last-known labels and longitude-latitude order', () {
    final Map<String, dynamic> json = riderMapGeoJson(presentation(), now);
    final Map<String, dynamic> feature =
        (json['features'] as List<dynamic>).single as Map<String, dynamic>;
    expect(feature['id'], 'rider-1');
    expect(feature['geometry']['coordinates'], <double>[108.552, -6.732]);
    expect(feature['properties']['label'], contains('Stale'));
    expect(feature['properties']['label'], contains('posisi terakhir'));
    expect(feature['properties']['label'], contains('45 dtk'));
    expect(feature['properties']['label'], isNot(contains('Live')));
  });

  test('offline observations never acquire a Live map label', () {
    final String label = riderMapLabel(
      presentation(offline: true).markers.single,
      now,
    );
    expect(label, contains('Offline'));
    expect(label, contains('posisi terakhir'));
  });

  testWidgets('missing client map style keeps the operational list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveGroupMapView(
            presentation: presentation(),
            now: now,
            fallback: const Text('Rider One · Stale'),
          ),
        ),
      ),
    );
    expect(find.byType(MapLibreMap), findsNothing);
    expect(find.text('Rider One · Stale'), findsOneWidget);
    expect(find.textContaining('Peta belum dikonfigurasi'), findsOneWidget);
  });

  testWidgets('insecure styles are not passed to the native map', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapStyleScope(
          styleUrl: 'http://untrusted.invalid/style.json?apiKey=hidden',
          child: Scaffold(
            body: LiveGroupMapView(
              presentation: presentation(),
              now: now,
              fallback: const Text('Rider list'),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(MapLibreMap), findsNothing);
    expect(find.text('Rider list'), findsOneWidget);
    expect(find.textContaining('hidden'), findsNothing);
  });
}
