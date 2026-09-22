import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_gateway.dart';
import '../models/route_planner.dart';
import 'route_planner_api.dart';

class HttpRoutePlannerApi implements RoutePlannerApi {
  HttpRoutePlannerApi({
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
  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    final Map<String, Object?> body = await _post(
      '/v1/maps/autocomplete',
      <String, Object?>{'input': input, 'sessionToken': sessionToken},
    );

    return _readList(
      body['suggestions'],
      PlaceSuggestion.fromJson,
      'place suggestions',
    );
  }

  @override
  Future<ResolvedPlace> resolvePlace({
    required String reference,
    required String sessionToken,
  }) async {
    final Map<String, Object?> body = await _post(
      '/v1/maps/resolve-place',
      <String, Object?>{'reference': reference, 'sessionToken': sessionToken},
    );
    final Object? raw = body['place'];
    if (raw is! Map<String, Object?>) {
      throw const RoutePlannerApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain a place.',
      );
    }
    return ResolvedPlace.fromJson(raw);
  }

  @override
  Future<List<RouteOption>> computeRoutes({
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required List<PlanningStop> stops,
    required RouteTravelMode travelMode,
    required bool computeAlternatives,
  }) async {
    final Map<String, Object?> body = await _post(
      '/v1/maps/routes',
      <String, Object?>{
        'origin': origin.location.toJson(),
        'destination': destination.location.toJson(),
        'intermediates': stops
            .map(
              (PlanningStop stop) => <String, Object?>{
                'location': stop.location.toJson(),
                'via': false,
              },
            )
            .toList(growable: false),
        'travelMode': travelMode.wireValue,
        'computeAlternatives': computeAlternatives,
        'modifiers': const <String, Object?>{
          'avoidTolls': false,
          'avoidHighways': false,
          'avoidFerries': false,
        },
      },
    );

    return _readList(body['routes'], RouteOption.fromJson, 'route options');
  }

  @override
  Future<List<AlongRoutePlace>> searchAlongRoute({
    required String textQuery,
    required RouteOption route,
    required RouteTravelMode travelMode,
  }) async {
    final Map<String, Object?> body = await _post(
      '/v1/maps/search-along-route',
      <String, Object?>{
        'textQuery': textQuery,
        'encodedPolyline': route.encodedPolyline,
        'travelMode': travelMode.wireValue,
        'maxResults': 8,
        'modifiers': const <String, Object?>{
          'avoidTolls': false,
          'avoidHighways': false,
          'avoidFerries': false,
        },
      },
    );

    return _readList(
      body['places'],
      AlongRoutePlace.fromJson,
      'along-route places',
    );
  }

  @override
  Future<List<TrafficIncident>> fetchTrafficIncidents(RouteOption route) async {
    final Map<String, Object?> body = await _post(
      '/v1/maps/traffic-incidents',
      <String, Object?>{
        'encodedPolyline': route.encodedPolyline,
        'maxResults': 50,
      },
    );

    return _readList(
      body['incidents'],
      TrafficIncident.fromJson,
      'traffic incidents',
    );
  }

  @override
  Future<SavedRoutePlan?> fetchRoutePlan(String rideId) async {
    final http.Response response = await _client.get(
      _endpoint('/v1/rides/${Uri.encodeComponent(rideId)}/route-plan'),
      headers: await _headers(),
    );
    final Map<String, Object?> body = _decodeObject(response);

    if (response.statusCode == 404) {
      final RoutePlannerApiException error = _exception(response, body);
      if (error.code == 'route_plan_not_found') {
        return null;
      }
      throw error;
    }

    _expectStatus(response, body, 200);

    final Object? raw = body['routePlan'];
    if (raw is! Map<String, Object?>) {
      throw const RoutePlannerApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain a RoutePlan.',
      );
    }
    return SavedRoutePlan.fromJson(raw);
  }

  @override
  Future<SavedRoutePlan> saveRoutePlan({
    required String rideId,
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required RouteOption route,
    required RouteTravelMode travelMode,
    required List<PlanningStop> stops,
  }) async {
    final http.Response response = await _client.put(
      _endpoint('/v1/rides/${Uri.encodeComponent(rideId)}/route-plan'),
      headers: await _headers(includeJson: true),
      body: jsonEncode(<String, Object?>{
        'travelMode': travelMode.wireValue,
        'origin': <String, Object?>{
          'label': origin.formattedAddress,
          'location': origin.location.toJson(),
        },
        'destination': <String, Object?>{
          'label': destination.formattedAddress,
          'location': destination.location.toJson(),
        },
        'distanceMeters': route.distanceMeters,
        'durationSeconds': route.durationSeconds,
        'encodedPolyline': route.encodedPolyline,
        'maneuvers': route.maneuvers
            .map((RouteManeuver maneuver) => maneuver.toJson())
            .toList(growable: false),
        'stops': stops
            .map((PlanningStop stop) => stop.toJson())
            .toList(growable: false),
      }),
    );

    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);

    final Object? raw = body['routePlan'];
    if (raw is! Map<String, Object?>) {
      throw const RoutePlannerApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain a RoutePlan.',
      );
    }
    final Object? broadcast = body['activeRideBroadcast'];
    if (broadcast != null && broadcast is! bool) {
      throw const RoutePlannerApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API returned invalid Active Ride broadcast status.',
      );
    }
    return SavedRoutePlan.fromJson(
      raw,
      activeRideBroadcast: broadcast as bool?,
    );
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final http.Response response = await _client.post(
      _endpoint(path),
      headers: await _headers(includeJson: true),
      body: jsonEncode(payload),
    );
    final Map<String, Object?> body = _decodeObject(response);
    _expectStatus(response, body, 200);
    return body;
  }

  List<T> _readList<T>(
    Object? raw,
    T Function(Map<String, Object?> json) parser,
    String label,
  ) {
    if (raw is! List<Object?>) {
      throw RoutePlannerApiException(
        statusCode: 500,
        code: 'invalid_response',
        message: 'CommRide API response does not contain $label.',
      );
    }

    return raw
        .map((Object? value) {
          if (value is! Map<String, Object?>) {
            throw RoutePlannerApiException(
              statusCode: 500,
              code: 'invalid_response',
              message: 'CommRide API returned invalid $label.',
            );
          }
          return parser(value);
        })
        .toList(growable: false);
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
      throw RoutePlannerApiException(
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

  RoutePlannerApiException _exception(
    http.Response response,
    Map<String, Object?> body,
  ) {
    final Object? rawError = body['error'];
    if (rawError is Map<String, Object?>) {
      final Object? code = rawError['code'];
      final Object? message = rawError['message'];
      if (code is String && message is String) {
        return RoutePlannerApiException(
          statusCode: response.statusCode,
          code: code,
          message: message,
        );
      }
    }

    return RoutePlannerApiException(
      statusCode: response.statusCode,
      code: 'request_failed',
      message: 'CommRide API request failed.',
    );
  }
}
