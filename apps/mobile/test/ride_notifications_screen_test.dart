import 'dart:async';

import 'package:commride_mobile/src/api/push_token_api.dart';
import 'package:commride_mobile/src/push/ride_push_controller.dart';
import 'package:commride_mobile/src/push/ride_push_messaging.dart';
import 'package:commride_mobile/src/screens/notifications/ride_notifications_screen.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TokenApi implements PushTokenApi {
  @override
  Future<void> registerToken({
    required String token,
    required RidePushPlatform platform,
  }) async {}

  @override
  Future<void> unregisterToken({
    required String token,
    required RidePushPlatform platform,
  }) async {}
}

class _Messaging implements RidePushMessaging {
  final StreamController<RideForegroundPush> foreground =
      StreamController<RideForegroundPush>.broadcast();

  @override
  Future<RidePushPermission> checkPermission() async =>
      RidePushPermission.authorized;

  @override
  Future<String?> currentToken() async => 'token';

  @override
  Stream<RideForegroundPush> get foregroundMessages => foreground.stream;

  @override
  Future<RidePushPermission> requestPermission() async =>
      RidePushPermission.authorized;

  @override
  Stream<String> get tokenRefreshes => const Stream<String>.empty();

  Future<void> close() => foreground.close();
}

void main() {
  testWidgets('read notification remains actionable', (
    WidgetTester tester,
  ) async {
    final _Messaging messaging = _Messaging();
    final RidePushController controller = RidePushController(
      tokenApi: _TokenApi(),
      messaging: messaging,
      platform: RidePushPlatform.android,
    );
    await controller.start();
    messaging.foreground.add(
      const RideForegroundPush(
        title: 'Ride Briefing diperbarui',
        body: 'Briefing terbaru siap dibaca.',
        data: <String, String>{
          'type': 'ride.briefing_published',
          'rideId': 'ride-1',
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    RideNotificationEntry? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: CommRideTheme.light(),
        home: RideNotificationsScreen(
          controller: controller,
          onOpen: (RideNotificationEntry item) async {
            opened = item;
          },
        ),
      ),
    );

    expect(find.text('Belum dibaca'), findsOneWidget);
    await tester.tap(find.text('Tandai dibaca'));
    await tester.pump();

    expect(find.text('Sudah dibaca'), findsOneWidget);
    expect(find.text('Ride Briefing diperbarui'), findsOneWidget);

    await tester.tap(find.text('Ride Briefing diperbarui'));
    await tester.pump();

    expect(opened?.rideId, 'ride-1');
    expect(controller.state.notifications.single.read, isTrue);

    controller.dispose();
    await messaging.close();
  });
}
