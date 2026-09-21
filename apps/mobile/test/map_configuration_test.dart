import 'package:commride_mobile/src/config/app_config.dart';
import 'package:commride_mobile/src/maps/map_style_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only HTTPS Geoapify client style configuration is accepted', () {
    const String valid =
        'https://maps.geoapify.com/v1/styles/osm-bright/style.json?apiKey=test';
    expect(AppConfig.validateMapStyleUrl(valid), valid);
    for (final String? invalid in <String?>[
      null,
      '',
      'file:///secret.json',
      'http://maps.geoapify.com/v1/styles/osm-bright/style.json?apiKey=test',
      'https://evil.invalid/style.json?apiKey=test',
      'https://maps.geoapify.com.evil.invalid/style.json?apiKey=test',
      'https://maps.geoapify.com/v1/styles/osm-bright/style.json',
      'https://user:password@maps.geoapify.com/v1/styles/osm-bright/style.json?apiKey=test',
      'https://maps.geoapify.com:444/v1/styles/osm-bright/style.json?apiKey=test',
    ]) {
      expect(AppConfig.validateMapStyleUrl(invalid), isNull);
    }
  });

  testWidgets('client map style scope survives a pushed route', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MapStyleScope(styleUrl: 'test-client-style', child: child!),
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => Scaffold(
                  body: Text(MapStyleScope.of(context) ?? 'missing'),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('test-client-style'), findsOneWidget);
  });
}
