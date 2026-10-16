// Fakes for rendering ActiveRideNavigationScreen without GPS, server or map
// plugins. Shared by widget tests and tool/ui_audit.

import 'dart:async';

import 'package:commride_mobile/src/active_ride/active_ride_runtime.dart';
import 'package:commride_mobile/src/active_ride/live_group_controller.dart';
import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/active_ride/location_session_controller.dart';
import 'package:commride_mobile/src/active_ride/realtime_client.dart';
import 'package:commride_mobile/src/active_ride/voice_intercom.dart';
import 'package:commride_mobile/src/api/ride_sos_api.dart';
import 'package:commride_mobile/src/api/route_planner_api.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/ride_sos.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:commride_mobile/src/screens/ride/active_ride_navigation_screen.dart';
import 'package:flutter/widgets.dart';

class AuditRealtimeClient implements ActiveRideRealtimeClient {
  final StreamController<ActiveRideRealtimeEvent> controller =
      StreamController<ActiveRideRealtimeEvent>.broadcast();

  @override
  Stream<ActiveRideRealtimeEvent> get events => controller.stream;

  @override
  Future<void> connect(String rideId) async {
    controller.add(
      const ActiveRideConnectionChanged(
        ActiveRideRealtimeConnectionState.connected,
      ),
    );
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> sendPresence(RideLocationSample sample) async {}

  @override
  Future<void> sendQuickAction(
    LiveQuickActionKind kind, {
    String? reason,
  }) async {}
}

class AuditLocationProvider implements RideLocationProvider {
  final StreamController<RideLocationSample> controller =
      StreamController<RideLocationSample>.broadcast();

  @override
  Stream<RideLocationSample> get samples => controller.stream;

  @override
  Future<RideLocationPermission> checkPermission() async =>
      RideLocationPermission.granted;

