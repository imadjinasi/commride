import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:commride_mobile/src/widgets/sos_hold_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _build({
  required Future<void> Function() onCompleted,
  bool active = false,
  bool working = false,
}) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 160,
          child: SosHoldButton(
            active: active,
            working: working,
            onCompleted: onCompleted,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('SOS sends only after three-second hold', (
    WidgetTester tester,
  ) async {
    int sends = 0;
    await tester.pumpWidget(_build(onCompleted: () async => sends += 1));

    final Finder button = find.byType(SosHoldButton);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(button),
    );
    await tester.pump(const Duration(seconds: 2, milliseconds: 900));
    expect(sends, 0);

    await tester.pump(const Duration(milliseconds: 150));
    expect(sends, 1);

    await gesture.up();
    await tester.pump();
    expect(sends, 1);
  });

  testWidgets('releasing SOS before three seconds cancels send', (
    WidgetTester tester,
  ) async {
    int sends = 0;
    await tester.pumpWidget(_build(onCompleted: () async => sends += 1));

    final Finder button = find.byType(SosHoldButton);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(button),
    );
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump(const Duration(seconds: 3));

    expect(sends, 0);
    expect(find.text('SOS · tahan 3 dtk'), findsOneWidget);
  });

  testWidgets('SOS uses critical red treatment', (WidgetTester tester) async {
    await tester.pumpWidget(_build(onCompleted: () async {}));

    final Iterable<Material> materials = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(SosHoldButton),
        matching: find.byType(Material),
      ),
    );

    expect(
      materials.any((Material material) =>
          material.color == CommRideColors.criticalRed),
      isTrue,
    );
  });
}
