import 'package:commride_mobile/src/config/app_config.dart';
import 'package:commride_mobile/src/navigation/app_shell.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const AppConfig testConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: null,
);

Widget buildShell() {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: const AppShell(config: testConfig),
  );
}

void main() {
  testWidgets('renders the documented primary navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildShell());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('can switch to Ride without requesting permissions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildShell());

    await tester.tap(find.byIcon(Icons.route_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Plan, join, and review Rides here. Route planning, Add Stop, '
        'Search Along Route, and the Active Ride command center come next.',
      ),
      findsOneWidget,
    );
  });
}
