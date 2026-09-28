import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:commride_mobile/src/widgets/active_ride_quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('quick action sends in at most two interactions from navigation', (
    WidgetTester tester,
  ) async {
    LiveQuickActionKind? sent;

    await tester.pumpWidget(
      MaterialApp(
        theme: CommRideTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => FilledButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (BuildContext context) =>
                      ActiveRideQuickActionsSheet(
                    onSend: (LiveQuickActionKind kind, {String? reason}) async {
                      sent = kind;
                    },
                  ),
                );
              },
              child: const Text('Status'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saya Berhenti'));
    await tester.pump();

    expect(sent, LiveQuickActionKind.stopping);
  });

  testWidgets('quick action reason is optional and secondary', (
    WidgetTester tester,
  ) async {
    String? sentReason;

    await tester.pumpWidget(
      MaterialApp(
        theme: CommRideTheme.light(),
        home: Scaffold(
          body: ActiveRideQuickActionsSheet(
            onSend: (LiveQuickActionKind kind, {String? reason}) async {
              sentReason = reason;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Tambahkan keterangan').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'isi BBM');
    await tester.tap(find.text('Kirim'));
    await tester.pump();

    expect(sentReason, 'isi BBM');
  });
}
