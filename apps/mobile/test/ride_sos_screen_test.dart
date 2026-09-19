import 'package:commride_mobile/src/active_ride/ride_sos_controller.dart';
import 'package:commride_mobile/src/api/ride_sos_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_sos.dart';
import 'package:commride_mobile/src/screens/ride/ride_sos_screen.dart';
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

RideSos incident({
  String riderId = 'rider-current',
  RideSosStatus status = RideSosStatus.active,
  RideSosPresence? presence,
}) {
  return RideSos(
    id: 'sos-1',
    rideId: 'ride-1',
    riderId: riderId,
    riderDisplayName: riderId == 'rider-current'
        ? 'Rider Current'
        : 'Rider Other',
    riderRideRole: RideRole.member,
    status: status,
    clientCommandId: 'client-1',
    reason: 'Butuh bantuan',
    raisedAt: DateTime.utc(2026, 9, 18, 10),
    cancelledAt: null,
    resolvedAt: null,
    resolvedByRiderId: null,
    presence: presence,
  );
}

class FakeRideSosApi implements RideSosApi {
  List<RideSos> items = <RideSos>[];
  int raises = 0;
  int cancels = 0;
  int resolves = 0;

  @override
  Future<List<RideSos>> fetchSos(String rideId) async => items;

  @override
  Future<RideSos> raiseSos({
    required String rideId,
    required String clientCommandId,
    required String? reason,
  }) async {
    raises += 1;
    final RideSos created = RideSos(
      id: 'sos-created',
      rideId: rideId,
      riderId: 'rider-current',
      riderDisplayName: 'Rider Current',
      riderRideRole: RideRole.member,
      status: RideSosStatus.active,
      clientCommandId: clientCommandId,
      reason: reason,
      raisedAt: DateTime.utc(2026, 9, 18, 10),
      cancelledAt: null,
      resolvedAt: null,
      resolvedByRiderId: null,
      presence: null,
    );
    items = <RideSos>[created];
    return created;
  }

  @override
  Future<RideSos> cancelSos({
    required String rideId,
    required String sosId,
  }) async {
    cancels += 1;
    return RideSos(
      id: sosId,
      rideId: rideId,
      riderId: 'rider-current',
      riderDisplayName: 'Rider Current',
      riderRideRole: RideRole.member,
      status: RideSosStatus.cancelled,
      clientCommandId: 'client-1',
      reason: null,
      raisedAt: DateTime.utc(2026, 9, 18, 10),
      cancelledAt: DateTime.utc(2026, 9, 18, 10, 5),
      resolvedAt: null,
      resolvedByRiderId: null,
      presence: null,
    );
  }

  @override
  Future<RideSos> resolveSos({
    required String rideId,
    required String sosId,
  }) async {
    resolves += 1;
    return RideSos(
      id: sosId,
      rideId: rideId,
      riderId: 'rider-other',
      riderDisplayName: 'Rider Other',
      riderRideRole: RideRole.member,
      status: RideSosStatus.resolved,
      clientCommandId: 'client-1',
      reason: null,
      raisedAt: DateTime.utc(2026, 9, 18, 10),
      cancelledAt: null,
      resolvedAt: DateTime.utc(2026, 9, 18, 10, 5),
      resolvedByRiderId: 'rider-current',
      presence: null,
    );
  }
}

Widget buildScreen({
  required RideStatus status,
  required RideRole role,
  required FakeRideSosApi api,
}) {
  final RideSosController controller = RideSosController(
    rideId: 'ride-1',
    api: api,
    clientCommandIdFactory: () => 'client-stable',
    readOnly: status == RideStatus.completed,
  );

  return MaterialApp(
    theme: CommRideTheme.light(),
    home: RideSosScreen(
      ride: ride(status),
      membership: membership(role),
      controller: controller,
    ),
  );
}

void main() {
  testWidgets('Rider confirms SOS and no GPS does not block activation', (
    WidgetTester tester,
  ) async {
    final FakeRideSosApi api = FakeRideSosApi();

    await tester.pumpWidget(
      buildScreen(
        status: RideStatus.active,
        role: RideRole.member,
        api: api,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aktifkan SOS'));
    await tester.pumpAndSettle();

    expect(find.text('Aktifkan SOS?'), findsOneWidget);
    expect(
      find.textContaining('tidak otomatis menghubungi ambulans'),
      findsOneWidget,
    );

    await tester.tap(find.text('Kirim SOS'));
    await tester.pumpAndSettle();

    expect(api.raises, 1);
    expect(find.textContaining('SOS tetap aktif tanpa GPS'), findsOneWidget);
    expect(find.text('Batalkan SOS'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Leader can resolve another Rider active SOS', (
    WidgetTester tester,
  ) async {
    final FakeRideSosApi api = FakeRideSosApi()
      ..items = <RideSos>[incident(riderId: 'rider-other')];

    await tester.pumpWidget(
      buildScreen(
        status: RideStatus.active,
        role: RideRole.leader,
        api: api,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tandai selesai'), findsOneWidget);
    await tester.tap(find.text('Tandai selesai'));
    await tester.pumpAndSettle();
    expect(find.text('Tandai SOS selesai?'), findsOneWidget);

    final Finder resolveConfirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Tandai selesai'),
    );
    await tester.tap(resolveConfirm);
    await tester.pumpAndSettle();

    expect(api.resolves, 1);
    expect(find.text('Selesai'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Completed Ride is history-only', (WidgetTester tester) async {
    final FakeRideSosApi api = FakeRideSosApi()
      ..items = <RideSos>[
        incident(status: RideSosStatus.cancelled),
      ];

    await tester.pumpWidget(
      buildScreen(
        status: RideStatus.completed,
        role: RideRole.member,
        api: api,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aktifkan SOS'), findsNothing);
    expect(
      find.text('Ride sudah selesai. Riwayat SOS tetap dapat dibaca.'),
      findsOneWidget,
    );
    expect(find.text('Dibatalkan'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
