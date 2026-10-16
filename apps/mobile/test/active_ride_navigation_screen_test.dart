import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:commride_mobile/src/widgets/sos_hold_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/active_ride_fakes.dart';

class _RecordingRealtimeClient extends AuditRealtimeClient {
  final List<LiveQuickActionKind> sent = <LiveQuickActionKind>[];

  @override
  Future<void> sendQuickAction(
    LiveQuickActionKind kind, {
    String? reason,
  }) async {
    sent.add(kind);
  }
}

class _RecordingHarness extends Harness {
  _RecordingHarness()
    : super(RideRole.member, realtime: _RecordingRealtimeClient());

  List<LiveQuickActionKind> get sent =>
      (realtime as _RecordingRealtimeClient).sent;
}

void _useRedmi8(WidgetTester tester) {
  // Redmi 8: 720x1520 px at 2.0 dpr with status and navigation bars.
  tester.view.physicalSize = const Size(720, 1520);
  tester.view.devicePixelRatio = 2.0;
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 96);
  tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 96);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _startRiding(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(
    MaterialApp(theme: CommRideTheme.light(), home: h.screen()),
  );
  await _settle(tester);
  await tester.tap(find.text('Mulai navigasi & tracking'));
  await _settle(tester);
  h.groupSnapshot();
  h.gps(routePoints.first);
  await _settle(tester);
}

Future<void> _tearDown(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  h.session.dispose();
  h.group.dispose();
}

void main() {
  testWidgets('riding screen fits a Redmi 8 with every action on screen', (
    WidgetTester tester,
  ) async {
    _useRedmi8(tester);
    final Harness h = Harness(RideRole.member);
    await _startRiding(tester, h);

    expect(tester.takeException(), isNull);
    expect(find.text('Belok kanan ke Jalan Siliwangi'), findsWidgets);
    for (final String label in <String>['Berhenti', 'Tertinggal', 'Bantuan']) {
      final Rect rect = tester.getRect(find.text(label));
      expect(rect.bottom, lessThanOrEqualTo(760 - 48));
    }
    expect(find.byType(SosHoldButton), findsOneWidget);
    expect(find.textContaining('tidak menghubungi ambulans'), findsNothing);

    await _tearDown(tester, h);
  });

  testWidgets('a status is sent with one tap', (WidgetTester tester) async {
    _useRedmi8(tester);
    final _RecordingHarness h = _RecordingHarness();
    await _startRiding(tester, h);

    await tester.tap(find.text('Tertinggal'));
    await _settle(tester);

    expect(h.sent, <LiveQuickActionKind>[LiveQuickActionKind.leftBehind]);
    expect(find.text('Saya Tertinggal terkirim ke rombongan.'), findsOneWidget);

    await _tearDown(tester, h);
  });

  testWidgets('another Rider status appears on the riding screen', (
    WidgetTester tester,
  ) async {
    _useRedmi8(tester);
    final Harness h = Harness(RideRole.sweeper);
    await _startRiding(tester, h);

    h.realtime.controller.add(
      ActiveRideQuickActionRaised(
        action: LiveQuickAction(
          eventId: 'event-1',
          riderId: 'rider-4',
          displayName: 'Eko',
          role: RideRole.member,
          kind: LiveQuickActionKind.leftBehind,
          reason: null,
          raisedAt: DateTime.now(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.textContaining('Eko: Saya Tertinggal'), findsOneWidget);

    await _tearDown(tester, h);
  });
}
