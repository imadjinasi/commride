/// Join permission for one Ride intercom room, minted by the CommRide API.
class IntercomJoinGrant {
  const IntercomJoinGrant({
    required this.provider,
    required this.authToken,
    required this.baseDomain,
    required this.canModerate,
  });

  factory IntercomJoinGrant.fromJson(Map<String, Object?> json) {
    final Object? provider = json['provider'];
    final Object? authToken = json['authToken'];
    final Object? baseDomain = json['baseDomain'];
    final Object? canModerate = json['canModerate'];
    if (provider is! String ||
        authToken is! String ||
        authToken.isEmpty ||
        baseDomain is! String ||
        canModerate is! bool) {
      throw const FormatException('Invalid intercom grant.');
    }
    return IntercomJoinGrant(
      provider: provider,
      authToken: authToken,
      baseDomain: baseDomain,
      canModerate: canModerate,
    );
  }

  final String provider;
  final String authToken;
  final String baseDomain;
  final bool canModerate;
}

abstract interface class IntercomApi {
  Future<IntercomJoinGrant> requestJoin(String rideId);
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
