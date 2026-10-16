import 'package:commride_mobile/src/api/route_planner_api.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:commride_mobile/src/screens/ride/location_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SearchApi implements RoutePlannerApi {
  GeoPoint? lastNear;
  List<PlaceSuggestion> results = const <PlaceSuggestion>[
    PlaceSuggestion(reference: 'p-1', text: 'Pesantren Fixture, Cirebon'),
  ];

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
    GeoPoint? near,
    PlaceSearchArea? area,
  }) async {
    lastNear = near;
    return results;
  }

  @override
  Future<ResolvedPlace> resolvePlace({
    required String reference,
    required String sessionToken,
  }) async {
    return const ResolvedPlace(
      reference: 'p-1',
      formattedAddress: 'Pesantren Fixture, Cirebon',
      location: GeoPoint(latitude: -6.71, longitude: 108.56),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _picker(_SearchApi api, {GeoPoint? center}) {
  return MaterialApp(
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              final ResolvedPlace? place = await Navigator.of(context)
                  .push<ResolvedPlace>(
                    MaterialPageRoute<ResolvedPlace>(
                      builder: (_) => LocationPickerScreen(
                        routePlannerApi: api,
                        title: 'Titik awal',
                        initialCenter: center,
                        currentLocation: ({required bool ask}) async => null,
                      ),
                    ),
                  );
              if (context.mounted && place != null) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(place.reference)));
              }
            },
            child: const Text('Buka'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('search favours the area being looked at', (
    WidgetTester tester,
  ) async {
    final _SearchApi api = _SearchApi();
    await tester.pumpWidget(
      _picker(api, center: const GeoPoint(latitude: -6.73, longitude: 108.55)),
    );
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pesantren');
    await tester.tap(find.text('Cari'));
    await tester.pumpAndSettle();

    expect(api.lastNear?.latitude, -6.73);
    expect(api.lastNear?.longitude, 108.55);

    await tester.tap(find.text('Pesantren Fixture, Cirebon'));
    await tester.pumpAndSettle();

    // Without a configured map the chosen result is returned directly.
    expect(find.text('p-1'), findsOneWidget);
  });

  testWidgets('no results says so instead of staying silent', (
    WidgetTester tester,
  ) async {
    final _SearchApi api = _SearchApi()..results = const <PlaceSuggestion>[];
    await tester.pumpWidget(_picker(api));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tidak ada');
    await tester.tap(find.text('Cari'));
    await tester.pumpAndSettle();

    expect(find.text('Tidak ditemukan.'), findsOneWidget);
  });
}
