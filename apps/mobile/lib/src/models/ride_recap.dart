import 'club_ride.dart';

class RideRecapParticipant {
  const RideRecapParticipant({
    required this.riderId,
    required this.displayName,
    required this.role,
    required this.membershipStatus,
  });

  final String riderId;
  final String displayName;
  final RideRole role;
  final RideMembershipStatus membershipStatus;

  factory RideRecapParticipant.fromJson(Map<String, Object?> json) {
    return RideRecapParticipant(
      riderId: _requiredString(json['riderId'], 'participant.riderId'),
      displayName: _requiredString(
        json['displayName'],
        'participant.displayName',
      ),
      role: RideRole.fromWireValue(
        _requiredString(json['role'], 'participant.role'),
      ),
      membershipStatus: RideMembershipStatus.fromWireValue(
        _requiredString(
          json['membershipStatus'],
          'participant.membershipStatus',
        ),
      ),
    );
  }
}

class RideRecapPlannedRoute {
  const RideRecapPlannedRoute({
    required this.routePlanId,
    required this.revision,
    required this.originLabel,
    required this.destinationLabel,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.stopCount,
  });

  final String routePlanId;
  final int revision;
  final String? originLabel;
  final String? destinationLabel;
  final int distanceMeters;
  final int durationSeconds;
  final int stopCount;

  factory RideRecapPlannedRoute.fromJson(Map<String, Object?> json) {
    return RideRecapPlannedRoute(
      routePlanId: _requiredString(json['routePlanId'], 'routePlanId'),
      revision: _requiredInt(json['revision'], 'revision'),
      originLabel: _optionalString(json['originLabel'], 'originLabel'),
      destinationLabel: _optionalString(
        json['destinationLabel'],
        'destinationLabel',
      ),
      distanceMeters: _requiredInt(json['distanceMeters'], 'distanceMeters'),
      durationSeconds: _requiredInt(
        json['durationSeconds'],
        'durationSeconds',
      ),
      stopCount: _requiredInt(json['stopCount'], 'stopCount'),
    );
  }
}

class RideRecapJourney {
  const RideRecapJourney({
    required this.sampleCount,
    required this.trackedRiderCount,
    required this.firstObservedAt,
    required this.lastObservedAt,
    required this.leaderTrackedDistanceMeters,
  });

  final int sampleCount;
  final int trackedRiderCount;
  final DateTime? firstObservedAt;
  final DateTime? lastObservedAt;
  final int? leaderTrackedDistanceMeters;

  bool get hasSamples => sampleCount > 0;

  factory RideRecapJourney.fromJson(Map<String, Object?> json) {
    return RideRecapJourney(
      sampleCount: _requiredInt(json['sampleCount'], 'sampleCount'),
      trackedRiderCount: _requiredInt(
        json['trackedRiderCount'],
        'trackedRiderCount',
      ),
      firstObservedAt: _optionalDate(
        json['firstObservedAt'],
        'firstObservedAt',
      ),
      lastObservedAt: _optionalDate(json['lastObservedAt'], 'lastObservedAt'),
      leaderTrackedDistanceMeters: _optionalInt(
        json['leaderTrackedDistanceMeters'],
        'leaderTrackedDistanceMeters',
      ),
    );
  }
}

class RideRecapCheckpoint {
  const RideRecapCheckpoint({
    required this.checkpointId,
    required this.label,
    required this.checkpointType,
    required this.checkInCount,
    required this.participantCount,
    required this.releasedAt,
  });

  final String checkpointId;
  final String label;
  final String checkpointType;
  final int checkInCount;
  final int participantCount;
  final DateTime? releasedAt;

  factory RideRecapCheckpoint.fromJson(Map<String, Object?> json) {
    return RideRecapCheckpoint(
      checkpointId: _requiredString(json['checkpointId'], 'checkpointId'),
      label: _requiredString(json['label'], 'checkpoint.label'),
      checkpointType: _requiredString(
        json['checkpointType'],
        'checkpointType',
      ),
      checkInCount: _requiredInt(json['checkInCount'], 'checkInCount'),
      participantCount: _requiredInt(
        json['participantCount'],
        'participantCount',
      ),
      releasedAt: _optionalDate(json['releasedAt'], 'releasedAt'),
    );
  }
}

class RideRecapIncident {
  const RideRecapIncident({
    required this.sosId,
    required this.riderId,
    required this.riderDisplayName,
    required this.state,
    required this.reason,
    required this.raisedAt,
    required this.closedAt,
  });

