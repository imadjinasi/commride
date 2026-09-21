enum RidePushPermission {
  notDetermined,
  denied,
  authorized,
  provisional;

  bool get canReceive =>
      this == RidePushPermission.authorized ||
      this == RidePushPermission.provisional;
}

class RideForegroundPush {
  const RideForegroundPush({
    required this.title,
    required this.body,
    required this.data,
  });

  final String? title;
  final String? body;
  final Map<String, String> data;

  String get displayText {
    final String? normalizedTitle = switch (title?.trim()) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    final String? normalizedBody = switch (body?.trim()) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };

    if (normalizedTitle != null && normalizedBody != null) {
      return '$normalizedTitle · $normalizedBody';
    }
    return normalizedTitle ?? normalizedBody ?? 'Notifikasi Ride baru';
  }
}

abstract interface class RidePushMessaging {
  Future<RidePushPermission> checkPermission();

  Future<RidePushPermission> requestPermission();

  Future<String?> currentToken();

  Stream<String> get tokenRefreshes;

  Stream<RideForegroundPush> get foregroundMessages;
}
