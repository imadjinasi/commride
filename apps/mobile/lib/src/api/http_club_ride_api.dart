import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/club_ride.dart';
import 'club_ride_api.dart';

class HttpClubRideApi implements ClubRideApi {
  HttpClubRideApi({
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
  Future<List<ClubListItem>> listClubs() async {
    final http.Response response = await _client.get(
      _endpoint('/v1/clubs'),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);

    final Object? rawItems = body['clubs'];
    if (rawItems is! List<Object?>) {
      throw const ClubRideApiException(
        statusCode: 500,
        message: 'CommRide API response does not contain a Club list.',
      );
    }

    return rawItems
        .map((Object? value) {
          if (value is! Map<String, Object?>) {
            throw const ClubRideApiException(
              statusCode: 500,
              message: 'CommRide API returned an invalid Club item.',
            );
          }
          return ClubListItem.fromJson(value);
        })
        .toList(growable: false);
  }

  @override
  Future<Club> createClub(ClubInput input) async {
    final http.Response response = await _post(
      '/v1/clubs',
      body: input.toJson(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 201);
    return _readClub(body);
  }

  @override
  Future<void> inviteClubMember({
    required String clubId,
    required String riderId,
    required ClubRole role,
  }) async {
    if (role == ClubRole.owner) {
      throw ArgumentError.value(role, 'role', 'Owner cannot be invited.');
    }

    final http.Response response = await _post(
      '/v1/clubs/${Uri.encodeComponent(clubId)}/members/invite',
      body: <String, Object?>{'riderId': riderId, 'role': role.name},
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
  }

  @override
  Future<void> joinClub(String clubId) async {
    final http.Response response = await _post(
      '/v1/clubs/${Uri.encodeComponent(clubId)}/join',
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
  }

  @override
  Future<List<RideListItem>> listRides(String clubId) async {
    final http.Response response = await _client.get(
      _endpoint('/v1/clubs/${Uri.encodeComponent(clubId)}/rides'),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);

    final Object? rawItems = body['rides'];
    if (rawItems is! List<Object?>) {
      throw const ClubRideApiException(
        statusCode: 500,
        message: 'CommRide API response does not contain a Ride list.',
      );
    }

    return rawItems
        .map((Object? value) {
          if (value is! Map<String, Object?>) {
            throw const ClubRideApiException(
              statusCode: 500,
              message: 'CommRide API returned an invalid Ride item.',
            );
          }
          return RideListItem.fromJson(value);
        })
        .toList(growable: false);
  }

  @override
  Future<Ride> createRide(String clubId, RideInput input) async {
    final http.Response response = await _post(
      '/v1/clubs/${Uri.encodeComponent(clubId)}/rides',
      body: input.toJson(),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 201);
    return _readRide(body);
  }

  @override
  Future<void> inviteRideMember({
    required String rideId,
    required String riderId,
    required RideRole role,
  }) async {
    if (role == RideRole.leader) {
      throw ArgumentError.value(role, 'role', 'Leader cannot be invited.');
    }

    final http.Response response = await _post(
      '/v1/rides/${Uri.encodeComponent(rideId)}/members/invite',
      body: <String, Object?>{'riderId': riderId, 'role': role.name},
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
  }

  @override
  Future<void> joinRide(String rideId) async {
    final http.Response response = await _post(
      '/v1/rides/${Uri.encodeComponent(rideId)}/join',
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
  }

  @override
  Future<Ride> publishRide(String rideId) {
    return _transition(rideId, 'publish');
  }

  @override
  Future<Ride> startRide(String rideId) {
    return _transition(rideId, 'start');
  }

  @override
  Future<Ride> endRide(String rideId) {
    return _transition(rideId, 'end');
  }

  @override
  Future<Ride> cancelRide(String rideId) {
    return _transition(rideId, 'cancel');
  }

  Future<Ride> _transition(String rideId, String action) async {
    final http.Response response = await _post(
      '/v1/rides/${Uri.encodeComponent(rideId)}/$action',
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
    return _readRide(body);
  }

  Future<http.Response> _post(String path, {Map<String, Object?>? body}) async {
    return _client.post(
      _endpoint(path),
      headers: await _headers(includeJson: body != null),
      body: body == null ? null : jsonEncode(body),
    );
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
      throw ClubRideApiException(
        statusCode: response.statusCode,
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

    final Object? error = body['error'];
    if (error is Map<String, Object?>) {
      final Object? code = error['code'];
      final Object? message = error['message'];
      if (message is String && message.isNotEmpty) {
        throw ClubRideApiException(
          statusCode: response.statusCode,
          message: message,
          code: code is String && code.isNotEmpty ? code : null,
        );
      }
    }

    throw ClubRideApiException(
      statusCode: response.statusCode,
      message: 'CommRide API request failed.',
    );
  }

  Club _readClub(Map<String, Object?> body) {
    final Object? rawClub = body['club'];
    if (rawClub is! Map<String, Object?>) {
      throw const ClubRideApiException(
        statusCode: 500,
        message: 'CommRide API response does not contain a Club.',
      );
    }
    return Club.fromJson(rawClub);
  }

  Ride _readRide(Map<String, Object?> body) {
    final Object? rawRide = body['ride'];
    if (rawRide is! Map<String, Object?>) {
      throw const ClubRideApiException(
        statusCode: 500,
        message: 'CommRide API response does not contain a Ride.',
      );
    }
    return Ride.fromJson(rawRide);
  }
}
