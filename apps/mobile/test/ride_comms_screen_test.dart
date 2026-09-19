import 'package:commride_mobile/src/active_ride/ride_comms_controller.dart';
import 'package:commride_mobile/src/api/ride_comms_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_message.dart';
import 'package:commride_mobile/src/screens/ride/ride_comms_screen.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Ride ride(RideStatus status) {
  return Ride(
    id: 'ride-1',
    clubId: 'club-1',
    title: 'Sunday Ride',
    status: status,
    scheduledStartAt: null,
    actualStartAt: DateTime.utc(2026, 9, 18, 9),
    endedAt: status == RideStatus.completed
        ? DateTime.utc(2026, 9, 18, 12)
        : null,
    notes: null,
  );
}

RideMembership membership(RideRole role) {
  return RideMembership(
    rideId: 'ride-1',
    riderId: 'rider-current',
    role: role,
    status: RideMembershipStatus.active,
  );
}

RideMessage message({
  String id = 'message-1',
  String senderRiderId = 'rider-other',
  String senderDisplayName = 'Rider Other',
  RideRole role = RideRole.member,
  RideMessageKind kind = RideMessageKind.chat,
  String body = 'Halo',
  String clientMessageId = 'client-existing',
  DateTime? createdAt,
}) {
  return RideMessage(
    id: id,
    rideId: 'ride-1',
    senderRiderId: senderRiderId,
    senderDisplayName: senderDisplayName,
    senderRideRole: role,
    kind: kind,
    body: body,
    clientMessageId: clientMessageId,
    createdAt: createdAt ?? DateTime.utc(2026, 9, 18, 10),
  );
}

class FakeRideCommsApi implements RideCommsApi {
  RideMessagePage page = const RideMessagePage(
    messages: <RideMessage>[],
    nextCursor: null,
  );
  int failSends = 0;
  int sendCount = 0;
  final List<String> clientIds = <String>[];
  final List<RideMessageKind> kinds = <RideMessageKind>[];
  final List<String> bodies = <String>[];

  @override
  Future<RideMessagePage> fetchMessages(
    String rideId, {
    String? cursor,
    int limit = 50,
  }) async {
    return page;
  }

  @override
  Future<RideMessage> sendChat({
    required String rideId,
    required String clientMessageId,
    required String body,
  }) {
    return _send(
      kind: RideMessageKind.chat,
      clientMessageId: clientMessageId,
      body: body,
    );
  }

  @override
  Future<RideMessage> sendAnnouncement({
    required String rideId,
    required String clientMessageId,
    required String body,
  }) {
    return _send(
      kind: RideMessageKind.announcement,
      clientMessageId: clientMessageId,
      body: body,
    );
  }

  Future<RideMessage> _send({
    required RideMessageKind kind,
    required String clientMessageId,
    required String body,
  }) async {
    sendCount += 1;
    clientIds.add(clientMessageId);
    kinds.add(kind);
    bodies.add(body);

    if (failSends > 0) {
      failSends -= 1;
      throw const RideCommsApiException(
        statusCode: 503,
        code: 'request_failed',
        message: 'Offline',
      );
    }

    return message(
      id: 'sent-$sendCount',
      senderRiderId: 'rider-current',
      senderDisplayName: 'Current Rider',
      role: kind == RideMessageKind.announcement
          ? RideRole.leader
          : RideRole.member,
      kind: kind,
      body: body,
      clientMessageId: clientMessageId,
      createdAt: DateTime.utc(2026, 9, 18, 10, sendCount),
    );
  }
}

Widget buildScreen({
  required RideStatus status,
  required RideRole role,
  required FakeRideCommsApi api,
  String Function()? clientMessageIdFactory,
}) {
  final RideCommsController controller = RideCommsController(
    rideId: 'ride-1',
    api: api,
    clientMessageIdFactory: clientMessageIdFactory,
  );

  return MaterialApp(
    theme: CommRideTheme.light(),
    home: RideCommsScreen(
      ride: ride(status),
      membership: membership(role),
      controller: controller,
    ),
  );
}

void main() {
  testWidgets('Active Rider can send chat and sees plain text literally', (
    WidgetTester tester,
  ) async {
    final FakeRideCommsApi api = FakeRideCommsApi()
      ..page = RideMessagePage(
        messages: <RideMessage>[
          message(body: '<b>Bukan HTML</b>'),
        ],
        nextCursor: null,
      );

    await tester.pumpWidget(
      buildScreen(
        status: RideStatus.active,
        role: RideRole.member,
        api: api,
        clientMessageIdFactory: () => 'client-chat',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('<b>Bukan HTML</b>'), findsOneWidget);
    expect(find.byTooltip('Pengumuman Leader'), findsNothing);
    expect(find.text('Pesan ke Rider...'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Tunggu di SPBU');
    await tester.tap(find.byTooltip('Kirim pesan'));
    await tester.pumpAndSettle();

    expect(api.kinds, <RideMessageKind>[RideMessageKind.chat]);
    expect(api.clientIds, <String>['client-chat']);
    expect(find.text('Tunggu di SPBU'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Leader can publish a distinct announcement', (
    WidgetTester tester,
  ) async {
    final FakeRideCommsApi api = FakeRideCommsApi();

    await tester.pumpWidget(
      buildScreen(
        status: RideStatus.active,
        role: RideRole.leader,
        api: api,
        clientMessageIdFactory: () => 'client-announcement',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Pengumuman Leader'));
    await tester.pumpAndSettle();

    final Finder dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, 'Regroup di checkpoint berikutnya');
    await tester.tap(find.text('Publikasikan'));
    await tester.pumpAndSettle();

    expect(api.kinds, <RideMessageKind>[RideMessageKind.announcement]);
    expect(
      find.text('Regroup di checkpoint berikutnya'),
      findsWidgets,
    );
    expect(find.text('Pengumuman Leader'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed send is visible and retry keeps clientMessageId', (
    WidgetTester tester,
  ) async {
    final FakeRideCommsApi api = FakeRideCommsApi()..failSends = 1;

    await tester.pumpWidget(
      buildScreen(
        status: RideStatus.active,
        role: RideRole.member,
        api: api,
        clientMessageIdFactory: () => 'retry-stable-id',
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Pesan retry');
    await tester.tap(find.byTooltip('Kirim pesan'));
    await tester.pumpAndSettle();

    expect(find.text('Pesan belum terkirim.'), findsOneWidget);
    expect(find.text('Kirim ulang'), findsOneWidget);

    await tester.tap(find.text('Kirim ulang'));
    await tester.pumpAndSettle();

    expect(api.clientIds, <String>['retry-stable-id', 'retry-stable-id']);
    expect(find.text('Pesan retry'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Completed Ride keeps history but removes all send controls', (
    WidgetTester tester,
  ) async {
    final FakeRideCommsApi api = FakeRideCommsApi()
      ..page = RideMessagePage(
        messages: <RideMessage>[
          message(
            id: 'announcement',
            kind: RideMessageKind.announcement,
            role: RideRole.leader,
            body: 'Ride selesai dengan aman.',
          ),
        ],
        nextCursor: null,
      );

    await tester.pumpWidget(
      buildScreen(
        status: RideStatus.completed,
        role: RideRole.leader,
        api: api,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ride selesai dengan aman.'), findsWidgets);
    expect(
      find.textContaining('Riwayat Comms tetap dapat dibaca'),
      findsOneWidget,
    );
    expect(find.byTooltip('Kirim pesan'), findsNothing);
    expect(find.byTooltip('Pengumuman Leader'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
