import '../models/ride_briefing.dart';

abstract interface class RideBriefingApi {
  Future<RideBriefingView?> fetchBriefing(String rideId);

  Future<RideBriefingView> publishBriefing({
    required String rideId,
    required String? notes,
  });

  Future<RideBriefingView> acknowledgeBriefing(String rideId);
}

class RideBriefingApiException implements Exception {
  const RideBriefingApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() {
    return 'RideBriefingApiException($statusCode, $code, $message)';
  }
}
