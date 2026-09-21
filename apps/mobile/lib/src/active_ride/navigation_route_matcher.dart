import 'dart:math' as math;

import '../models/route_planner.dart';

const int _shapeSamples = 16;

/// Chooses a fresh provider route that still represents the persisted RoutePlan.
///
/// Route tokens are intentionally not persisted because provider tokens expire.
/// Before embedded guidance starts, CommRide recomputes routes and uses this
/// geometry matcher so a previously selected alternative is not silently
/// replaced by the provider's current default route.
RouteOption? selectNavigationRoute(
  SavedRoutePlan plan,
  List<RouteOption> candidates,
) {
  final List<RouteOption> tokenized = candidates
      .where(
        (RouteOption candidate) =>
            candidate.routeToken != null &&
            candidate.routeToken!.trim().isNotEmpty,
      )
      .toList(growable: false);

  if (tokenized.isEmpty) {
    return null;
  }

  final List<GeoPoint>? plannedPoints = _decodePolyline(
    plan.route.encodedPolyline,
  );
  if (plannedPoints == null || plannedPoints.length < 2) {
    return null;
  }

  _RouteSimilarity? best;
  for (final RouteOption candidate in tokenized) {
    final List<GeoPoint>? candidatePoints = _decodePolyline(
      candidate.encodedPolyline,
    );
    if (candidatePoints == null || candidatePoints.length < 2) {
      continue;
    }

    final _RouteSimilarity similarity = _similarity(
      plan,
      plannedPoints,
      candidate,
      candidatePoints,
    );
    if (best == null || similarity.score < best.score) {
      best = similarity;
    }
  }

  if (best == null || !best.acceptable) {
    return null;
  }
  return best.route;
}

class _RouteSimilarity {
  const _RouteSimilarity({
    required this.route,
    required this.score,
    required this.acceptable,
  });

  final RouteOption route;
  final double score;
  final bool acceptable;
}

_RouteSimilarity _similarity(
  SavedRoutePlan plan,
  List<GeoPoint> plannedPoints,
  RouteOption candidate,
  List<GeoPoint> candidatePoints,
) {
  final List<GeoPoint> plannedSamples = _sampleByDistance(
    plannedPoints,
    _shapeSamples,
  );
  final List<GeoPoint> candidateSamples = _sampleByDistance(
    candidatePoints,
    _shapeSamples,
  );

  double separationTotal = 0;
  for (int index = 0; index < _shapeSamples; index += 1) {
    separationTotal += _haversineMeters(
      plannedSamples[index],
      candidateSamples[index],
    );
  }
  final double meanShapeSeparation = separationTotal / _shapeSamples;

  final double distanceDeltaRatio = _relativeDelta(
    plan.route.distanceMeters,
    candidate.distanceMeters,
  );
  final double durationDeltaRatio = _relativeDelta(
    plan.route.durationSeconds,
    candidate.durationSeconds,
  );

  // Geometry is the dominant signal. Distance/time deltas break ties and
  // guard against a materially different provider route being accepted merely
  // because endpoints match.
  final double score =
      meanShapeSeparation +
      (distanceDeltaRatio * 5000) +
      (durationDeltaRatio * 1000);

  final double maximumShapeSeparation = math.max(
    1500,
    plan.route.distanceMeters * 0.015,
  );

  return _RouteSimilarity(
    route: candidate,
    score: score,
    acceptable:
        meanShapeSeparation <= maximumShapeSeparation &&
        distanceDeltaRatio <= 0.25 &&
        durationDeltaRatio <= 0.4,
  );
}

double _relativeDelta(int expected, int actual) {
  if (expected <= 0) {
    return actual == expected ? 0 : 1;
  }
  return (actual - expected).abs() / expected;
}