  @override
  Future<RideLocationPermission> requestPermission() async =>
      RideLocationPermission.granted;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class AuditRoutePlannerApi implements RoutePlannerApi {
  @override
  Future<SavedRoutePlan?> fetchRoutePlan(String rideId) async => plan();

  @override
  Future<List<TrafficIncident>> fetchTrafficIncidents(
    RouteOption route,
  ) async => <TrafficIncident>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class AuditRideSosApi implements RideSosApi {
  @override
  Future<List<RideSos>> fetchSos(String rideId) async => <RideSos>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const List<GeoPoint> routePoints = <GeoPoint>[
  GeoPoint(latitude: -6.7320, longitude: 108.5520),
  GeoPoint(latitude: -6.7340, longitude: 108.5560),
  GeoPoint(latitude: -6.7380, longitude: 108.5570),
  GeoPoint(latitude: -6.7420, longitude: 108.5600),
];

SavedRoutePlan plan() {
  return SavedRoutePlan(
    revision: 2,
    travelMode: RouteTravelMode.twoWheeler,
    originLabel: 'Alun-alun Kejaksan',
    origin: routePoints.first,
    destinationLabel: 'Pantai Kejawanan',
    destination: routePoints.last,
    route: RouteOption(
      routeIndex: 0,
      labels: const <String>['RECOMMENDED'],
      distanceMeters: 1400,
      durationSeconds: 300,
      encodedPolyline: encode(routePoints),
      legs: const <RouteLeg>[
        RouteLeg(distanceMeters: 1400, durationSeconds: 300),
      ],
      maneuvers: const <RouteManeuver>[
        RouteManeuver(
          instruction: 'Belok kanan ke Jalan Siliwangi',
          type: 'right',
          distanceMeters: 450,
          durationSeconds: 60,
          beginShapeIndex: 1,
          endShapeIndex: 2,
          verbalPreTransitionInstruction: null,
          verbalTransitionInstruction: null,
          verbalPostTransitionInstruction: null,
        ),
      ],
    ),
    stops: const <PlanningStop>[],
  );
}

String encode(List<GeoPoint> points) {
  int lastLatitude = 0;
  int lastLongitude = 0;
  final StringBuffer output = StringBuffer();
  void write(int value) {
    int current = value < 0 ? ~(value << 1) : value << 1;
    while (current >= 0x20) {
      output.writeCharCode((0x20 | (current & 0x1f)) + 63);
      current >>= 5;
    }
    output.writeCharCode(current + 63);
  }

  for (final GeoPoint point in points) {
    final int latitude = (point.latitude * 1e5).round();
    final int longitude = (point.longitude * 1e5).round();
    write(latitude - lastLatitude);
    write(longitude - lastLongitude);
    lastLatitude = latitude;
    lastLongitude = longitude;
  }
  return output.toString();
}

Ride activeRide() => Ride(
  id: 'ride-1',
  clubId: 'club-1',
  title: 'Sunday Morning Ride Cirebon',
  status: RideStatus.active,
  scheduledStartAt: null,
  actualStartAt: DateTime.now().subtract(const Duration(minutes: 20)),
  endedAt: null,
  notes: null,
);

LiveRiderPresence presence(
  String id,
  String name,
  RideRole role, {
  Duration age = Duration.zero,
}) {
  final DateTime at = DateTime.now().subtract(age);
  return LiveRiderPresence(
    riderId: id,
    displayName: name,
    role: role,
    latitude: routePoints[1].latitude,
    longitude: routePoints[1].longitude,
    observedAt: at,
    receivedAt: at,
    movement: RideMovementState.moving,
    freshness: age > const Duration(minutes: 2)
        ? LivePresenceFreshness.stale
        : LivePresenceFreshness.live,
  );
}

/// Voice transport for screens and audits: joins at once, records calls and
/// lets a test push room events.
class AuditVoiceTransport implements RideVoiceTransport {
  final StreamController<RideVoiceEvent> controller =
      StreamController<RideVoiceEvent>.broadcast();
  bool? microphoneEnabled;
  final List<String> moderatorMuted = <String>[];

  @override
  Stream<RideVoiceEvent> get events => controller.stream;

  @override
  bool get supportsLocalMute => false;

  @override
  Future<void> connect({
    required String rideId,
    required RideVoiceMode mode,
    required bool microphoneEnabled,
  }) async {
    this.microphoneEnabled = microphoneEnabled;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> setMode(RideVoiceMode mode) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    microphoneEnabled = enabled;
  }

  @override
  Future<void> setPushToTalkActive(bool active) async {
    microphoneEnabled = active;
  }

  @override
  Future<void> setParticipantAudioEnabled(String riderId, bool enabled) async {}

  @override
  Future<void> moderatorMute(String riderId) async {
    moderatorMuted.add(riderId);
  }
}

class Harness {
  Harness(RideRole role, {AuditRealtimeClient? realtime, this.voice})
    : realtime = realtime ?? AuditRealtimeClient(),
      membership = RideMembership(
        rideId: 'ride-1',
        riderId: 'rider-me',
        role: role,
        status: RideMembershipStatus.active,
      );

  final RideMembership membership;
  final AuditRealtimeClient realtime;

  /// When set, the screen gets the intercom flag on and this transport.
  final AuditVoiceTransport? voice;
  final AuditLocationProvider location = AuditLocationProvider();
  late final RideLocationSessionController session =
      RideLocationSessionController(
        locationProvider: location,
        realtimeClient: realtime,
      );
  late final ActiveRideGroupController group = ActiveRideGroupController(
    rideId: 'ride-1',
    realtimeClient: realtime,
  )..start();
  late final ActiveRideRuntime runtime = ActiveRideRuntime(
    rideId: 'ride-1',
    realtimeClient: realtime,
    locationProvider: location,
    locationSession: session,
    groupController: group,
    voiceTransportFactory: voice == null ? null : () => voice!,
  );

  Widget screen() => ActiveRideNavigationScreen(
    ride: activeRide(),
    membership: membership,
    runtime: runtime,
    routePlannerApi: AuditRoutePlannerApi(),
    rideSosApi: AuditRideSosApi(),
    voiceIntercomEnabled: voice != null,
    onOpenLiveGroup: () async {},
    onOpenTracking: () async {},
    onOpenComms: () async {},
    onOpenSos: () async {},
  );

  void groupSnapshot({bool stale = false}) {
    realtime.controller.add(
      ActiveRideSnapshotReceived(
        rideId: 'ride-1',
        presences: <LiveRiderPresence>[
          presence('rider-me', 'Saya', membership.role),
          presence('rider-l', 'Andi', RideRole.leader),
          presence('rider-s', 'Budi', RideRole.sweeper),
          presence('rider-2', 'Citra', RideRole.member),
          presence('rider-3', 'Dedi', RideRole.member),
          presence(
            'rider-4',
            'Eko',
            RideRole.member,
            age: stale ? const Duration(minutes: 6) : Duration.zero,
          ),
        ],
        separation: null,
      ),
    );
  }

  void gps(GeoPoint point) {
    location.controller.add(
      RideLocationSample(
        latitude: point.latitude,
        longitude: point.longitude,
        observedAt: DateTime.now(),
        movement: RideMovementState.moving,
      ),
    );
  }
}
