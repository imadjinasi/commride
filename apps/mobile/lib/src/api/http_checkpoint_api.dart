import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/ride_checkpoint.dart';
import 'checkpoint_api.dart';

class HttpCheckpointApi implements CheckpointApi {
  HttpCheckpointApi({
    required Uri apiBaseUrl,
    required AuthGateway authGateway,
    http.Client? client,
  }) : _apiBaseUrl = apiBaseUrl,
       _authGateway = authGateway,
       _client = client ?? http.Client();

  final Uri _apiBaseUrl;
  final AuthGateway _authGateway;
  final http.Client _client;

  @override
  Future<RideCheckpointView> fetchCheckpoints(String rideId) async {
    final http.Response response = await _client.get(
      _endpoint('/v1/rides/${Uri.encodeComponent(rideId)}/checkpoints'),
      headers: await _headers(),
    );
    return _readView(response);
  }

  @override
  Future<RideCheckpointView> checkIn({
    required String rideId,
    required String checkpointId,
  }) async {
    final http.Response response = await _client.post(
      _endpoint(
        '/v1/rides/${Uri.encodeComponent(rideId)}/checkpoints/'
        '${Uri.encodeComponent(checkpointId)}/check-in',
      ),
      headers: await _headers(),
    );
    return _readView(response);
  }

  @override
  Future<RideCheckpointView> release({
    required String rideId,
    required String checkpointId,
  }) async {
    final http.Response response = await _client.post(
      _endpoint(
        '/v1/rides/${Uri.encodeComponent(rideId)}/checkpoints/'
        '${Uri.encodeComponent(checkpointId)}/release',
      ),
      headers: await _headers(),
    );
    return _readView(response);
  }

  RideCheckpointView _readView(http.Response response) {
    final Map<String, Object?> body = _decodeObject(response);
    if (response.statusCode != 200) {
      throw _exception(response, body);
    }

    final Object? raw = body['checkpointView'];
    if (raw is! Map<String, Object?>) {
      throw const CheckpointApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain Checkpoint state.',
      );
    }

    try {
      return RideCheckpointView.fromJson(raw);
    } on FormatException catch (error) {
      throw CheckpointApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: error.message,
      );
    }
  }

  Uri _endpoint(String path) => _apiBaseUrl.resolve(path);

  Future<Map<String, String>> _headers() async {
    final String token = await _authGateway.idToken();
    return <String, String>{
      'authorization': <String>['Bearer', token].join(' '),
    };
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.body.isEmpty) {
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw CheckpointApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'CommRide API returned an invalid response.',
      );
    }
    return decoded;
  }

  CheckpointApiException _exception(
    http.Response response,
    Map<String, Object?> body,
  ) {
    final Object? rawError = body['error'];
    if (rawError is Map<String, Object?>) {
      final Object? code = rawError['code'];
      final Object? message = rawError['message'];
      if (code is String && message is String) {
        return CheckpointApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
        );
      }
    }

    return CheckpointApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'CommRide API request failed.',
    );
  }
}
