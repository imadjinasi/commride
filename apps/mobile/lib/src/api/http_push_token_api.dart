import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import 'push_token_api.dart';

class HttpPushTokenApi implements PushTokenApi {
  HttpPushTokenApi({
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
  Future<void> registerToken({
    required String token,
    required RidePushPlatform platform,
  }) {
    return _write(
      'POST',
      token: token,
      platform: platform,
    );
  }

  @override
  Future<void> unregisterToken({
    required String token,
    required RidePushPlatform platform,
  }) {
    return _write(
      'DELETE',
      token: token,
      platform: platform,
    );
  }

  Future<void> _write(
    String method, {
    required String token,
    required RidePushPlatform platform,
  }) async {
    final String authToken = await _authGateway.idToken();
    final http.Request request = http.Request(
      method,
      _apiBaseUrl.resolve('/v1/me/push-tokens'),
    )
      ..headers.addAll(<String, String>{
        'authorization': 'Bearer $authToken',
        'content-type': 'application/json',
      })
      ..body = jsonEncode(<String, Object?>{
        'token': token,
        'platform': platform.wireValue,
      });

    final http.StreamedResponse streamed = await _client.send(request);
    final http.Response response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw _exception(response);
    }
  }

  PushTokenApiException _exception(http.Response response) {
    if (response.body.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(response.body);
        if (decoded is Map<String, Object?>) {
          final Object? rawError = decoded['error'];
          if (rawError is Map<String, Object?>) {
            final Object? code = rawError['code'];
            final Object? message = rawError['message'];
            if (code is String && message is String) {
              return PushTokenApiException(
                statusCode: response.statusCode,
                code: code,
                message: message,
              );
            }
          }
        }
      } catch (_) {
        // Fall through to a stable transport error.
      }
    }

    return PushTokenApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'Pengaturan notifikasi belum dapat disimpan.',
    );
  }
}
