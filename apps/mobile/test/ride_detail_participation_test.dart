import 'package:commride_mobile/src/active_ride/active_ride_runtime.dart';
import 'package:commride_mobile/src/api/checkpoint_api.dart';
import 'package:commride_mobile/src/api/club_ride_api.dart';
import 'package:commride_mobile/src/api/ride_briefing_api.dart';
import 'package:commride_mobile/src/api/ride_comms_api.dart';
import 'package:commride_mobile/src/api/ride_sos_api.dart';
import 'package:commride_mobile/src/api/route_planner_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/screens/ride/ride_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Only the parts of these APIs a test touches are implemented.
class _Unused
    implements
        ClubRideApi,
        CheckpointApi,
        RoutePlannerApi,
        RideBriefingApi,
        RideCommsApi,
        RideSosApi,
        AuthGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Ride _activeRide() => Ride(
  id: 'ride-1',
  clubId: 'club-1',
  title: 'Pangandaran l',
  status: RideStatus.active,
  scheduledStartAt: null,
  actualStartAt: DateTime.utc(2026, 9, 24),
  endedAt: null,
  notes: null,
);

Widget _detail(RideMembership? membership) {
  final _Unused unused = _Unused();
  return MaterialApp(
    home: RideDetailScreen(
      item: RideListItem(ride: _activeRide(), membership: membership),
      clubRideApi: unused,
      checkpointApi: unused,
      routePlannerApi: unused,
      rideBriefingApi: unused,
      rideCommsApi: unused,
      rideSosApi: unused,
      activeRideRuntimeManager: ActiveRideRuntimeManager(
        apiBaseUrl: Uri.parse('https://api.example.test'),
        authGateway: unused,
      ),
      onChanged: () {},
    ),
  );
}

void main() {
  testWidgets('Club member who is not in the Ride gets an explanation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_detail(null));

    expect(find.text('Anda belum terdaftar di Ride ini'), findsOneWidget);
    expect(find.text('Buka Active Ride'), findsNothing);
  });

  testWidgets('participant of an Active Ride can open it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _detail(
        const RideMembership(
          rideId: 'ride-1',
          riderId: 'rider-1',
          role: RideRole.member,
          status: RideMembershipStatus.active,
        ),
      ),
    );

    expect(find.text('Buka Active Ride'), findsOneWidget);
    expect(find.text('Anda belum terdaftar di Ride ini'), findsNothing);
  });
}
