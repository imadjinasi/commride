import '../models/club_ride.dart';
import 'location_provider.dart';

const Duration livePresenceFreshnessWindow = Duration(seconds: 30);

enum LivePresenceFreshness {
  live,
  stale,
  offline;

  String get label {
    return switch (this) {
      LivePresenceFreshness.live => 'Live',
      LivePresenceFreshness.stale => 'Stale',
      LivePresenceFreshness.offline => 'Offline',
    };
  }

  static LivePresenceFreshness fromWireValue(String value) {
    return switch (value) {
      'live' => LivePresenceFreshness.live,
      'stale' => LivePresenceFreshness.stale,
      'offline' => LivePresenceFreshness.offline,
      _ => throw FormatException('Unknown presence freshness: $value'),
    };
  }
}

class LiveRiderPresence {
  const LiveRiderPresence({
    required this.riderId,
    required this.displayName,
    required this.role,
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    required this.receivedAt,
    required this.movement,
    required this.freshness,
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

  LiveRiderPresence copyWith({
    LivePresenceFreshness? freshness,
  }) {
    return LiveRiderPresence(
      riderId: riderId,
      displayName: displayName,
      role: role,
      latitude: latitude,
      longitude: longitude,
      observedAt: observedAt,
      receivedAt: receivedAt,
      movement: movement,
      freshness: freshness ?? this.freshness,
    );
  }

  LivePresenceFreshness effectiveFreshness(
    DateTime now, {
    Duration liveWindow = livePresenceFreshnessWindow,
  }) {
    if (freshness != LivePresenceFreshness.live) {
      return freshness;
    }

    final Duration age = now.toUtc().difference(observedAt.toUtc());
    if (age > liveWindow) {
      return LivePresenceFreshness.stale;
    }

    return LivePresenceFreshness.live;
  }

  factory LiveRiderPresence.fromJson(Map<String, Object?> json) {
    final String riderId = _requiredString(json['riderId'], 'riderId');
    final String displayName = _requiredString(
      json['displayName'],
      'displayName',
    );
    final String role = _requiredString(json['role'], 'role');
    final double latitude = _number(json['latitude'], 'latitude');
    final double longitude = _number(json['longitude'], 'longitude');
    final DateTime observedAt = _requiredDate(json['observedAt'], 'observedAt');
    final DateTime receivedAt = _requiredDate(json['receivedAt'], 'receivedAt');
    final String movement = _requiredString(json['movement'], 'movement');
    final String freshness = _requiredString(json['freshness'], 'freshness');

    if (latitude < -90 || latitude > 90) {
      throw const FormatException('Invalid presence latitude.');
    }
    if (longitude < -180 || longitude > 180) {
      throw const FormatException('Invalid presence longitude.');
    }

    return LiveRiderPresence(
      riderId: riderId,
      displayName: displayName,
      role: RideRole.fromWireValue(role),
      latitude: latitude,
      longitude: longitude,
      observedAt: observedAt,
      receivedAt: receivedAt,
      movement: switch (movement) {
        'moving' => RideMovementState.moving,
        'stopped' => RideMovementState.stopped,
        'unknown' => RideMovementState.unknown,
        _ => throw FormatException('Unknown presence movement: $movement'),
      },
      freshness: LivePresenceFreshness.fromWireValue(freshness),
    );
  }
}

enum LiveQuickActionKind {
  stopping,
  leftBehind,
  needHelp;

  String get label {
    return switch (this) {
      LiveQuickActionKind.stopping => 'Saya Berhenti',
      LiveQuickActionKind.leftBehind => 'Saya Tertinggal',
      LiveQuickActionKind.needHelp => 'Butuh Bantuan',
    };
  }

  static LiveQuickActionKind fromWireValue(String value) {
    return switch (value) {
      'stopping' => LiveQuickActionKind.stopping,
      'left_behind' => LiveQuickActionKind.leftBehind,
      'need_help' => LiveQuickActionKind.needHelp,
      _ => throw FormatException('Unknown quick action: $value'),
    };
  }
}

class LiveQuickAction {
  const LiveQuickAction({
    required this.eventId,
    required this.riderId,
    required this.displayName,
    required this.role,
    required this.kind,
    required this.reason,
    required this.raisedAt,
  });

  final String eventId;
  final String riderId;
  final String displayName;
  final RideRole role;
  final LiveQuickActionKind kind;
  final String? reason;
  final DateTime raisedAt;

  factory LiveQuickAction.fromJson(Map<String, Object?> json) {
    final Object? rawRider = json['rider'];
    if (rawRider is! Map<String, Object?>) {
      throw const FormatException('Quick action Rider is required.');
    }

    return LiveQuickAction(
      eventId: _requiredString(json['eventId'], 'eventId'),
      riderId: _requiredString(rawRider['riderId'], 'riderId'),
      displayName: _requiredString(rawRider['displayName'], 'displayName'),
      role: RideRole.fromWireValue(_requiredString(rawRider['role'], 'role')),
      kind: LiveQuickActionKind.fromWireValue(
        _requiredString(json['kind'], 'kind'),
      ),
      reason: _optionalString(json['reason']),
      raisedAt: _requiredDate(json['raisedAt'], 'raisedAt'),
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

  final String normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

double _number(Object? value, String field) {
  if (value is! num) {
    throw FormatException('$field must be numeric.');
  }
  return value.toDouble();
}

DateTime _requiredDate(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field timestamp is required.');
  }

  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$field timestamp is invalid.');
  }
  return parsed;
}
