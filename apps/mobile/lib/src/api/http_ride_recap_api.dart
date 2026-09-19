import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/ride_recap.dart';
import 'ride_recap_api.dart';

class HttpRideRecapApi implements RideRecapApi {
  HttpRideRecapApi({
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
  Future<RideRecap> fetchRecap(String rideId) async {
    final http.Response response = await _client.get(
      _apiBaseUrl.resolve(
        '/v1/rides/${Uri.encodeComponent(rideId)}/recap',
      ),
      headers: <String, String>{
        'authorization': 'Bearer ${await _authGateway.idToken()}',
      },
    );

    final Map<String, Object?> body = _decode(response);
    if (response.statusCode != 200) {
      throw _exception(response, body);
    }

    final Object? rawRecap = body['recap'];
    if (rawRecap is! Map<String, Object?>) {
      throw const RideRecapApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain a Ride Recap.',
      );
    }

    try {
      return RideRecap.fromJson(rawRecap);
    } on FormatException catch (error) {
      throw RideRecapApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: error.message,
      );
    }
  }

  Map<String, Object?> _decode(http.Response response) {
    if (response.body.isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw RideRecapApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'CommRide API returned an invalid response.',
      );
    }
    return decoded;
  }

  RideRecapApiException _exception(
    http.Response response,
    Map<String, Object?> body,
  ) {
    final Object? rawError = body['error'];
    if (rawError is Map<String, Object?>) {
      final Object? code = rawError['code'];
      final Object? message = rawError['message'];
      if (code is String && message is String) {
        return RideRecapApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
        );
      }
    }
    return RideRecapApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'Ride Recap belum dapat dimuat.',
    );
  }
}
