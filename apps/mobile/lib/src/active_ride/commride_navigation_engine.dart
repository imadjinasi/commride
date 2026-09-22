import 'dart:math' as math;

import '../models/route_planner.dart';

enum CommRideNavigationPhase {
  onRoute,
  suspectedOffRoute,
  confirmedOffRoute,
  recovery,
  rejoined,
}

class CommRideNavigationSnapshot {
  const CommRideNavigationSnapshot({
    required this.phase,
    required this.position,
    required this.distanceFromRouteMeters,
    required this.routeProgressMeters,
    required this.routeProgressShapeIndex,
    required this.nextManeuver,
    required this.distanceToNextManeuverMeters,
    required this.rejoinTarget,
    required this.distanceToRejoinMeters,
    required this.shouldOfferReroute,
    required this.routeBearingDegrees,
  });

  final CommRideNavigationPhase phase;
  final GeoPoint position;
  final double distanceFromRouteMeters;
  final double routeProgressMeters;
  final int routeProgressShapeIndex;
  final RouteManeuver? nextManeuver;
  final double? distanceToNextManeuverMeters;
  final GeoPoint? rejoinTarget;
  final double? distanceToRejoinMeters;
  final bool shouldOfferReroute;
  final double routeBearingDegrees;

  bool get isRecovering =>
      phase == CommRideNavigationPhase.confirmedOffRoute ||
      phase == CommRideNavigationPhase.recovery;
}

class CommRideNavigationEngine {
  CommRideNavigationEngine(
    SavedRoutePlan plan, {
    this.suspectDistanceMeters = 35,
    this.confirmDistanceMeters = 65,
    this.rejoinDistanceMeters = 30,
    this.confirmDuration = const Duration(seconds: 8),
    this.rejoinStableDuration = const Duration(seconds: 5),
    this.rerouteOfferDuration = const Duration(seconds: 20),
    this.rerouteOfferDistanceMeters = 150,
  }) {
    replacePlan(plan);
  }

  final double suspectDistanceMeters;
  final double confirmDistanceMeters;
  final double rejoinDistanceMeters;
  final Duration confirmDuration;
  final Duration rejoinStableDuration;
  final Duration rerouteOfferDuration;
  final double rerouteOfferDistanceMeters;

  late SavedRoutePlan _plan;
  late List<GeoPoint> _route;
  late List<double> _cumulativeMeters;

  CommRideNavigationPhase _phase = CommRideNavigationPhase.onRoute;
  DateTime? _suspectedAt;
  DateTime? _confirmedAt;
  DateTime? _rejoinedAt;
  double _furthestProgressMeters = 0;
  int _furthestShapeIndex = 0;

  SavedRoutePlan get plan => _plan;
  List<GeoPoint> get routePoints => List<GeoPoint>.unmodifiable(_route);

  int closestShapeIndex(GeoPoint point) {
    _RouteProjection? best;
    for (int index = 0; index < _route.length - 1; index++) {
      final _RouteProjection candidate = _projectToSegment(
        point,
        _route[index],
        _route[index + 1],
        index,
      );
      if (best == null || candidate.distanceMeters < best.distanceMeters) {
        best = candidate;
      }
    }
    return best?.segmentIndex ?? 0;
  }

  void replacePlan(SavedRoutePlan plan) {
    final List<GeoPoint> points = decodeRoutePolyline(
      plan.route.encodedPolyline,
    );
    if (points.length < 2) {
      throw const FormatException('RoutePlan polyline is invalid.');
    }

    _plan = plan;
    _route = points;
    _cumulativeMeters = <double>[0];
    for (int index = 1; index < _route.length; index++) {
      _cumulativeMeters.add(
        _cumulativeMeters[index - 1] +
            geoDistanceMeters(_route[index - 1], _route[index]),
      );
    }

    _phase = CommRideNavigationPhase.onRoute;
    _suspectedAt = null;
    _confirmedAt = null;
    _rejoinedAt = null;
    _furthestProgressMeters = 0;
    _furthestShapeIndex = 0;
  }

