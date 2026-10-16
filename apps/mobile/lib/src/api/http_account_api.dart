import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import 'account_api.dart';

class HttpAccountApi implements AccountDeletionApi, ClubOwnershipApi {
  HttpAccountApi({
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
  Future<AccountDeletionPreview> previewDeletion() async {
    final http.Response response = await _client.get(
      _apiBaseUrl.resolve('/v1/me/deletion'),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
    return _preview(body) ??
        (throw const AccountApiException(
          statusCode: 500,
          code: 'invalid_response',
          message: 'Data hapus akun tidak valid.',
        ));
  }

  @override
  Future<void> deleteAccount() async {
    final http.Response response = await _client.delete(
      _apiBaseUrl.resolve('/v1/me'),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
  }

  @override
  Future<List<ClubMember>> listMembers(String clubId) async {
    final http.Response response = await _client.get(
      _apiBaseUrl.resolve('/v1/clubs/${Uri.encodeComponent(clubId)}/members'),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
    return _members(body);
  }

  @override
  Future<void> transferOwnership({
    required String clubId,
    required String riderId,
  }) async {
    final http.Response response = await _client.post(
      _apiBaseUrl.resolve('/v1/clubs/${Uri.encodeComponent(clubId)}/owner'),
      headers: <String, String>{
        ...await _headers(),
        'content-type': 'application/json',
      },
      body: jsonEncode(<String, String>{'riderId': riderId}),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
  }

  AccountDeletionPreview? _preview(Map<String, Object?> body) {
    final Object? raw = body['deletion'];
    return raw is Map<String, Object?>
        ? AccountDeletionPreview.fromJson(raw)
        : null;
  }

  List<ClubMember> _members(Map<String, Object?> body) {
    final Object? raw = body['members'];
    if (raw is! List<Object?>) {
      throw const AccountApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'Daftar anggota tidak tersedia.',
      );
    }
    return raw
        .whereType<Map<String, Object?>>()
        .map(ClubMember.fromJson)
        .toList(growable: false);
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
      throw AccountApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'Respons server tidak valid.',
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
        throw AccountApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
          preview: _preview(body),
        );
      }
    }
    throw AccountApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'Permintaan belum dapat diproses.',
    );
  }
}
