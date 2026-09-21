import '../models/ride_sos.dart';

abstract interface class RideSosApi {
  Future<List<RideSos>> fetchSos(String rideId);

  Future<RideSos> raiseSos({
    required String rideId,
    required String clientCommandId,
    required String? reason,
  });

  Future<RideSos> cancelSos({required String rideId, required String sosId});

  Future<RideSos> resolveSos({required String rideId, required String sosId});
}

class RideSosApiException implements Exception {
  const RideSosApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'RideSosApiException($code): $message';
}
