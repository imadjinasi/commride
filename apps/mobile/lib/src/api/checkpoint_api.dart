import '../models/ride_checkpoint.dart';

abstract interface class CheckpointApi {
  Future<RideCheckpointView> fetchCheckpoints(String rideId);

  Future<RideCheckpointView> checkIn({
    required String rideId,
    required String checkpointId,
  });

  Future<RideCheckpointView> release({
    required String rideId,
    required String checkpointId,
  });
}

class CheckpointApiException implements Exception {
  const CheckpointApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'CheckpointApiException($code): $message';
}
