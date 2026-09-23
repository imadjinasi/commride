import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/screens/ride/ride_quick_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quick action sheet sends a one-tap status', (
    WidgetTester tester,
  ) async {
    LiveQuickActionKind? sentKind;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showRideQuickActionsSheet(
                  context,
                  onSend: (
                    LiveQuickActionKind kind, {
                    String? reason,
                  }) async {
                    sentKind = kind;
                  },
                ),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saya Berhenti'));
    await tester.pumpAndSettle();

    expect(sentKind, LiveQuickActionKind.stopping);
    expect(find.text('Saya Berhenti terkirim.'), findsOneWidget);
  });

  testWidgets('quick action sheet can send an optional reason', (
    WidgetTester tester,
  ) async {
    LiveQuickActionKind? sentKind;
    String? sentReason;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => showRideQuickActionsSheet(
                  context,
                  onSend: (
                    LiveQuickActionKind kind, {
                    String? reason,
                  }) async {
                    sentKind = kind;
                    sentReason = reason;
                  },
                ),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byTooltip('Kirim Butuh Bantuan dengan alasan'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ban bocor');
    await tester.tap(find.text('Kirim'));
    await tester.pumpAndSettle();

    expect(sentKind, LiveQuickActionKind.needHelp);
    expect(sentReason, 'ban bocor');
  });
}