  CommRideNavigationSnapshot update(GeoPoint position, DateTime observedAt) {
    final _RouteProjection projection = _nearestProjection(position);
    final double distance = projection.distanceMeters;

    if (distance <= rejoinDistanceMeters) {
      if (_phase == CommRideNavigationPhase.suspectedOffRoute ||
          _phase == CommRideNavigationPhase.confirmedOffRoute ||
          _phase == CommRideNavigationPhase.recovery ||
          _phase == CommRideNavigationPhase.rejoined) {
        _rejoinedAt ??= observedAt;
        if (observedAt.difference(_rejoinedAt!) >= rejoinStableDuration) {
          _phase = CommRideNavigationPhase.onRoute;
          _suspectedAt = null;
          _confirmedAt = null;
          _rejoinedAt = null;
        } else {
          _phase = CommRideNavigationPhase.rejoined;
        }
      } else {
        _phase = CommRideNavigationPhase.onRoute;
      }
    } else if (distance >= confirmDistanceMeters) {
      _rejoinedAt = null;
      _suspectedAt ??= observedAt;
      if (observedAt.difference(_suspectedAt!) >= confirmDuration) {
        if (_confirmedAt == null) {
          _confirmedAt = observedAt;
          _phase = CommRideNavigationPhase.confirmedOffRoute;
        } else {
          _phase = CommRideNavigationPhase.recovery;
        }
      } else {
        _phase = CommRideNavigationPhase.suspectedOffRoute;
      }
    } else if (distance >= suspectDistanceMeters) {
      _rejoinedAt = null;
      _suspectedAt ??= observedAt;
      _phase = CommRideNavigationPhase.suspectedOffRoute;
    } else {
      _phase = CommRideNavigationPhase.onRoute;
      _suspectedAt = null;
      _confirmedAt = null;
      _rejoinedAt = null;
    }

    if (distance < confirmDistanceMeters * 1.5) {
      _furthestProgressMeters = math.max(
        _furthestProgressMeters,
        projection.progressMeters,
      );
      _furthestShapeIndex = math.max(
        _furthestShapeIndex,
        projection.segmentIndex,
      );
    }

    final double navigationProgress = math.max(
      _furthestProgressMeters,
      projection.progressMeters,
    );
    final int navigationShapeIndex = math.max(
      _furthestShapeIndex,
      projection.segmentIndex,
    );

    final RouteManeuver? maneuver = _nextManeuver(
      navigationShapeIndex,
      navigationProgress,
    );
    final double? maneuverDistance = maneuver == null
        ? null
        : math.max(
            0,
            _distanceAtShapeIndex(maneuver.beginShapeIndex) -
                navigationProgress,
          );

    final bool recovering =
        _phase == CommRideNavigationPhase.confirmedOffRoute ||
        _phase == CommRideNavigationPhase.recovery;
    final GeoPoint? rejoinTarget = recovering
        ? _futureRejoinTarget(
            math.max(navigationProgress, projection.progressMeters),
            distance,
          )
        : null;

    final bool shouldOfferReroute =
        _confirmedAt != null &&
        (distance >= rerouteOfferDistanceMeters ||
            observedAt.difference(_confirmedAt!) >= rerouteOfferDuration);

    return CommRideNavigationSnapshot(
      phase: _phase,
      position: position,
      distanceFromRouteMeters: distance,
      routeProgressMeters: navigationProgress,
      routeProgressShapeIndex: navigationShapeIndex,
      nextManeuver: maneuver,
      distanceToNextManeuverMeters: maneuverDistance,
      rejoinTarget: rejoinTarget,
      distanceToRejoinMeters: rejoinTarget == null
          ? null
          : geoDistanceMeters(position, rejoinTarget),
      shouldOfferReroute: shouldOfferReroute,
      routeBearingDegrees: projection.bearingDegrees,
    );
  }

  RouteManeuver? _nextManeuver(int shapeIndex, double progressMeters) {
    for (final RouteManeuver maneuver in _plan.route.maneuvers) {
      if (maneuver.endShapeIndex < shapeIndex) continue;
      if (_distanceAtShapeIndex(maneuver.endShapeIndex) + 15 < progressMeters) {
        continue;
      }
      return maneuver;
    }
    return null;
  }

  GeoPoint _futureRejoinTarget(double progressMeters, double deviationMeters) {
    final double ahead = math.max(400, math.min(1500, deviationMeters * 3));
    final double target = math.min(
      _cumulativeMeters.last,
      progressMeters + ahead,
    );

    for (int index = 0; index < _cumulativeMeters.length; index++) {
      if (_cumulativeMeters[index] >= target) {
        return _route[index];
      }
    }
    return _route.last;
  }

  double _distanceAtShapeIndex(int index) {
    if (index <= 0) return 0;
    if (index >= _cumulativeMeters.length) return _cumulativeMeters.last;
    return _cumulativeMeters[index];
  }

  _RouteProjection _nearestProjection(GeoPoint point) {
    _RouteProjection? best;

    for (int index = 0; index < _route.length - 1; index++) {
      // Once navigation has made meaningful progress, strongly prefer current
      // or future route segments. This avoids snapping backwards at loops.
      if (_cumulativeMeters[index + 1] < _furthestProgressMeters - 250) {
        continue;
      }

      final _RouteProjection candidate = _projectToSegment(
        point,
        _route[index],
        _route[index + 1],
        index,
      );
      if (best == null || candidate.distanceMeters < best.distanceMeters) {
        best = candidate;
      }
    }

    if (best != null) return best;

    // Fallback is only reachable near the end after all earlier segments were
    // excluded by the progress guard.
    return _projectToSegment(
      point,
      _route[_route.length - 2],
      _route.last,
      _route.length - 2,
    );
  }

