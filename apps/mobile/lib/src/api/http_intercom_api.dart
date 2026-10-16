import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import 'intercom_api.dart';

class HttpIntercomApi implements IntercomApi {
  HttpIntercomApi({
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
  Future<IntercomJoinGrant> requestJoin(String rideId) async {
    final String token = await _authGateway.idToken();
    final http.Response response = await _client.post(
      _apiBaseUrl.resolve(
        '/v1/rides/${Uri.encodeComponent(rideId)}/intercom/token',
      ),
      headers: <String, String>{
        'authorization': <String>['Bearer', token].join(' '),
      },
    );

    Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final Map<String, Object?> body = decoded is Map<String, Object?>
        ? decoded
        : <String, Object?>{};

    if (response.statusCode != 200) {
      final Object? error = body['error'];
      if (error is Map<String, Object?> &&
          error['code'] is String &&
          error['message'] is String) {
        throw IntercomApiException(
          statusCode: response.statusCode,
          code: error['code']! as String,
          message: error['message']! as String,
        );
      }
      throw IntercomApiException(
        statusCode: response.statusCode,
        code: 'request_failed',
        message: 'CommRide API request failed.',
      );
    }

    final Object? grant = body['intercom'];
    try {
      if (grant is! Map<String, Object?>) {
        throw const FormatException('Missing intercom grant.');
      }
      return IntercomJoinGrant.fromJson(grant);
    } on FormatException catch (error) {
      throw IntercomApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: error.message,
      );
    }
  }
}
