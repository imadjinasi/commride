import '../models/ride_recap.dart';

abstract interface class RideRecapApi {
  Future<RideRecap> fetchRecap(String rideId);
}

class RideRecapApiException implements Exception {
  const RideRecapApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'RideRecapApiException($code): $message';
}
