/// Join permission for one Ride intercom room, minted by the CommRide API.
class IntercomJoinGrant {
  const IntercomJoinGrant({
    required this.provider,
    required this.serverUrl,
    required this.authToken,
    required this.canModerate,
  });

  factory IntercomJoinGrant.fromJson(Map<String, Object?> json) {
    final Object? provider = json['provider'];
    final Object? serverUrl = json['serverUrl'];
    final Object? authToken = json['authToken'];
    final Object? canModerate = json['canModerate'];
    if (provider is! String ||
        serverUrl is! String ||
        serverUrl.isEmpty ||
        authToken is! String ||
        authToken.isEmpty ||
        canModerate is! bool) {
      throw const FormatException('Invalid intercom grant.');
    }
    return IntercomJoinGrant(
      provider: provider,
      serverUrl: serverUrl,
      authToken: authToken,
      canModerate: canModerate,
    );
  }

  final String provider;
  final String serverUrl;
  final String authToken;
  final bool canModerate;
}

abstract interface class IntercomApi {
  Future<IntercomJoinGrant> requestJoin(String rideId);

  /// Ride Leader only: mutes [riderId]'s microphone for everyone.
  Future<void> muteRider({required String rideId, required String riderId});
}

class IntercomApiException implements Exception {
  const IntercomApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'IntercomApiException($code): $message';
}
