import '../models/club_ride.dart';
import 'convoy_separation.dart';
import 'live_group_models.dart';
import 'location_provider.dart';

enum LiveGroupMapAttention {
  normal,
  inspect,
  separated,
}

class LiveGroupMapMarker {
  const LiveGroupMapMarker({
    required this.riderId,
    required this.displayName,
    required this.role,
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    required this.receivedAt,
    required this.movement,
    required this.freshness,
    required this.attention,
  });

  final String riderId;
  final String displayName;
  final RideRole role;
  final double latitude;
  final double longitude;
  final DateTime observedAt;
  final DateTime receivedAt;
  final RideMovementState movement;
  final LivePresenceFreshness freshness;
  final LiveGroupMapAttention attention;

  bool get isLastKnown => freshness != LivePresenceFreshness.live;
}

class LiveGroupMapBounds {
  const LiveGroupMapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  double get centerLatitude => (south + north) / 2;
  double get centerLongitude => (west + east) / 2;
}

class LiveGroupMapPresentation {
  const LiveGroupMapPresentation({
    required this.markers,
    required this.bounds,
    required this.separationPhase,
  });

  final List<LiveGroupMapMarker> markers;
  final LiveGroupMapBounds? bounds;
  final ConvoySeparationPhase? separationPhase;

  bool get isEmpty => markers.isEmpty;

  factory LiveGroupMapPresentation.fromPresences({
    required Iterable<LiveRiderPresence> presences,
    required DateTime now,
    LiveConvoySeparation? separation,
  }) {
    final Map<String, LiveRiderPresence> latestByRider =
        <String, LiveRiderPresence>{};

    for (final LiveRiderPresence candidate in presences) {
      final LiveRiderPresence? current = latestByRider[candidate.riderId];
      if (current == null || _shouldReplace(current, candidate)) {
        latestByRider[candidate.riderId] = candidate;
      }
    }

    final List<LiveGroupMapMarker> markers = latestByRider.values
        .map(
          (LiveRiderPresence presence) => LiveGroupMapMarker(
            riderId: presence.riderId,
            displayName: presence.displayName,
            role: presence.role,
            latitude: presence.latitude,
            longitude: presence.longitude,
            observedAt: presence.observedAt,
            receivedAt: presence.receivedAt,
            movement: presence.movement,
            freshness: presence.effectiveFreshness(now),
            attention: _attentionFor(presence.riderId, separation),
          ),
        )
        .toList(growable: false)
      ..sort(_compareMarkers);

    return LiveGroupMapPresentation(
      markers: List<LiveGroupMapMarker>.unmodifiable(markers),
      bounds: _bounds(markers),
      separationPhase: separation?.phase,
    );
  }
}

bool _shouldReplace(
  LiveRiderPresence current,
  LiveRiderPresence candidate,
) {
  final int observedCompare = candidate.observedAt.compareTo(current.observedAt);
  if (observedCompare > 0) {
    return true;
  }
  if (observedCompare < 0) {
    return false;
  }

  return _freshnessRank(candidate.freshness) >
      _freshnessRank(current.freshness);
}

int _freshnessRank(LivePresenceFreshness freshness) {
  return switch (freshness) {
    LivePresenceFreshness.live => 0,
    LivePresenceFreshness.stale => 1,
    LivePresenceFreshness.offline => 2,
  };
}

LiveGroupMapAttention _attentionFor(
  String riderId,
  LiveConvoySeparation? separation,
) {
  if (separation == null ||
      !separation.isolatedRiderIds.contains(riderId)) {
    return LiveGroupMapAttention.normal;
  }

  return switch (separation.phase) {
    ConvoySeparationPhase.splitCandidate => LiveGroupMapAttention.inspect,
    ConvoySeparationPhase.separatedAttention =>
      LiveGroupMapAttention.separated,
    ConvoySeparationPhase.insufficientData ||
    ConvoySeparationPhase.normal => LiveGroupMapAttention.normal,
  };
}

int _compareMarkers(LiveGroupMapMarker a, LiveGroupMapMarker b) {
  final int roleCompare = _roleRank(a.role).compareTo(_roleRank(b.role));
  if (roleCompare != 0) {
    return roleCompare;
  }

  final int nameCompare = a.displayName.toLowerCase().compareTo(
    b.displayName.toLowerCase(),
  );
  if (nameCompare != 0) {
    return nameCompare;
  }

  return a.riderId.compareTo(b.riderId);
}

int _roleRank(RideRole role) {
  return switch (role) {
    RideRole.leader => 0,
    RideRole.sweeper => 1,
    RideRole.navigator => 2,
    RideRole.member => 3,
  };
}

LiveGroupMapBounds? _bounds(List<LiveGroupMapMarker> markers) {
  if (markers.isEmpty) {
    return null;
  }

  double south = markers.first.latitude;
  double north = markers.first.latitude;
  double west = markers.first.longitude;
  double east = markers.first.longitude;

  for (final LiveGroupMapMarker marker in markers.skip(1)) {
    if (marker.latitude < south) {
      south = marker.latitude;
    }
    if (marker.latitude > north) {
      north = marker.latitude;
    }
    if (marker.longitude < west) {
      west = marker.longitude;
    }
    if (marker.longitude > east) {
      east = marker.longitude;
    }
  }

  return LiveGroupMapBounds(
    south: south,
    west: west,
    north: north,
    east: east,
  );
}
