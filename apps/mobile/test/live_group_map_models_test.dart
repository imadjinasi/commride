import 'package:commride_mobile/src/active_ride/convoy_separation.dart';
import 'package:commride_mobile/src/active_ride/live_group_map_models.dart';
import 'package:commride_mobile/src/active_ride/live_group_models.dart';
import 'package:commride_mobile/src/active_ride/location_provider.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:flutter_test/flutter_test.dart';

LiveRiderPresence presence({
  required String riderId,
  required String displayName,
  required RideRole role,
  required double latitude,
  required double longitude,
  required DateTime observedAt,
  LivePresenceFreshness freshness = LivePresenceFreshness.live,
}) {
  return LiveRiderPresence(
    riderId: riderId,
    displayName: displayName,
    role: role,
    latitude: latitude,
    longitude: longitude,
    observedAt: observedAt,
    receivedAt: observedAt.add(const Duration(seconds: 1)),
    movement: RideMovementState.moving,
    freshness: freshness,
  );
}

LiveConvoySeparation separation(ConvoySeparationPhase phase) {
  return LiveConvoySeparation(
    phase: phase,
    dataSufficient: true,
    components: const <List<String>>[
      <String>['leader', 'sweeper'],
      <String>['isolated'],
    ],
    isolatedRiderIds: const <String>['isolated'],
    sweeperComponentRiderIds: const <String>['leader', 'sweeper'],
    firstSplitObservedAt: DateTime.utc(2026, 9, 18, 10),
    confirmedAt: phase == ConvoySeparationPhase.separatedAttention
        ? DateTime.utc(2026, 9, 18, 10, 0, 20)
        : null,
    recoveryObservedAt: null,
    lastUpdatedAt: DateTime.utc(2026, 9, 18, 10, 0, 20),
  );
}

