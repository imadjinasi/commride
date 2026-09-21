import '../models/route_planner.dart';

abstract interface class RoutePlannerApi {
  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  });

  Future<ResolvedPlace> resolvePlace({
    required String reference,
    required String sessionToken,
  });

  Future<List<RouteOption>> computeRoutes({
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required List<PlanningStop> stops,
    required RouteTravelMode travelMode,
    required bool computeAlternatives,
  });

  Future<List<AlongRoutePlace>> searchAlongRoute({
    required String textQuery,
    required RouteOption route,
    required RouteTravelMode travelMode,
  });

  Future<SavedRoutePlan?> fetchRoutePlan(String rideId);

  Future<SavedRoutePlan> saveRoutePlan({
    required String rideId,
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required RouteOption route,
    required RouteTravelMode travelMode,
    required List<PlanningStop> stops,
  });
}

class RoutePlannerApiException implements Exception {
  const RoutePlannerApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() {
    return 'RoutePlannerApiException($statusCode, $code, $message)';
  }
}
