import '../models/vehicle_profile.dart';

abstract interface class VehicleApi {
  Future<List<VehicleProfile>> listVehicles();

  Future<VehicleProfile> createVehicle(VehicleProfileInput input);

  Future<VehicleProfile> updateVehicle(
    String vehicleId,
    VehicleProfileInput input,
  );

  Future<void> deleteVehicle(String vehicleId);
}

class VehicleApiException implements Exception {
  const VehicleApiException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'VehicleApiException($statusCode, $message)';
}
