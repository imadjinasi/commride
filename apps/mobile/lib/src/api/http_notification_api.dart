import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/rider_notification.dart';
import 'notification_api.dart';

class HttpNotificationApi implements NotificationApi {
  HttpNotificationApi({
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
  Future<List<RiderNotification>> listNotifications({
    RiderNotificationScope? scope,
    String? clubId,
    int limit = 50,
  }) async {
    final Uri endpoint = _apiBaseUrl
        .resolve('/v1/me/notifications')
        .replace(
          queryParameters: <String, String>{
            if (scope != null) 'scope': scope.name,
            if (clubId != null && clubId.trim().isNotEmpty)
              'clubId': clubId.trim(),
            'limit': limit.toString(),
          },
        );
    final http.Response response = await _client.get(
      endpoint,
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);

    final Object? raw = body['notifications'];
    if (raw is! List<Object?>) {
      throw const NotificationApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'Daftar notifikasi tidak tersedia.',
      );
    }

    return raw
        .map((Object? item) {
          if (item is! Map<String, Object?>) {
            throw const NotificationApiException(
              statusCode: 500,
              code: 'invalid_response',
              message: 'Data notifikasi tidak valid.',
            );
          }
          return RiderNotification.fromJson(item);
        })
        .toList(growable: false);
  }

  @override
  Future<void> markRead(String notificationId) async {
    final http.Response response = await _client.post(
      _apiBaseUrl.resolve(
        '/v1/me/notifications/' + Uri.encodeComponent(notificationId) + '/read',
      ),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
  }

  Future<Map<String, String>> _headers() async {
    final String token = await _authGateway.idToken();
    return <String, String>{'authorization': 'Bearer $token'};
  }

  Map<String, Object?> _decodeObject(http.Response response) {
    if (response.body.isEmpty) {
      return <String, Object?>{};
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) {
      throw NotificationApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'Respons notifikasi tidak valid.',
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
    final Object? rawError = body['error'];
    if (rawError is Map<String, Object?>) {
      final Object? code = rawError['code'];
      final Object? message = rawError['message'];
      if (code is String && message is String) {
        throw NotificationApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
        );
      }
    }
    throw NotificationApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'Notifikasi belum dapat dimuat.',
    );
  }
}
