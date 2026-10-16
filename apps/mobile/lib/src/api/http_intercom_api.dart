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
    final Map<String, Object?> body = await _post(rideId, 'token');
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

  @override
  Future<void> muteRider({
    required String rideId,
    required String riderId,
  }) async {
    await _post(rideId, 'mute', <String, Object?>{'riderId': riderId});
  }

  Future<Map<String, Object?>> _post(
    String rideId,
    String action, [
    Map<String, Object?>? payload,
  ]) async {
    final String token = await _authGateway.idToken();
    final http.Response response = await _client.post(
      _apiBaseUrl.resolve(
        '/v1/rides/${Uri.encodeComponent(rideId)}/intercom/$action',
      ),
      headers: <String, String>{
        'authorization': <String>['Bearer', token].join(' '),
        if (payload != null) 'content-type': 'application/json',
      },
      body: payload == null ? null : jsonEncode(payload),
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

    if (response.statusCode == 200) {
      return body;
    }
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
}
