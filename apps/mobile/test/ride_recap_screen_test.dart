import 'package:commride_mobile/src/api/ride_recap_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_recap.dart';
import 'package:commride_mobile/src/screens/ride/ride_recap_screen.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRideRecapApi implements RideRecapApi {
  FakeRideRecapApi(this.recap);

  final RideRecap recap;

  @override
  Future<RideRecap> fetchRecap(String rideId) async => recap;
}

RideRecap buildRecap({required bool withSamples}) {
  return RideRecap(
    rideId: 'ride-1',
    title: 'Sunday Ride',
    actualStartAt: DateTime.utc(2026, 9, 18, 9),
    endedAt: DateTime.utc(2026, 9, 18, 12),
    durationSeconds: 10800,
    participants: const <RideRecapParticipant>[
      RideRecapParticipant(
        riderId: 'rider-1',
        displayName: 'Rider One',
        role: RideRole.leader,
        membershipStatus: RideMembershipStatus.active,
      ),
    ],
    plannedRoute: const RideRecapPlannedRoute(
      routePlanId: 'plan-1',
      revision: 2,
      originLabel: 'Cirebon',
      destinationLabel: 'Kuningan',
      distanceMeters: 42000,
      durationSeconds: 3600,
      stopCount: 2,
    ),
    journey: RideRecapJourney(
      sampleCount: withSamples ? 60 : 0,
      trackedRiderCount: withSamples ? 8 : 0,
      firstObservedAt: withSamples ? DateTime.utc(2026, 9, 18, 9, 1) : null,
      lastObservedAt: withSamples ? DateTime.utc(2026, 9, 18, 11, 59) : null,
      leaderTrackedDistanceMeters: withSamples ? 39750 : null,
    ),
    checkpoints: <RideRecapCheckpoint>[
      RideRecapCheckpoint(
        checkpointId: 'stop-1',
        label: 'Regroup 1',
        checkpointType: 'regroup',
        checkInCount: 8,
        participantCount: 10,
        releasedAt: DateTime.utc(2026, 9, 18, 10, 30),
      ),
    ],
    incidents: <RideRecapIncident>[
      RideRecapIncident(
        sosId: 'sos-1',
        riderId: 'rider-2',
        riderDisplayName: 'Rider Two',
        state: 'resolved',
        reason: 'Ban bocor',
        raisedAt: DateTime.utc(2026, 9, 18, 10, 45),
        closedAt: DateTime.utc(2026, 9, 18, 10, 52),
      ),
    ],
    generatedAt: DateTime.utc(2026, 9, 18, 12, 0, 1),
  );
}

Widget app(RideRecap recap) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: RideRecapScreen(
      rideId: 'ride-1',
      rideRecapApi: FakeRideRecapApi(recap),
    ),
  );
}

void main() {
  testWidgets('Recap distinguishes planned route from missing actual samples', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(buildRecap(withSamples: false)));
    await tester.pumpAndSettle();

    expect(find.text('Ride Recap'), findsOneWidget);
    expect(find.text('Sunday Ride'), findsOneWidget);
    expect(find.text('Rencana'), findsOneWidget);
    expect(find.textContaining('42.0 km'), findsOneWidget);
    expect(find.textContaining('tidak ada sampel lokasi'), findsOneWidget);
    expect(find.textContaining('8/10 Rider check-in'), findsOneWidget);
    expect(find.text('Rider Two'), findsOneWidget);
    expect(find.textContaining('Ban bocor'), findsOneWidget);
  });

  testWidgets('Recap labels sampled journey as incomplete operational data', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(buildRecap(withSamples: true)));
    await tester.pumpAndSettle();

    expect(find.text('Perjalanan tersampel'), findsOneWidget);
    expect(find.textContaining('60 sampel'), findsOneWidget);
    expect(find.textContaining('Jejak Leader: 39.8 km'), findsOneWidget);
    expect(
      find.textContaining(
        'dapat lebih pendek dari jarak perjalanan sebenarnya',
      ),
      findsOneWidget,
    );
  });
}
