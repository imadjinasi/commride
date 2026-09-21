enum RidePushPlatform {
  android,
  ios;

  String get wireValue => name;
}

abstract interface class PushTokenApi {
  Future<void> registerToken({
    required String token,
    required RidePushPlatform platform,
  });

  Future<void> unregisterToken({
    required String token,
    required RidePushPlatform platform,
  });
}

class PushTokenApiException implements Exception {
  const PushTokenApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'PushTokenApiException($code): $message';
}
