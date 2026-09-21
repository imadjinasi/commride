enum RouteTravelMode {
  drive,
  twoWheeler;

  String get wireValue {
    return switch (this) {
      RouteTravelMode.drive => 'drive',
      RouteTravelMode.twoWheeler => 'two_wheeler',
    };
  }

  String get label {
    return switch (this) {
      RouteTravelMode.drive => 'Mobil',
      RouteTravelMode.twoWheeler => 'Motor',
    };
  }

  static RouteTravelMode fromWireValue(String value) {
    return switch (value) {
      'drive' => RouteTravelMode.drive,
      'two_wheeler' => RouteTravelMode.twoWheeler,
      _ => throw FormatException('Unknown route travel mode: $value'),
    };
  }
}

class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  factory GeoPoint.fromJson(Map<String, Object?> json) {
    return GeoPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'latitude': latitude, 'longitude': longitude};
  }
}

class PlaceSuggestion {
  const PlaceSuggestion({required this.reference, required this.text});

  final String reference;
  final String text;

  factory PlaceSuggestion.fromJson(Map<String, Object?> json) {
    return PlaceSuggestion(
      reference: json['reference'] as String,
      text: json['text'] as String,
    );
  }
}

class ResolvedPlace {
  const ResolvedPlace({
    required this.reference,
    required this.formattedAddress,
    required this.location,
  });

  final String reference;
  final String? formattedAddress;
  final GeoPoint location;

  factory ResolvedPlace.fromJson(Map<String, Object?> json) {
    return ResolvedPlace(
      reference: json['reference'] as String,
      formattedAddress: json['formattedAddress'] as String?,
      location: GeoPoint.fromJson(json['location'] as Map<String, Object?>),
    );
  }
}

class RouteLeg {
  const RouteLeg({required this.distanceMeters, required this.durationSeconds});

  final int distanceMeters;
  final int durationSeconds;

  factory RouteLeg.fromJson(Map<String, Object?> json) {
    return RouteLeg(
      distanceMeters: json['distanceMeters'] as int,
      durationSeconds: json['durationSeconds'] as int,
    );
  }
}

class RouteOption {
  const RouteOption({
    required this.routeIndex,
    required this.labels,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.encodedPolyline,
    this.routeToken,
    required this.legs,
  });

  final int routeIndex;
  final List<String> labels;
  final int distanceMeters;
  final int durationSeconds;
  final String encodedPolyline;
  final String? routeToken;
  final List<RouteLeg> legs;

  factory RouteOption.fromJson(Map<String, Object?> json) {
    return RouteOption(
      routeIndex: json['routeIndex'] as int,
      labels: (json['labels'] as List<Object?>).whereType<String>().toList(
        growable: false,
      ),
      distanceMeters: json['distanceMeters'] as int,
      durationSeconds: json['durationSeconds'] as int,
      encodedPolyline: json['encodedPolyline'] as String,
      routeToken: json['routeToken'] as String?,
      legs: (json['legs'] as List<Object?>)
          .map(
            (Object? value) => RouteLeg.fromJson(value as Map<String, Object?>),
          )
          .toList(growable: false),
    );
  }
}

enum StopType {
  generic,
  fuel,
  rest,
  meal,
  hotel,
  custom;

  String get wireValue => name;
}

enum CheckpointType {
  stop,
  fuel,
  rest,
  meal,
  regroup,
  mandatoryRegroup,
  hotel,
  custom,
  finish;

  String get wireValue {
    return switch (this) {
      CheckpointType.mandatoryRegroup => 'mandatory_regroup',
      _ => name,
    };
  }

  String get label {
    return switch (this) {
      CheckpointType.stop => 'Stop',
      CheckpointType.fuel => 'Fuel',
      CheckpointType.rest => 'Rest',
      CheckpointType.meal => 'Meal',
      CheckpointType.regroup => 'Regroup',
      CheckpointType.mandatoryRegroup => 'Mandatory Regroup',
      CheckpointType.hotel => 'Hotel',
      CheckpointType.custom => 'Custom',
      CheckpointType.finish => 'Finish',
    };
  }

  static CheckpointType fromWireValue(String value) {
    return CheckpointType.values.firstWhere(
      (CheckpointType type) => type.wireValue == value,
      orElse: () => throw FormatException('Unknown checkpoint type: $value'),
    );
  }
}

