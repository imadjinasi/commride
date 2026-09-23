import 'package:commride_mobile/src/api/notification_api.dart';
import 'package:commride_mobile/src/models/rider_notification.dart';
import 'package:commride_mobile/src/screens/notifications/notification_center_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNotificationApi implements NotificationApi {
  final List<RiderNotification> items = <RiderNotification>[
    RiderNotification(
      id: 'account-1',
      scope: RiderNotificationScope.account,
      clubId: 'club-1',
      rideId: null,
      kind: 'club_invite',
      title: 'Undangan Club',
      body: 'Anda diundang ke Club.',
      data: const <String, String>{'type': 'club.invite'},
      createdAt: DateTime.parse('2026-09-23T10:00:00Z'),
      readAt: null,
    ),
    RiderNotification(
      id: 'club-1',
      scope: RiderNotificationScope.club,
      clubId: 'club-1',
      rideId: 'ride-1',
      kind: 'briefing_published',
      title: 'Briefing diperbarui',
      body: 'Briefing terbaru siap dibaca.',
      data: const <String, String>{'type': 'ride.briefing_published'},
      createdAt: DateTime.parse('2026-09-23T11:00:00Z'),
      readAt: null,
    ),
  ];

  @override
  Future<List<RiderNotification>> listNotifications({
    RiderNotificationScope? scope,
    String? clubId,
    int limit = 50,
  }) async {
    return items
        .where(
          (RiderNotification item) =>
              (scope == null || item.scope == scope) &&
              (clubId == null || item.clubId == clubId),
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> markRead(String notificationId) async {
    final int index = items.indexWhere(
      (RiderNotification item) => item.id == notificationId,
    );
    if (index < 0) {
      return;
    }
    final RiderNotification item = items[index];
    items[index] = RiderNotification(
      id: item.id,
      scope: item.scope,
      clubId: item.clubId,
      rideId: item.rideId,
      kind: item.kind,
      title: item.title,
      body: item.body,
      data: item.data,
      createdAt: item.createdAt,
      readAt: DateTime.parse('2026-09-23T12:00:00Z'),
    );
  }
}

void main() {
  testWidgets('notification center separates Account and Club scopes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCenterScreen(
          notificationApi: FakeNotificationApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Akun'), findsOneWidget);
    expect(find.text('Club'), findsOneWidget);
    expect(find.text('Undangan Club'), findsOneWidget);
    expect(find.text('Briefing diperbarui'), findsNothing);

    await tester.tap(find.text('Club'));
    await tester.pumpAndSettle();

    expect(find.text('Briefing diperbarui'), findsOneWidget);
    expect(find.text('Undangan Club'), findsNothing);
  });

  testWidgets('opening an unread notification marks it read', (
    WidgetTester tester,
  ) async {
    final FakeNotificationApi api = FakeNotificationApi();
    await tester.pumpWidget(
      MaterialApp(home: NotificationCenterScreen(notificationApi: api)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undangan Club'));
    await tester.pumpAndSettle();

    expect(api.items.first.isUnread, isFalse);
  });
}
