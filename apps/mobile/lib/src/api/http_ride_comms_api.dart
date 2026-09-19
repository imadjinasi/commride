import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/ride_message.dart';
import 'ride_comms_api.dart';

class HttpRideCommsApi implements RideCommsApi {
  HttpRideCommsApi({
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
  Future<RideMessagePage> fetchMessages(
    String rideId, {
    String? cursor,
    int limit = 50,
  }) async {
    final Map<String, String> queryParameters = <String, String>{
      'limit': '$limit',
    };
    if (cursor != null) {
      queryParameters['cursor'] = cursor;
    }

    final Uri endpoint = _endpoint(
      '/v1/rides/${Uri.encodeComponent(rideId)}/messages',
    ).replace(queryParameters: queryParameters);

    final http.Response response = await _client.get(
      endpoint,
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    if (response.statusCode != 200) {
      throw _exception(response, body);
    }

    try {
      return RideMessagePage.fromJson(body);
    } on FormatException catch (error) {
      throw RideCommsApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: error.message,
      );
    }
  }

  @override
  Future<RideMessage> sendChat({
    required String rideId,
    required String clientMessageId,
    required String body,
  }) {
    return _send(
      path: '/v1/rides/${Uri.encodeComponent(rideId)}/messages',
      clientMessageId: clientMessageId,
      body: body,
    );
  }

  @override
  Future<RideMessage> sendAnnouncement({
    required String rideId,
    required String clientMessageId,
    required String body,
  }) {
    return _send(
      path: '/v1/rides/${Uri.encodeComponent(rideId)}/announcements',
      clientMessageId: clientMessageId,
      body: body,
    );
  }

  Future<RideMessage> _send({
    required String path,
    required String clientMessageId,
    required String body,
  }) async {
    final http.Response response = await _client.post(
      _endpoint(path),
      headers: await _headers(json: true),
      body: jsonEncode(<String, Object?>{
        'clientMessageId': clientMessageId,
        'body': body,
      }),
    );
    final Map<String, Object?> decoded = _decodeObject(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw _exception(response, decoded);
    }

    final Object? rawMessage = decoded['message'];
    if (rawMessage is! Map<String, Object?>) {
      throw const RideCommsApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain a Ride message.',
      );
    }

    try {
      return RideMessage.fromJson(rawMessage);
    } on FormatException catch (error) {
      throw RideCommsApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: error.message,
      );
    }
  }

  Uri _endpoint(String path) => _apiBaseUrl.resolve(path);

  Future<Map<String, String>> _headers({bool json = false}) async {
    final String token = await _authGateway.idToken();
    return <String, String>{
      'authorization': <String>['Bearer', token].join(' '),
      if (json) 'content-type': 'application/json',
    };
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.body.isEmpty) {
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw RideCommsApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'CommRide API returned an invalid response.',
      );
    }
    return decoded;
  }

  RideCommsApiException _exception(
    http.Response response,
    Map<String, Object?> body,
  ) {
    final Object? rawError = body['error'];
    if (rawError is Map<String, Object?>) {
      final Object? code = rawError['code'];
      final Object? message = rawError['message'];
      if (code is String && message is String) {
        return RideCommsApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
        );
      }
    }

    return RideCommsApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'CommRide API request failed.',
    );
  }
}
