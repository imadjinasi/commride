import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/ride_briefing.dart';
import 'ride_briefing_api.dart';

class HttpRideBriefingApi implements RideBriefingApi {
  HttpRideBriefingApi({
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
  Future<RideBriefingView?> fetchBriefing(String rideId) async {
    final http.Response response = await _client.get(
      _endpoint('/v1/rides/${Uri.encodeComponent(rideId)}/briefing'),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);

    if (response.statusCode == 404) {
      final RideBriefingApiException error = _exception(response, body);
      if (error.code == 'briefing_not_found') {
        return null;
      }
      throw error;
    }

    _expectStatus(response, body, 200);
    return _readView(body);
  }

  @override
  Future<RideBriefingView> publishBriefing({
    required String rideId,
    required String? notes,
  }) async {
    final http.Response response = await _client.post(
      _endpoint('/v1/rides/${Uri.encodeComponent(rideId)}/briefing/publish'),
      headers: await _headers(includeJson: true),
      body: jsonEncode(<String, Object?>{'notes': notes}),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
    return _readView(body);
  }

  @override
  Future<RideBriefingView> acknowledgeBriefing(String rideId) async {
    final http.Response response = await _client.post(
      _endpoint(
        '/v1/rides/${Uri.encodeComponent(rideId)}/briefing/acknowledge',
      ),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
    return _readView(body);
  }

  RideBriefingView _readView(Map<String, Object?> body) {
    final Object? raw = body['briefingView'];
    if (raw is! Map<String, Object?>) {
      throw const RideBriefingApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain a Briefing.',
      );
    }
    return RideBriefingView.fromJson(raw);
  }

  Uri _endpoint(String path) => _apiBaseUrl.resolve(path);

  Future<Map<String, String>> _headers({bool includeJson = false}) async {
    final String token = await _authGateway.idToken();
    return <String, String>{
      'authorization': 'Bearer $token',
      if (includeJson) 'content-type': 'application/json',
    };
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.body.isEmpty) {
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw RideBriefingApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'CommRide API returned an invalid response.',
      );
    }
    return decoded;
  }

  void _expectStatus(
    http.Response response,
    Map<String, Object?> body,
    int expected,
  ) {
    if (response.statusCode == expected) {
      return;
    }
    throw _exception(response, body);
  }

  RideBriefingApiException _exception(
    http.Response response,
    Map<String, Object?> body,
  ) {
    final Object? rawError = body['error'];
    if (rawError is Map<String, Object?>) {
      final Object? code = rawError['code'];
      final Object? message = rawError['message'];
      if (code is String && message is String) {
        return RideBriefingApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
        );
      }
    }

    return RideBriefingApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'CommRide API request failed.',
    );
  }
}
