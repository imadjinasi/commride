import 'club_ride.dart';

enum RideMessageKind {
  chat,
  announcement;

  String get wireValue {
    return switch (this) {
      RideMessageKind.chat => 'chat',
      RideMessageKind.announcement => 'announcement',
    };
  }

  static RideMessageKind fromWireValue(String value) {
    return switch (value) {
      'chat' => RideMessageKind.chat,
      'announcement' => RideMessageKind.announcement,
      _ => throw FormatException('Unknown Ride message kind: $value'),
    };
  }
}

class RideMessage {
  const RideMessage({
    required this.id,
    required this.rideId,
    required this.senderRiderId,
    required this.senderDisplayName,
    required this.senderRideRole,
    required this.kind,
    required this.body,
    required this.clientMessageId,
    required this.createdAt,
  });

  final String id;
  final String rideId;
  final String senderRiderId;
  final String senderDisplayName;
  final RideRole senderRideRole;
  final RideMessageKind kind;
  final String body;
  final String clientMessageId;
  final DateTime createdAt;

  factory RideMessage.fromJson(Map<String, Object?> json) {
    return RideMessage(
      id: _requiredString(json['id'], 'id'),
      rideId: _requiredString(json['rideId'], 'rideId'),
      senderRiderId: _requiredString(
        json['senderRiderId'],
        'senderRiderId',
      ),
      senderDisplayName: _requiredString(
        json['senderDisplayName'],
        'senderDisplayName',
      ),
      senderRideRole: RideRole.fromWireValue(
        _requiredString(json['senderRideRole'], 'senderRideRole'),
      ),
      kind: RideMessageKind.fromWireValue(
        _requiredString(json['kind'], 'kind'),
      ),
      body: _requiredString(json['body'], 'body'),
      clientMessageId: _requiredString(
        json['clientMessageId'],
        'clientMessageId',
      ),
      createdAt: _requiredDate(json['createdAt'], 'createdAt'),
    );
  }
}

class RideMessagePage {
  const RideMessagePage({
    required this.messages,
    required this.nextCursor,
  });

  final List<RideMessage> messages;
  final String? nextCursor;

  factory RideMessagePage.fromJson(Map<String, Object?> json) {
    final Object? rawMessages = json['messages'];
    if (rawMessages is! List<Object?>) {
      throw const FormatException('Ride messages must be a list.');
    }

    return RideMessagePage(
      messages: rawMessages.map((Object? value) {
        if (value is! Map<String, Object?>) {
          throw const FormatException('Ride message entry is invalid.');
        }
        return RideMessage.fromJson(value);
      }).toList(growable: false),
      nextCursor: _optionalString(json['nextCursor']),
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
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected a non-empty optional string.');
  }
  return value.trim();
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
