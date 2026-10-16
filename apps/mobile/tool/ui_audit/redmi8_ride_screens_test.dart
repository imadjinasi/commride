// Renders Active Ride screens at Redmi 8 size (720x1520 px, 2.0 dpr, status
// bar and 3-button navigation bar) with real Roboto and Material icons, for
// UI audits. Not part of CI:
//
//   flutter test tool/ui_audit/redmi8_ride_screens_test.dart
//
// PNGs are written to build/ui_audit/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/active_ride/voice_intercom.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/support/active_ride_fakes.dart';

const Size redmi8Physical = Size(720, 1520);
const double redmi8Dpr = 2.0;

Future<void> loadRealFonts() async {
  final String flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final String fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final FontLoader roboto = FontLoader('Roboto');
  for (final String file in <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    roboto.addFont(_fontBytes('$fonts/$file'));
  }
  await roboto.load();
  final FontLoader icons = FontLoader('MaterialIcons')
    ..addFont(_fontBytes('$fonts/materialicons-regular.otf'));
  await icons.load();
}

Future<ByteData> _fontBytes(String path) async {
  final List<int> bytes = await File(path).readAsBytes();
  return ByteData.view(Uint8List.fromList(bytes).buffer);
}

void useRedmi8(WidgetTester tester) {
  // Draw real elevation shadows instead of the test outlines.
  debugDisableShadows = false;
  tester.view.physicalSize = redmi8Physical;
  tester.view.devicePixelRatio = redmi8Dpr;
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 96);
  tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 96);
  addTearDown(tester.view.reset);
}

final GlobalKey _boundary = GlobalKey();

Widget frame(Widget child) {
  return RepaintBoundary(
    key: _boundary,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: CommRideTheme.light().copyWith(
        textTheme: CommRideTheme.light().textTheme.apply(fontFamily: 'Roboto'),
      ),
      home: child,
    ),
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  final RenderRepaintBoundary boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: redmi8Dpr);
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File file = File('build/ui_audit/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadRealFonts);

  final List<String> overflows = <String>[];
  setUp(() {
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final String text = details.exceptionAsString();
      if (text.contains('overflowed')) {
        overflows.add(text.split('\n').first);
        return;
      }
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  });
  tearDownAll(() {
    // ignore: avoid_print
    print('OVERFLOWS: ${overflows.isEmpty ? 'none' : overflows.join(' | ')}');
  });

  for (final RideRole role in <RideRole>[RideRole.member, RideRole.leader]) {
    testWidgets('riding screens · ${role.name}', (WidgetTester tester) async {
      useRedmi8(tester);
      final Harness h = Harness(role);
      await tester.pumpWidget(frame(h.screen()));
      await settle(tester);
      await capture(tester, '${role.name}_01_before_start');

      await tester.tap(find.text('Mulai navigasi & tracking'));
      await settle(tester);
      h.groupSnapshot();
      h.gps(routePoints.first);
      await settle(tester);
      await capture(tester, '${role.name}_02_on_route');

      h.groupSnapshot(stale: true);
      await settle(tester);
      await capture(tester, '${role.name}_03_rider_stale');

      h.realtime.controller.add(
        ActiveRideQuickActionRaised(
          action: LiveQuickAction(
            eventId: 'event-1',
            riderId: 'rider-4',
            displayName: 'Eko',
            role: RideRole.member,
            kind: LiveQuickActionKind.leftBehind,
            reason: null,
            raisedAt: DateTime.now().subtract(const Duration(minutes: 2)),
            presence: null,
          ),
        ),
      );
      await settle(tester);
      await capture(tester, '${role.name}_04_alert_from_rider');

      h.gps(const GeoPoint(latitude: -6.7300, longitude: 108.5600));
      await settle(tester);
      h.gps(const GeoPoint(latitude: -6.7298, longitude: 108.5602));
      await settle(tester);
      h.gps(const GeoPoint(latitude: -6.7296, longitude: 108.5604));
      await settle(tester);
      await capture(tester, '${role.name}_05_off_route');

      await tester.tap(find.text('Berhenti'));
      await settle(tester);
      await capture(tester, '${role.name}_06_status_sent');

      await tester.pumpWidget(const SizedBox.shrink());
      h.session.dispose();
      h.group.dispose();
      debugDisableShadows = true;
    });
  }

  for (final RideRole role in <RideRole>[RideRole.member, RideRole.leader]) {
    testWidgets('intercom · ${role.name}', (WidgetTester tester) async {
      useRedmi8(tester);
      final AuditVoiceTransport voice = AuditVoiceTransport();
      final Harness h = Harness(role, voice: voice);
      await tester.pumpWidget(frame(h.screen()));
      await settle(tester);

      await tester.tap(find.text('Mulai navigasi & tracking'));
      await settle(tester);
      h.groupSnapshot();
      h.gps(routePoints.first);
      voice.controller.add(
        const RideVoiceParticipantsChanged(<RideVoiceParticipant>[
          RideVoiceParticipant(
            riderId: 'rider-l',
            name: 'Andi',
            audioEnabled: true,
          ),
          RideVoiceParticipant(
            riderId: 'rider-s',
            name: 'Budi',
            audioEnabled: true,
          ),
          RideVoiceParticipant(
            riderId: 'rider-2',
            name: 'Citra',
            audioEnabled: false,
          ),
        ]),
      );
      await settle(tester);
      await capture(tester, 'intercom_${role.name}_01_listening');

      await tester.tap(find.byKey(const ValueKey<String>('intercom-mic')));
      await settle(tester);
      await capture(tester, 'intercom_${role.name}_02_mic_on');

      voice.controller.add(
        const RideVoiceActiveSpeakersChanged(<String>{'rider-s'}),
      );
      await settle(tester);
      await capture(tester, 'intercom_${role.name}_03_speaker');

      if (role == RideRole.member) {
        voice.controller.add(const RideVoiceModeratorMutedChanged(muted: true));
        await settle(tester);
        await capture(tester, 'intercom_${role.name}_04_muted_by_leader');
      }

      await tester.tap(find.byKey(const ValueKey<String>('intercom-settings')));
      await settle(tester);
      await capture(tester, 'intercom_${role.name}_05_sheet');

      await tester.tap(find.byKey(const ValueKey<String>('intercom-mode-ptt')));
      await settle(tester);
      await tester.tapAt(const Offset(180, 80));
      await settle(tester);
      await capture(tester, 'intercom_${role.name}_06_tap_to_talk');

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpWidget(const SizedBox.shrink());
      h.session.dispose();
      h.group.dispose();
      await voice.controller.close();
      debugDisableShadows = true;
    });
  }
}
