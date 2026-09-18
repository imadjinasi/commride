import 'package:commride_mobile/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the documented primary navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CommRideApp());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('can switch to Ride without requesting permissions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CommRideApp());

    await tester.tap(find.byIcon(Icons.route_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Plan, join, and review Rides here. Route planning, Add Stop, Search Along Route, and the Active Ride command center come next.'), findsOneWidget);
  });
}