  _RouteProjection _projectToSegment(
    GeoPoint point,
    GeoPoint start,
    GeoPoint end,
    int segmentIndex,
  ) {
    const double earthRadius = 6371000;
    final double referenceLatitude = point.latitude * math.pi / 180;
    final double xScale =
        earthRadius * math.pi / 180 * math.cos(referenceLatitude);
    const double yScale = earthRadius * math.pi / 180;

    final double ax =
        _wrappedLongitudeDelta(start.longitude - point.longitude) * xScale;
    final double ay = (start.latitude - point.latitude) * yScale;
    final double bx =
        ax + _wrappedLongitudeDelta(end.longitude - start.longitude) * xScale;
    final double by = (end.latitude - point.latitude) * yScale;
    final double dx = bx - ax;
    final double dy = by - ay;
    final double squared = dx * dx + dy * dy;
    final double t = squared == 0
        ? 0
        : (-((ax * dx) + (ay * dy)) / squared).clamp(0.0, 1.0).toDouble();

    final double projectedX = ax + t * dx;
    final double projectedY = ay + t * dy;
    final double segmentLength = geoDistanceMeters(start, end);
    final double progress = _cumulativeMeters[segmentIndex] + segmentLength * t;

    return _RouteProjection(
      segmentIndex: segmentIndex,
      distanceMeters: math.sqrt(
        projectedX * projectedX + projectedY * projectedY,
      ),
      progressMeters: progress,
      bearingDegrees: geoBearingDegrees(start, end),
    );
  }
}

class _RouteProjection {
  const _RouteProjection({
    required this.segmentIndex,
    required this.distanceMeters,
    required this.progressMeters,
    required this.bearingDegrees,
  });

  final int segmentIndex;
  final double distanceMeters;
  final double progressMeters;
  final double bearingDegrees;
}

List<GeoPoint> decodeRoutePolyline(String encoded) {
  if (encoded.isEmpty || encoded.length > 200000) return <GeoPoint>[];

  final List<GeoPoint> points = <GeoPoint>[];
  int index = 0;
  int latitude = 0;
  int longitude = 0;

  int readSigned() {
    int result = 0;
    int shift = 0;
    while (index < encoded.length && shift <= 30) {
      final int value = encoded.codeUnitAt(index++) - 63;
      if (value < 0 || value > 63) {
        throw const FormatException('Invalid route polyline.');
      }
      result |= (value & 0x1f) << shift;
      if (value < 0x20) {
        return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      }
      shift += 5;
    }
    throw const FormatException('Invalid route polyline.');
  }

  try {
    while (index < encoded.length) {
      latitude += readSigned();
      longitude += readSigned();
      final double lat = latitude / 1e5;
      final double lon = longitude / 1e5;
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        return <GeoPoint>[];
      }
      points.add(GeoPoint(latitude: lat, longitude: lon));
    }
  } on FormatException {
    return <GeoPoint>[];
  }

  return points;
}

bool shouldRefreshRecoveryRoute({
  required GeoPoint origin,
  required GeoPoint target,
  required DateTime observedAt,
  required GeoPoint? lastOrigin,
  required GeoPoint? lastTarget,
  required DateTime? lastRequestedAt,
  Duration minimumInterval = const Duration(seconds: 30),
  double minimumOriginMovementMeters = 120,
  double minimumTargetMovementMeters = 120,
}) {
  if (lastOrigin == null || lastTarget == null || lastRequestedAt == null) {
    return true;
  }
  if (observedAt.isBefore(lastRequestedAt) ||
      observedAt.difference(lastRequestedAt) < minimumInterval) {
    return false;
  }

  return geoDistanceMeters(origin, lastOrigin) >= minimumOriginMovementMeters ||
      geoDistanceMeters(target, lastTarget) >= minimumTargetMovementMeters;
}

double geoDistanceMeters(GeoPoint a, GeoPoint b) {
  const double radius = 6371000;
  final double lat1 = a.latitude * math.pi / 180;
  final double lat2 = b.latitude * math.pi / 180;
  final double deltaLat = (b.latitude - a.latitude) * math.pi / 180;
  final double deltaLon =
      _wrappedLongitudeDelta(b.longitude - a.longitude) * math.pi / 180;
  final double haversine =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  return 2 * radius * math.asin(math.sqrt(haversine.clamp(0.0, 1.0)));
}

double geoBearingDegrees(GeoPoint a, GeoPoint b) {
  final double lat1 = a.latitude * math.pi / 180;
  final double lat2 = b.latitude * math.pi / 180;
  final double deltaLon =
      _wrappedLongitudeDelta(b.longitude - a.longitude) * math.pi / 180;
  final double y = math.sin(deltaLon) * math.cos(lat2);
  final double x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double _wrappedLongitudeDelta(double delta) {
  return ((delta + 540) % 360) - 180;
}
