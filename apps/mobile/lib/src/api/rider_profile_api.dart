import '../models/rider_profile.dart';

abstract interface class RiderProfileApi {
  Future<RiderProfile?> fetchProfile();

  Future<RiderProfile> saveProfile(RiderProfileInput input);
}

class RiderProfileApiException implements Exception {
  const RiderProfileApiException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'RiderProfileApiException($statusCode, $message)';
}