  final String sosId;
  final String riderId;
  final String riderDisplayName;
  final String state;
  final String? reason;
  final DateTime raisedAt;
  final DateTime? closedAt;

  factory RideRecapIncident.fromJson(Map<String, Object?> json) {
    const Set<String> states = <String>{'active', 'cancelled', 'resolved'};
    final String state = _requiredString(json['state'], 'incident.state');
    if (!states.contains(state)) {
      throw FormatException('Invalid Ride recap incident state: $state');
    }

    return RideRecapIncident(
      sosId: _requiredString(json['sosId'], 'sosId'),
      riderId: _requiredString(json['riderId'], 'incident.riderId'),
      riderDisplayName: _requiredString(
        json['riderDisplayName'],
        'incident.riderDisplayName',
      ),
      state: state,
      reason: _optionalString(json['reason'], 'incident.reason'),
      raisedAt: _requiredDate(json['raisedAt'], 'incident.raisedAt'),
      closedAt: _optionalDate(json['closedAt'], 'incident.closedAt'),
    );
  }
}

class RideRecap {
  const RideRecap({
    required this.rideId,
    required this.title,
    required this.actualStartAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.participants,
    required this.plannedRoute,
    required this.journey,
    required this.checkpoints,
    required this.incidents,
    required this.generatedAt,
  });

  final String rideId;
  final String title;
  final DateTime? actualStartAt;
  final DateTime? endedAt;
  final int? durationSeconds;
  final List<RideRecapParticipant> participants;
  final RideRecapPlannedRoute? plannedRoute;
  final RideRecapJourney journey;
  final List<RideRecapCheckpoint> checkpoints;
  final List<RideRecapIncident> incidents;
  final DateTime generatedAt;

  factory RideRecap.fromJson(Map<String, Object?> json) {
    final Object? rawParticipants = json['participants'];
    final Object? rawJourney = json['journey'];
    final Object? rawCheckpoints = json['checkpoints'];
    final Object? rawIncidents = json['incidents'];
    final Object? rawPlannedRoute = json['plannedRoute'];

    if (rawParticipants is! List<Object?> ||
        rawJourney is! Map<String, Object?> ||
        rawCheckpoints is! List<Object?> ||
        rawIncidents is! List<Object?>) {
      throw const FormatException('Invalid Ride recap response.');
    }

    return RideRecap(
      rideId: _requiredString(json['rideId'], 'rideId'),
      title: _requiredString(json['title'], 'title'),
      actualStartAt: _optionalDate(json['actualStartAt'], 'actualStartAt'),
      endedAt: _optionalDate(json['endedAt'], 'endedAt'),
      durationSeconds: _optionalInt(json['durationSeconds'], 'durationSeconds'),
      participants: List<RideRecapParticipant>.unmodifiable(
        rawParticipants.map((Object? item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid Ride recap participant.');
          }
          return RideRecapParticipant.fromJson(item);
        }),
      ),
      plannedRoute: rawPlannedRoute == null
          ? null
          : rawPlannedRoute is Map<String, Object?>
          ? RideRecapPlannedRoute.fromJson(rawPlannedRoute)
          : throw const FormatException('Invalid Ride recap planned route.'),
      journey: RideRecapJourney.fromJson(rawJourney),
      checkpoints: List<RideRecapCheckpoint>.unmodifiable(
        rawCheckpoints.map((Object? item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid Ride recap checkpoint.');
          }
          return RideRecapCheckpoint.fromJson(item);
        }),
      ),
      incidents: List<RideRecapIncident>.unmodifiable(
        rawIncidents.map((Object? item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid Ride recap incident.');
          }
          return RideRecapIncident.fromJson(item);
        }),
      ),
      generatedAt: _requiredDate(json['generatedAt'], 'generatedAt'),
    );
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid Ride recap $field.');
  }
  return value;
}

String? _optionalString(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Invalid Ride recap $field.');
  }
  return value;
}

int _requiredInt(Object? value, String field) {
  if (value is! num || value.toInt() != value) {
    throw FormatException('Invalid Ride recap $field.');
  }
  return value.toInt();
}

int? _optionalInt(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return _requiredInt(value, field);
}

DateTime _requiredDate(Object? value, String field) {
  if (value is! String) {
    throw FormatException('Invalid Ride recap $field.');
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Invalid Ride recap $field.');
  }
  return parsed;
}

DateTime? _optionalDate(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return _requiredDate(value, field);
}
