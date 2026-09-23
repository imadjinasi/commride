enum RiderNotificationScope {
  account,
  club;

  static RiderNotificationScope fromJson(Object? value) {
    return switch (value) {
      'account' => RiderNotificationScope.account,
      'club' => RiderNotificationScope.club,
      _ => throw const FormatException('Unknown notification scope.'),
    };
  }
}

class RiderNotification {
  const RiderNotification({
    required this.id,
    required this.scope,
    required this.clubId,
    required this.rideId,
    required this.kind,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    required this.readAt,
  });

  final String id;
  final RiderNotificationScope scope;
  final String? clubId;
  final String? rideId;
  final String kind;
  final String title;
  final String body;
  final Map<String, String> data;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory RiderNotification.fromJson(Map<String, Object?> json) {
    final Object? rawData = json['data'];
    final Map<String, String> data = <String, String>{};
    if (rawData is Map<String, Object?>) {
      for (final MapEntry<String, Object?> entry in rawData.entries) {
        final Object? value = entry.value;
        if (value is String) {
          data[entry.key] = value;
        }
      }
    }

    return RiderNotification(
      id: json['id']! as String,
      scope: RiderNotificationScope.fromJson(json['scope']),
      clubId: json['clubId'] as String?,
      rideId: json['rideId'] as String?,
      kind: json['kind']! as String,
      title: json['title']! as String,
      body: json['body']! as String,
      data: Map<String, String>.unmodifiable(data),
      createdAt: DateTime.parse(json['createdAt']! as String),
      readAt: json['readAt'] == null
          ? null
          : DateTime.parse(json['readAt']! as String),
    );
  }
}
