import '../models/ride_message.dart';

abstract interface class RideCommsApi {
  Future<RideMessagePage> fetchMessages(
    String rideId, {
    String? cursor,
    int limit = 50,
  });

  Future<RideMessage> sendChat({
    required String rideId,
    required String clientMessageId,
    required String body,
  });

  Future<RideMessage> sendAnnouncement({
    required String rideId,
    required String clientMessageId,
    required String body,
  });
}

class RideCommsApiException implements Exception {
  const RideCommsApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'RideCommsApiException($code): $message';
}
