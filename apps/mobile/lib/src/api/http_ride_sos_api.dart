import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/ride_sos.dart';
import 'ride_sos_api.dart';

class HttpRideSosApi implements RideSosApi {
  HttpRideSosApi({
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
  Future<List<RideSos>> fetchSos(String rideId) async {
    final http.Response response = await _client.get(
      _endpoint('/v1/rides/${Uri.encodeComponent(rideId)}/sos'),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    if (response.statusCode != 200) {
      throw _exception(response, body);
    }

    final Object? rawSos = body['sos'];
    if (rawSos is! List<Object?>) {
      throw const RideSosApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain SOS history.',
      );
    }

    try {
      return List<RideSos>.unmodifiable(
        rawSos.map((Object? item) {
          if (item is! Map<String, Object?>) {
            throw const FormatException('Invalid SOS history item.');
          }
          return RideSos.fromJson(item);
        }),
      );
    } on FormatException catch (error) {
      throw RideSosApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: error.message,
      );
    }
  }

  @override
  Future<RideSos> raiseSos({
    required String rideId,
    required String clientCommandId,
    required String? reason,
  }) {
    return _post(
      '/v1/rides/${Uri.encodeComponent(rideId)}/sos',
      body: <String, Object?>{
        'clientCommandId': clientCommandId,
        'reason': reason,
      },
    );
  }

  @override
  Future<RideSos> cancelSos({required String rideId, required String sosId}) {
    return _post(
      '/v1/rides/${Uri.encodeComponent(rideId)}/sos/'
      '${Uri.encodeComponent(sosId)}/cancel',
    );
  }

  @override
  Future<RideSos> resolveSos({required String rideId, required String sosId}) {
    return _post(
      '/v1/rides/${Uri.encodeComponent(rideId)}/sos/'
      '${Uri.encodeComponent(sosId)}/resolve',
    );
  }

  Future<RideSos> _post(String path, {Map<String, Object?>? body}) async {
    final http.Response response = await _client.post(
      _endpoint(path),
      headers: await _headers(json: body != null),
      body: body == null ? null : jsonEncode(body),
    );
    final Map<String, Object?> decoded = _decodeObject(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _exception(response, decoded);
    }

    final Object? rawSos = decoded['sos'];
    if (rawSos is! Map<String, Object?>) {
      throw const RideSosApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain an SOS incident.',
      );
    }

    try {
      return RideSos.fromJson(rawSos);
    } on FormatException catch (error) {
      throw RideSosApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: error.message,
      );
    }
  }

  Uri _endpoint(String path) => _apiBaseUrl.resolve(path);

  Future<Map<String, String>> _headers({bool json = false}) async {
    final String token = await _authGateway.idToken();
    final Map<String, String> headers = <String, String>{
      'authorization': <String>['Bearer', token].join(' '),
    };
    if (json) {
      headers['content-type'] = 'application/json';
    }
    return headers;
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.body.isEmpty) {
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw RideSosApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'CommRide API returned an invalid response.',
      );
    }
    return decoded;
  }

  RideSosApiException _exception(
    http.Response response,
    Map<String, Object?> body,
  ) {
    final Object? rawError = body['error'];
    if (rawError is Map<String, Object?>) {
      final Object? code = rawError['code'];
      final Object? message = rawError['message'];
      if (code is String && message is String) {
        return RideSosApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
        );
      }
    }

    return RideSosApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'CommRide API request failed.',
    );
  }
}
