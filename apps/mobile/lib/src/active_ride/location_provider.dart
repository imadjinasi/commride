enum RideLocationPermission { unknown, denied, deniedPermanently, granted }

enum RideMovementState { moving, stopped, unknown }

class RideLocationSample {
  const RideLocationSample({
    required this.latitude,
    required this.longitude,
    required this.observedAt,
    required this.movement,
  });

  final double latitude;
  final double longitude;
  final DateTime observedAt;
  final RideMovementState movement;
}

abstract interface class RideLocationProvider {
  Stream<RideLocationSample> get samples;

  Future<RideLocationPermission> checkPermission();

  Future<RideLocationPermission> requestPermission();

  Future<void> start();

  Future<void> stop();
}
