import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/vehicle_profile.dart';
import 'vehicle_api.dart';

class HttpVehicleApi implements VehicleApi {
  HttpVehicleApi({
    required Uri apiBaseUrl,
    required AuthGateway authGateway,
    http.Client? client,
  }) : _collectionEndpoint = apiBaseUrl.resolve('/v1/me/vehicles'),
       _authGateway = authGateway,
       _client = client ?? http.Client();

  final Uri _collectionEndpoint;
  final AuthGateway _authGateway;
  final http.Client _client;

  @override
  Future<List<VehicleProfile>> listVehicles() async {
    final http.Response response = await _client.get(
      _collectionEndpoint,
      headers: await _headers(),
    );

    final Map<String, Object?> body = _decodeObject(response);
    if (response.statusCode != 200) {
      throw _exception(response.statusCode, body);
    }

    final Object? rawVehicles = body['vehicles'];
    if (rawVehicles is! List<Object?>) {
      throw const VehicleApiException(
        statusCode: 500,
        message: 'CommRide API response does not contain a Vehicle list.',
      );
    }

    return rawVehicles
        .map((Object? value) {
          if (value is! Map<String, Object?>) {
            throw const VehicleApiException(
              statusCode: 500,
              message: 'CommRide API returned an invalid Vehicle.',
            );
          }
          return VehicleProfile.fromJson(value);
        })
        .toList(growable: false);
  }

  @override
  Future<VehicleProfile> createVehicle(VehicleProfileInput input) async {
    final http.Response response = await _client.post(
      _collectionEndpoint,
      headers: await _headers(includeJson: true),
      body: jsonEncode(input.toJson()),
    );

    return _readVehicleResponse(response, expectedStatus: 201);
  }

  @override
  Future<VehicleProfile> updateVehicle(
    String vehicleId,
    VehicleProfileInput input,
  ) async {
    final http.Response response = await _client.put(
      _vehicleEndpoint(vehicleId),
      headers: await _headers(includeJson: true),
      body: jsonEncode(input.toJson()),
    );

    return _readVehicleResponse(response, expectedStatus: 200);
  }

  @override
  Future<void> deleteVehicle(String vehicleId) async {
    final http.Response response = await _client.delete(
      _vehicleEndpoint(vehicleId),
      headers: await _headers(),
    );

    if (response.statusCode == 204) {
      return;
    }

    final Map<String, Object?> body = _decodeObject(response);
    throw _exception(response.statusCode, body);
  }

  Uri _vehicleEndpoint(String vehicleId) {
    return _collectionEndpoint.resolve(
      '/v1/me/vehicles/${Uri.encodeComponent(vehicleId)}',
    );
  }

  Future<Map<String, String>> _headers({bool includeJson = false}) async {
    final String token = await _authGateway.idToken();

    return <String, String>{
      'authorization': 'Bearer $token',
      if (includeJson) 'content-type': 'application/json',
    };
  }

  VehicleProfile _readVehicleResponse(
    http.Response response, {
    required int expectedStatus,
  }) {
    final Map<String, Object?> body = _decodeObject(response);
    if (response.statusCode != expectedStatus) {
      throw _exception(response.statusCode, body);
    }

    final Object? vehicle = body['vehicle'];
    if (vehicle is! Map<String, Object?>) {
      throw const VehicleApiException(
        statusCode: 500,
        message: 'CommRide API response does not contain a Vehicle.',
      );
    }

    return VehicleProfile.fromJson(vehicle);
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.body.isEmpty) {
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw VehicleApiException(
        statusCode: response.statusCode,
        message: 'CommRide API returned an invalid response.',
      );
    }

    return decoded;
  }

  VehicleApiException _exception(int statusCode, Map<String, Object?> body) {
    final Object? error = body['error'];
    if (error is Map<String, Object?>) {
      final Object? message = error['message'];
      if (message is String && message.isNotEmpty) {
        return VehicleApiException(statusCode: statusCode, message: message);
      }
    }

    return VehicleApiException(
      statusCode: statusCode,
      message: 'CommRide API request failed.',
    );
  }
}
