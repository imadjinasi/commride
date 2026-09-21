import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/rider_profile.dart';
import 'rider_profile_api.dart';

class HttpRiderProfileApi implements RiderProfileApi {
  HttpRiderProfileApi({
    required Uri apiBaseUrl,
    required AuthGateway authGateway,
    http.Client? client,
  }) : _endpoint = apiBaseUrl.resolve('/v1/me'),
       _authGateway = authGateway,
       _client = client ?? http.Client();

  final Uri _endpoint;
  final AuthGateway _authGateway;
  final http.Client _client;

  @override
  Future<RiderProfile?> fetchProfile() async {
    final http.Response response = await _client.get(
      _endpoint,
      headers: await _headers(),
    );

    if (response.statusCode == 404) {
      return null;
    }

    final Map<String, Object?> body = _decodeObject(response);
    if (response.statusCode != 200) {
      throw _exception(response.statusCode, body);
    }

    return _readProfile(body);
  }

  @override
  Future<RiderProfile> saveProfile(RiderProfileInput input) async {
    final http.Response response = await _client.put(
      _endpoint,
      headers: await _headers(includeJson: true),
      body: jsonEncode(input.toJson()),
    );

    final Map<String, Object?> body = _decodeObject(response);
    if (response.statusCode != 200) {
      throw _exception(response.statusCode, body);
    }

    return _readProfile(body);
  }

  Future<Map<String, String>> _headers({bool includeJson = false}) async {
    final String token = await _authGateway.idToken();

    return <String, String>{
      'authorization': 'Bearer $token',
      if (includeJson) 'content-type': 'application/json',
    };
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw RiderProfileApiException(
        statusCode: response.statusCode,
        message: 'CommRide API returned an invalid response.',
      );
    }

    return decoded;
  }

  RiderProfile _readProfile(Map<String, Object?> body) {
    final Object? rider = body['rider'];
    if (rider is! Map<String, Object?>) {
      throw const RiderProfileApiException(
        statusCode: 500,
        message: 'CommRide API response does not contain a Rider profile.',
      );
    }

    return RiderProfile.fromJson(rider);
  }

  RiderProfileApiException _exception(
    int statusCode,
    Map<String, Object?> body,
  ) {
    final Object? error = body['error'];
    if (error is Map<String, Object?>) {
      final Object? message = error['message'];
      if (message is String && message.isNotEmpty) {
        return RiderProfileApiException(
          statusCode: statusCode,
          message: message,
        );
      }
    }

    return RiderProfileApiException(
      statusCode: statusCode,
      message: 'CommRide API request failed.',
    );
  }
}
