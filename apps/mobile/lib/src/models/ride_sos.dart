import 'club_ride.dart';

enum RideSosStatus {
  active,
  cancelled,
  resolved;

  static RideSosStatus fromWireValue(String value) {
    return RideSosStatus.values.firstWhere(
      (RideSosStatus status) => status.name == value,
      orElse: () => throw FormatException('Unknown SOS state: $value'),
    );
  }

  String get label {
    return switch (this) {
      RideSosStatus.active => 'Aktif',
      RideSosStatus.cancelled => 'Dibatalkan',
      RideSosStatus.resolved => 'Selesai',
    };
  }
}

enum RidePresenceFreshness {
  live,
  stale,
  offline;

  static RidePresenceFreshness fromWireValue(String value) {
    return RidePresenceFreshness.values.firstWhere(
      (RidePresenceFreshness freshness) => freshness.name == value,
      orElse: () => throw FormatException('Unknown presence freshness: $value'),
    );
  }

  String get label {
    return switch (this) {
      RidePresenceFreshness.live => 'Live',
      RidePresenceFreshness.stale => 'Stale',
      RidePresenceFreshness.offline => 'Offline',
    };
  }
}

class RideSosPresence {
  const RideSosPresence({
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    required this.receivedAt,
    required this.freshness,
    required this.movement,
  });

  final double latitude;
  final double longitude;
  final DateTime observedAt;
  final DateTime receivedAt;
  final RidePresenceFreshness freshness;
  final String movement;

  factory RideSosPresence.fromJson(Map<String, Object?> json) {
    final Object? latitude = json['latitude'];
    final Object? longitude = json['longitude'];
    final Object? observedAt = json['observedAt'];
    final Object? receivedAt = json['receivedAt'];
    final Object? freshness = json['freshness'];
    final Object? movement = json['movement'];

    if (latitude is! num ||
        longitude is! num ||
        observedAt is! String ||
        receivedAt is! String ||
        freshness is! String ||
        movement is! String) {
      throw const FormatException('Invalid SOS presence snapshot.');
    }

    final DateTime? parsedObservedAt = DateTime.tryParse(observedAt);
    final DateTime? parsedReceivedAt = DateTime.tryParse(receivedAt);
    if (parsedObservedAt == null || parsedReceivedAt == null) {
      throw const FormatException('Invalid SOS presence timestamps.');
    }

    return RideSosPresence(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      observedAt: parsedObservedAt,
      receivedAt: parsedReceivedAt,
      freshness: RidePresenceFreshness.fromWireValue(freshness),
      movement: movement,
    );
  }
}

class RideSos {
  const RideSos({
    required this.id,
    required this.rideId,
    required this.riderId,
    required this.riderDisplayName,
    required this.riderRideRole,
    required this.status,
    required this.clientCommandId,
    required this.reason,
    required this.raisedAt,
    required this.cancelledAt,
    required this.resolvedAt,
    required this.resolvedByRiderId,
    required this.presence,
  });

  final String id;
  final String rideId;
  final String riderId;
  final String riderDisplayName;
  final RideRole riderRideRole;
  final RideSosStatus status;
  final String clientCommandId;
  final String? reason;
  final DateTime raisedAt;
  final DateTime? cancelledAt;
  final DateTime? resolvedAt;
  final String? resolvedByRiderId;
  final RideSosPresence? presence;

  factory RideSos.fromJson(Map<String, Object?> json) {
    final Object? rawPresence = json['presence'];
    final Object? raisedAt = json['raisedAt'];
    if (raisedAt is! String) {
      throw const FormatException('Invalid SOS raisedAt.');
    }
    final DateTime? parsedRaisedAt = DateTime.tryParse(raisedAt);
    if (parsedRaisedAt == null) {
      throw const FormatException('Invalid SOS raisedAt.');
    }

    return RideSos(
      id: _requiredString(json['id'], 'id'),
      rideId: _requiredString(json['rideId'], 'rideId'),
      riderId: _requiredString(json['riderId'], 'riderId'),
      riderDisplayName: _requiredString(
        json['riderDisplayName'],
        'riderDisplayName',
      ),
      riderRideRole: RideRole.fromWireValue(
        _requiredString(json['riderRideRole'], 'riderRideRole'),
      ),
      status: RideSosStatus.fromWireValue(
        _requiredString(json['state'], 'state'),
      ),
      clientCommandId: _requiredString(
        json['clientCommandId'],
        'clientCommandId',
      ),
      reason: json['reason'] as String?,
      raisedAt: parsedRaisedAt,
      cancelledAt: _optionalDate(json['cancelledAt']),
      resolvedAt: _optionalDate(json['resolvedAt']),
      resolvedByRiderId: json['resolvedByRiderId'] as String?,
      presence: rawPresence == null
          ? null
          : rawPresence is Map<String, Object?>
          ? RideSosPresence.fromJson(rawPresence)
          : throw const FormatException('Invalid SOS presence.'),
    );
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid SOS $field.');
  }
  return value;
}

DateTime? _optionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('Invalid SOS timestamp.');
  }
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('Invalid SOS timestamp.');
  }
  return parsed;
}