List<GeoPoint> _sampleByDistance(List<GeoPoint> points, int sampleCount) {
  if (points.length == 1) {
    return List<GeoPoint>.filled(sampleCount, points.first);
  }

  final List<double> cumulative = <double>[0];
  for (int index = 1; index < points.length; index += 1) {
    cumulative.add(
      cumulative.last + _haversineMeters(points[index - 1], points[index]),
    );
  }

  final double total = cumulative.last;
  if (total <= 0) {
    return List<GeoPoint>.filled(sampleCount, points.first);
  }

  final List<GeoPoint> result = <GeoPoint>[];
  int segment = 1;

  for (int sample = 0; sample < sampleCount; sample += 1) {
    final double fraction = sampleCount == 1
        ? 0
        : sample / (sampleCount - 1);
    final double target = total * fraction;

    while (segment < cumulative.length - 1 &&
        cumulative[segment] < target) {
      segment += 1;
    }

    final double segmentStart = cumulative[segment - 1];
    final double segmentEnd = cumulative[segment];
    final double segmentLength = segmentEnd - segmentStart;
    final double ratio = segmentLength <= 0
        ? 0
        : ((target - segmentStart) / segmentLength).clamp(0, 1).toDouble();

    final GeoPoint start = points[segment - 1];
    final GeoPoint end = points[segment];
    result.add(
      GeoPoint(
        latitude: start.latitude + ((end.latitude - start.latitude) * ratio),
        longitude:
            start.longitude + ((end.longitude - start.longitude) * ratio),
      ),
    );
  }

  return result;
}

List<GeoPoint>? _decodePolyline(String encoded) {
  if (encoded.isEmpty || encoded.length > 200000) {
    return null;
  }

  final List<GeoPoint> points = <GeoPoint>[];
  int index = 0;
  int latitude = 0;
  int longitude = 0;

  try {
    while (index < encoded.length) {
      final _DecodedValue latitudeValue = _decodeValue(encoded, index);
      index = latitudeValue.nextIndex;
      latitude += latitudeValue.value;

      final _DecodedValue longitudeValue = _decodeValue(encoded, index);
      index = longitudeValue.nextIndex;
      longitude += longitudeValue.value;

      final double decodedLatitude = latitude / 1e5;
      final double decodedLongitude = longitude / 1e5;
      if (decodedLatitude < -90 ||
          decodedLatitude > 90 ||
          decodedLongitude < -180 ||
          decodedLongitude > 180) {
        return null;
      }

      points.add(
        GeoPoint(
          latitude: decodedLatitude,
          longitude: decodedLongitude,
        ),
      );
    }
  } on FormatException {
    return null;
  }

  return points.length >= 2 ? points : null;
}

class _DecodedValue {
  const _DecodedValue(this.value, this.nextIndex);

  final int value;
  final int nextIndex;
}

_DecodedValue _decodeValue(String encoded, int startIndex) {
  int result = 0;
  int shift = 0;
  int index = startIndex;

  while (true) {
    if (index >= encoded.length || shift > 30) {
      throw const FormatException('Invalid encoded polyline.');
    }
    final int value = encoded.codeUnitAt(index) - 63;
    if (value < 0 || value > 63) {
      throw const FormatException('Invalid encoded polyline.');
    }
    index += 1;
    result |= (value & 0x1f) << shift;
    shift += 5;
    if (value < 0x20) {
      break;
    }
  }

  final int decoded = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  return _DecodedValue(decoded, index);
}

double _haversineMeters(GeoPoint a, GeoPoint b) {
  const double earthRadiusMeters = 6371000;
  final double lat1 = _radians(a.latitude);
  final double lat2 = _radians(b.latitude);
  final double deltaLatitude = _radians(b.latitude - a.latitude);
  final double deltaLongitude = _radians(b.longitude - a.longitude);

  final double sinLat = math.sin(deltaLatitude / 2);
  final double sinLon = math.sin(deltaLongitude / 2);
  final double value =
      (sinLat * sinLat) +
      (math.cos(lat1) * math.cos(lat2) * sinLon * sinLon);
  final double centralAngle = 2 * math.atan2(
    math.sqrt(value),
    math.sqrt(math.max(0, 1 - value)),
  );
  return earthRadiusMeters * centralAngle;
}

double _radians(double degrees) => degrees * math.pi / 180;
