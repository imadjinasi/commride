import 'package:commride_mobile/src/api/checkpoint_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_checkpoint.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:commride_mobile/src/screens/ride/checkpoints_screen.dart';
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
    riderId: role == RideRole.leader ? 'rider-leader' : 'rider-member',
    role: role,
    status: RideMembershipStatus.joined,
  );
}

RideCheckpointView view({
  bool checkedIn = false,
  bool released = false,
  int missingCount = 2,
}) {
  final int checkedInCount = 2 - missingCount;
  return RideCheckpointView(
    rideId: 'ride-1',
    routePlanId: 'plan-2',
    routePlanRevision: 2,
    checkpoints: <RideCheckpointItem>[
      RideCheckpointItem(
        checkpointId: 'cp-fuel',
        sequence: 0,
        label: 'Fuel One',
        formattedAddress: 'SPBU One',
        latitude: -6.8,
        longitude: 108.0,
        checkpointType: CheckpointType.fuel,
        plannedDurationMinutes: 15,
        state: released
            ? RideCheckpointState.released
            : RideCheckpointState.current,
        expectedCount: 2,
        checkedInCount: checkedInCount,
        missingCount: missingCount,
        currentRiderCheckedIn: checkedIn,
        releasedAt: released ? DateTime.utc(2026, 9, 18, 10, 5) : null,
        participants: <CheckpointParticipant>[
          CheckpointParticipant(
            riderId: 'rider-leader',
            displayName: 'Leader One',
            role: RideRole.leader,
            membershipStatus: RideMembershipStatus.joined,
            checkedInAt: missingCount < 2
                ? DateTime.utc(2026, 9, 18, 10)
                : null,
          ),
          CheckpointParticipant(
            riderId: 'rider-member',
            displayName: 'Member One',
            role: RideRole.member,
            membershipStatus: RideMembershipStatus.joined,
            checkedInAt: checkedIn ? DateTime.utc(2026, 9, 18, 10, 1) : null,
          ),
        ],
      ),
    ],
  );
}

class FakeCheckpointApi implements CheckpointApi {
  FakeCheckpointApi(this.current);

  RideCheckpointView current;
  int fetchCalls = 0;
  int checkInCalls = 0;
  int releaseCalls = 0;

  @override
  Future<RideCheckpointView> fetchCheckpoints(String rideId) async {
    fetchCalls += 1;
    return current;
  }

  @override
  Future<RideCheckpointView> checkIn({
    required String rideId,
    required String checkpointId,
  }) async {
    checkInCalls += 1;
    current = view(checkedIn: true, missingCount: 1);
    return current;
  }

  @override
  Future<RideCheckpointView> release({
    required String rideId,
    required String checkpointId,
  }) async {
    releaseCalls += 1;
    current = view(
      released: true,
      missingCount: current.checkpoints.single.missingCount,
    );
    return current;
  }
}

Widget buildScreen({
  required Ride rideValue,
  required RideRole role,
  required FakeCheckpointApi api,
}) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: CheckpointsScreen(
      ride: rideValue,
      membership: membership(role),
      checkpointApi: api,
    ),
  );
}

void main() {
  testWidgets('Rider sees manual check-in truth and can check in self', (
    WidgetTester tester,
  ) async {
    final FakeCheckpointApi api = FakeCheckpointApi(view());

    await tester.pumpWidget(
      buildScreen(
        rideValue: ride(RideStatus.active),
        role: RideRole.member,
        api: api,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fuel One'), findsOneWidget);
    expect(find.textContaining('bukan verifikasi GPS'), findsOneWidget);
    expect(find.text('Saya sudah tiba'), findsOneWidget);
    expect(find.text('Lepas Checkpoint'), findsNothing);

    await tester.tap(find.text('Saya sudah tiba'));
    await tester.pumpAndSettle();

    expect(api.checkInCalls, 1);
    expect(find.text('Anda sudah check-in.'), findsOneWidget);
    expect(find.textContaining('1/2 Rider sudah tiba'), findsOneWidget);
  });

  testWidgets('Leader release warns when Riders are still missing', (
    WidgetTester tester,
  ) async {
    final FakeCheckpointApi api = FakeCheckpointApi(view());

    await tester.pumpWidget(
      buildScreen(
        rideValue: ride(RideStatus.active),
        role: RideRole.leader,
        api: api,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lepas Checkpoint'));
    await tester.pumpAndSettle();

    expect(find.text('Lepas Checkpoint?'), findsOneWidget);
    expect(find.textContaining('2 Rider belum check-in'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(api.releaseCalls, 0);

    await tester.tap(find.text('Lepas Checkpoint'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tetap lepas'));
    await tester.pumpAndSettle();

    expect(api.releaseCalls, 1);
    expect(find.text('Released'), findsOneWidget);
  });

  testWidgets('Leader release with no missing Riders needs no warning', (
    WidgetTester tester,
  ) async {
    final FakeCheckpointApi api = FakeCheckpointApi(
      view(checkedIn: true, missingCount: 0),
    );

    await tester.pumpWidget(
      buildScreen(
        rideValue: ride(RideStatus.active),
        role: RideRole.leader,
        api: api,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lepas Checkpoint'));
    await tester.pumpAndSettle();

    expect(api.releaseCalls, 1);
    expect(find.text('Lepas Checkpoint?'), findsNothing);
    expect(find.text('Released'), findsOneWidget);
  });

  testWidgets('Completed Ride is read-only', (WidgetTester tester) async {
    final FakeCheckpointApi api = FakeCheckpointApi(view(released: true));

    await tester.pumpWidget(
      buildScreen(
        rideValue: ride(RideStatus.completed),
        role: RideRole.leader,
        api: api,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fuel One'), findsOneWidget);
    expect(find.text('Saya sudah tiba'), findsNothing);
    expect(find.text('Lepas Checkpoint'), findsNothing);
  });
}