class PlanningStop {
  const PlanningStop({
    required this.label,
    required this.formattedAddress,
    required this.location,
    required this.stopType,
    required this.checkpointType,
    required this.plannedDurationMinutes,
  });

  final String label;
  final String? formattedAddress;
  final GeoPoint location;
  final StopType stopType;
  final CheckpointType? checkpointType;
  final int? plannedDurationMinutes;

  PlanningStop copyWith({
    StopType? stopType,
    CheckpointType? checkpointType,
    bool clearCheckpoint = false,
    int? plannedDurationMinutes,
    bool clearDuration = false,
  }) {
    return PlanningStop(
      label: label,
      formattedAddress: formattedAddress,
      location: location,
      stopType: stopType ?? this.stopType,
      checkpointType: clearCheckpoint
          ? null
          : checkpointType ?? this.checkpointType,
      plannedDurationMinutes: clearDuration
          ? null
          : plannedDurationMinutes ?? this.plannedDurationMinutes,
    );
  }

  factory PlanningStop.fromJson(Map<String, Object?> json) {
    final Object? checkpoint = json['checkpointType'];

    return PlanningStop(
      label: json['label'] as String,
      formattedAddress: json['formattedAddress'] as String?,
      location: GeoPoint.fromJson(json['location'] as Map<String, Object?>),
      stopType: StopType.values.firstWhere(
        (StopType type) => type.wireValue == json['stopType'],
      ),
      checkpointType: checkpoint is String
          ? CheckpointType.fromWireValue(checkpoint)
          : null,
      plannedDurationMinutes: json['plannedDurationMinutes'] as int?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'formattedAddress': formattedAddress,
      'location': location.toJson(),
      'stopType': stopType.wireValue,
      'checkpointType': checkpointType?.wireValue,
      'plannedDurationMinutes': plannedDurationMinutes,
    };
  }
}

class AlongRoutePlace {
  const AlongRoutePlace({
    required this.reference,
    required this.displayName,
    required this.formattedAddress,
    required this.location,
    required this.viaPlaceDistanceMeters,
    required this.viaPlaceDurationSeconds,
  });

  final String reference;
  final String displayName;
  final String? formattedAddress;
  final GeoPoint? location;
  final int? viaPlaceDistanceMeters;
  final int? viaPlaceDurationSeconds;

  factory AlongRoutePlace.fromJson(Map<String, Object?> json) {
    final Object? rawLocation = json['location'];

    return AlongRoutePlace(
      reference: json['reference'] as String,
      displayName: json['displayName'] as String,
      formattedAddress: json['formattedAddress'] as String?,
      location: rawLocation is Map<String, Object?>
          ? GeoPoint.fromJson(rawLocation)
          : null,
      viaPlaceDistanceMeters: json['viaPlaceDistanceMeters'] as int?,
      viaPlaceDurationSeconds: json['viaPlaceDurationSeconds'] as int?,
    );
  }
}

class SavedRoutePlan {
  const SavedRoutePlan({
    required this.revision,
    required this.travelMode,
    required this.originLabel,
    required this.origin,
    required this.destinationLabel,
    required this.destination,
    required this.route,
    required this.stops,
  });

  final int revision;
  final RouteTravelMode travelMode;
  final String? originLabel;
  final GeoPoint origin;
  final String? destinationLabel;
  final GeoPoint destination;
  final RouteOption route;
  final List<PlanningStop> stops;

  factory SavedRoutePlan.fromJson(Map<String, Object?> json) {
    final int distanceMeters = json['distanceMeters'] as int;
    final int durationSeconds = json['durationSeconds'] as int;

    return SavedRoutePlan(
      revision: json['revision'] as int,
      travelMode: RouteTravelMode.fromWireValue(json['travelMode'] as String),
      originLabel: json['originLabel'] as String?,
      origin: GeoPoint.fromJson(json['origin'] as Map<String, Object?>),
      destinationLabel: json['destinationLabel'] as String?,
      destination: GeoPoint.fromJson(
        json['destination'] as Map<String, Object?>,
      ),
      route: RouteOption(
        routeIndex: 0,
        labels: const <String>[],
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        encodedPolyline: json['encodedPolyline'] as String,
        routeToken: null,
        legs: const <RouteLeg>[],
      ),
      stops: (json['stops'] as List<Object?>)
          .map(
            (Object? value) =>
                PlanningStop.fromJson(value as Map<String, Object?>),
          )
          .toList(growable: false),
    );
  }
}