void main() {
  test('maps Rider identity, role, coordinate, and deterministic order', () {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final LiveGroupMapPresentation model =
        LiveGroupMapPresentation.fromPresences(
          presences: <LiveRiderPresence>[
            presence(
              riderId: 'member',
              displayName: 'Member',
              role: RideRole.member,
              latitude: -6.73,
              longitude: 108.55,
              observedAt: now,
            ),
            presence(
              riderId: 'leader',
              displayName: 'Leader',
              role: RideRole.leader,
              latitude: -6.72,
              longitude: 108.54,
              observedAt: now,
            ),
          ],
          now: now,
        );

    expect(
      model.markers.map((LiveGroupMapMarker item) => item.riderId),
      <String>['leader', 'member'],
    );
    expect(model.markers.first.role, RideRole.leader);
    expect(model.markers.first.latitude, -6.72);
    expect(model.markers.first.longitude, 108.54);
  });

  test('ages only server-Live marker to Stale without moving coordinate', () {
    final DateTime observedAt = DateTime.utc(2026, 9, 18, 10);
    final LiveGroupMapPresentation model =
        LiveGroupMapPresentation.fromPresences(
          presences: <LiveRiderPresence>[
            presence(
              riderId: 'rider-1',
              displayName: 'Rider One',
              role: RideRole.member,
              latitude: -6.732,
              longitude: 108.552,
              observedAt: observedAt,
            ),
          ],
          now: observedAt.add(const Duration(seconds: 31)),
        );

    final LiveGroupMapMarker marker = model.markers.single;
    expect(marker.freshness, LivePresenceFreshness.stale);
    expect(marker.isLastKnown, isTrue);
    expect(marker.latitude, -6.732);
    expect(marker.longitude, 108.552);
  });

  test('server Offline marker never becomes Live locally', () {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final LiveGroupMapPresentation model =
        LiveGroupMapPresentation.fromPresences(
          presences: <LiveRiderPresence>[
            presence(
              riderId: 'rider-1',
              displayName: 'Rider One',
              role: RideRole.member,
              latitude: -6.732,
              longitude: 108.552,
              observedAt: now,
              freshness: LivePresenceFreshness.offline,
            ),
          ],
          now: now,
        );

    expect(model.markers.single.freshness, LivePresenceFreshness.offline);
    expect(model.markers.single.isLastKnown, isTrue);
  });

  test('dedupes Rider and ignores older observation regression', () {
    final DateTime newer = DateTime.utc(2026, 9, 18, 10, 0, 10);
    final LiveGroupMapPresentation model =
        LiveGroupMapPresentation.fromPresences(
          presences: <LiveRiderPresence>[
            presence(
              riderId: 'rider-1',
              displayName: 'Newest',
              role: RideRole.member,
              latitude: -6.73,
              longitude: 108.55,
              observedAt: newer,
            ),
            presence(
              riderId: 'rider-1',
              displayName: 'Older',
              role: RideRole.member,
              latitude: -7,
              longitude: 109,
              observedAt: newer.subtract(const Duration(seconds: 5)),
            ),
          ],
          now: newer,
        );

    expect(model.markers, hasLength(1));
    expect(model.markers.single.displayName, 'Newest');
    expect(model.markers.single.latitude, -6.73);
  });

  test('same observation may conservatively degrade to Offline', () {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final LiveGroupMapPresentation model =
        LiveGroupMapPresentation.fromPresences(
          presences: <LiveRiderPresence>[
            presence(
              riderId: 'rider-1',
              displayName: 'Rider One',
              role: RideRole.member,
              latitude: -6.73,
              longitude: 108.55,
              observedAt: now,
            ),
            presence(
              riderId: 'rider-1',
              displayName: 'Rider One',
              role: RideRole.member,
              latitude: -6.73,
              longitude: 108.55,
              observedAt: now,
              freshness: LivePresenceFreshness.offline,
            ),
          ],
          now: now,
        );

    expect(model.markers, hasLength(1));
    expect(model.markers.single.freshness, LivePresenceFreshness.offline);
  });

  test('separation attention comes only from server-derived state', () {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final List<LiveRiderPresence> presences = <LiveRiderPresence>[
      presence(
        riderId: 'leader',
        displayName: 'Leader',
        role: RideRole.leader,
        latitude: -6.72,
        longitude: 108.54,
        observedAt: now,
      ),
      presence(
        riderId: 'isolated',
        displayName: 'Rear Rider',
        role: RideRole.member,
        latitude: -6.8,
        longitude: 108.6,
        observedAt: now,
      ),
    ];

    final LiveGroupMapPresentation candidate =
        LiveGroupMapPresentation.fromPresences(
          presences: presences,
          now: now,
          separation: separation(ConvoySeparationPhase.splitCandidate),
        );
    final LiveGroupMapPresentation confirmed =
        LiveGroupMapPresentation.fromPresences(
          presences: presences,
          now: now,
          separation: separation(
            ConvoySeparationPhase.separatedAttention,
          ),
        );

    expect(
      candidate.markers
          .singleWhere((LiveGroupMapMarker item) => item.riderId == 'isolated')
          .attention,
      LiveGroupMapAttention.inspect,
    );
    expect(
      confirmed.markers
          .singleWhere((LiveGroupMapMarker item) => item.riderId == 'isolated')
          .attention,
      LiveGroupMapAttention.separated,
    );
    expect(
      confirmed.markers
          .singleWhere((LiveGroupMapMarker item) => item.riderId == 'leader')
          .attention,
      LiveGroupMapAttention.normal,
    );
  });

  test('computes group-fit bounds and center from known markers', () {
    final DateTime now = DateTime.utc(2026, 9, 18, 10);
    final LiveGroupMapPresentation model =
        LiveGroupMapPresentation.fromPresences(
          presences: <LiveRiderPresence>[
            presence(
              riderId: 'a',
              displayName: 'A',
              role: RideRole.member,
              latitude: -6.8,
              longitude: 108.5,
              observedAt: now,
            ),
            presence(
              riderId: 'b',
              displayName: 'B',
              role: RideRole.member,
              latitude: -6.7,
              longitude: 108.7,
              observedAt: now,
            ),
          ],
          now: now,
        );

    expect(model.bounds?.south, -6.8);
    expect(model.bounds?.north, -6.7);
    expect(model.bounds?.west, 108.5);
    expect(model.bounds?.east, 108.7);
    expect(model.bounds?.centerLatitude, closeTo(-6.75, 0.000001));
    expect(model.bounds?.centerLongitude, closeTo(108.6, 0.000001));
  });

  test('empty presence produces no markers and no fit bounds', () {
    final LiveGroupMapPresentation model =
        LiveGroupMapPresentation.fromPresences(
          presences: const <LiveRiderPresence>[],
          now: DateTime.utc(2026, 9, 18, 10),
        );

    expect(model.isEmpty, isTrue);
    expect(model.markers, isEmpty);
    expect(model.bounds, isNull);
  });
}
