import 'club_ride.dart';
import 'route_planner.dart';

enum RideCheckpointState {
  current,
  upcoming,
  released;

  String get label {
    return switch (this) {
      RideCheckpointState.current => 'Current',
      RideCheckpointState.upcoming => 'Upcoming',
      RideCheckpointState.released => 'Released',
    };
  }

  static RideCheckpointState fromWireValue(String value) {
    return switch (value) {
      'current' => RideCheckpointState.current,
      'upcoming' => RideCheckpointState.upcoming,
      'released' => RideCheckpointState.released,
      _ => throw FormatException('Unknown Checkpoint state: $value'),
    };
  }
}

class CheckpointParticipant {
  const CheckpointParticipant({
    required this.riderId,
    required this.displayName,
    required this.role,
    required this.membershipStatus,
    required this.checkedInAt,
  });

  final String riderId;
  final String displayName;
  final RideRole role;
  final RideMembershipStatus membershipStatus;
  final DateTime? checkedInAt;

  bool get checkedIn => checkedInAt != null;

  factory CheckpointParticipant.fromJson(Map<String, Object?> json) {
    return CheckpointParticipant(
      riderId: _requiredString(json['riderId'], 'riderId'),
      displayName: _requiredString(json['displayName'], 'displayName'),
      role: RideRole.fromWireValue(_requiredString(json['role'], 'role')),
      membershipStatus: RideMembershipStatus.fromWireValue(
        _requiredString(json['membershipStatus'], 'membershipStatus'),
      ),
      checkedInAt: _optionalDate(json['checkedInAt'], 'checkedInAt'),
    );
  }
}

class RideCheckpointItem {
  const RideCheckpointItem({
    required this.checkpointId,
    required this.sequence,
    required this.label,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    required this.checkpointType,
    required this.plannedDurationMinutes,
    required this.state,
    required this.expectedCount,
    required this.checkedInCount,
    required this.missingCount,
    required this.currentRiderCheckedIn,
    required this.releasedAt,
    required this.participants,
  });

  final String checkpointId;
  final int sequence;
  final String label;
  final String? formattedAddress;
  final double latitude;
  final double longitude;
  final CheckpointType checkpointType;
  final int? plannedDurationMinutes;
  final RideCheckpointState state;
  final int expectedCount;
  final int checkedInCount;
  final int missingCount;
  final bool currentRiderCheckedIn;
  final DateTime? releasedAt;
  final List<CheckpointParticipant> participants;

  factory RideCheckpointItem.fromJson(Map<String, Object?> json) {
    final Object? rawParticipants = json['participants'];
    if (rawParticipants is! List<Object?>) {
      throw const FormatException('Checkpoint participants are required.');
    }

    final int expectedCount = _requiredInt(
      json['expectedCount'],
      'expectedCount',
    );
    final int checkedInCount = _requiredInt(
      json['checkedInCount'],
      'checkedInCount',
    );
    final int missingCount = _requiredInt(json['missingCount'], 'missingCount');

    if (expectedCount < 0 ||
        checkedInCount < 0 ||
        missingCount < 0 ||
        checkedInCount + missingCount != expectedCount) {
      throw const FormatException('Checkpoint counts are inconsistent.');
    }

    return RideCheckpointItem(
      checkpointId: _requiredString(json['checkpointId'], 'checkpointId'),
      sequence: _requiredInt(json['sequence'], 'sequence'),
      label: _requiredString(json['label'], 'label'),
      formattedAddress: _optionalString(json['formattedAddress']),
      latitude: _coordinate(json['latitude'], 'latitude', -90, 90),
      longitude: _coordinate(json['longitude'], 'longitude', -180, 180),
      checkpointType: CheckpointType.fromWireValue(
        _requiredString(json['checkpointType'], 'checkpointType'),
      ),
      plannedDurationMinutes: _optionalInt(
        json['plannedDurationMinutes'],
        'plannedDurationMinutes',
      ),
      state: RideCheckpointState.fromWireValue(
        _requiredString(json['state'], 'state'),
      ),
      expectedCount: expectedCount,
      checkedInCount: checkedInCount,
      missingCount: missingCount,
      currentRiderCheckedIn: _requiredBool(
        json['currentRiderCheckedIn'],
        'currentRiderCheckedIn',
      ),
      releasedAt: _optionalDate(json['releasedAt'], 'releasedAt'),
      participants: rawParticipants
          .map((Object? value) {
            if (value is! Map<String, Object?>) {
              throw const FormatException('Invalid Checkpoint participant.');
            }
            return CheckpointParticipant.fromJson(value);
          })
          .toList(growable: false),
    );
  }
}

class RideCheckpointView {
  const RideCheckpointView({
    required this.rideId,
    required this.routePlanId,
    required this.routePlanRevision,
    required this.checkpoints,
  });

  final String rideId;
  final String routePlanId;
  final int routePlanRevision;
  final List<RideCheckpointItem> checkpoints;

  factory RideCheckpointView.fromJson(Map<String, Object?> json) {
    final Object? rawCheckpoints = json['checkpoints'];
    if (rawCheckpoints is! List<Object?>) {
      throw const FormatException('Checkpoint list is required.');
    }

    return RideCheckpointView(
      rideId: _requiredString(json['rideId'], 'rideId'),
      routePlanId: _requiredString(json['routePlanId'], 'routePlanId'),
      routePlanRevision: _requiredInt(
        json['routePlanRevision'],
        'routePlanRevision',
      ),
      checkpoints: rawCheckpoints
          .map((Object? value) {
            if (value is! Map<String, Object?>) {
              throw const FormatException('Invalid Checkpoint item.');
            }
            return RideCheckpointItem.fromJson(value);
          })
          .toList(growable: false),
    );
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field is required.');
  }
  return value.trim();
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('Expected an optional string.');
  }
  return value;
}

int _requiredInt(Object? value, String field) {
  if (value is! int) {
    throw FormatException('$field must be an integer.');
  }
  return value;
}

int? _optionalInt(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw FormatException('$field must be an integer or null.');
  }
  return value;
}

bool _requiredBool(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('$field must be a boolean.');
  }
  return value;
}

double _coordinate(Object? value, String field, double min, double max) {
  if (value is! num) {
    throw FormatException('$field must be numeric.');
  }
  final double coordinate = value.toDouble();
  if (coordinate < min || coordinate > max) {
    throw FormatException('$field is outside valid range.');
  }
  return coordinate;
}

DateTime? _optionalDate(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('$field must be an ISO timestamp or null.');
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$field timestamp is invalid.');
  }
  return parsed;
}
