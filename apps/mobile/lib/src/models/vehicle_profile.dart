enum VehicleKind {
  motorcycle,
  car,
  other;

  String get wireValue => name;

  String get label {
    return switch (this) {
      VehicleKind.motorcycle => 'Motor',
      VehicleKind.car => 'Mobil',
      VehicleKind.other => 'Lainnya',
    };
  }

  static VehicleKind fromWireValue(String value) {
    return VehicleKind.values.firstWhere(
      (VehicleKind kind) => kind.wireValue == value,
      orElse: () => throw FormatException('Unknown Vehicle kind: $value'),
    );
  }
}

class VehicleProfile {
  const VehicleProfile({
    required this.id,
    required this.kind,
    required this.make,
    required this.model,
    required this.nickname,
    required this.fuelType,
    required this.safeRangeKm,
  });

  final String id;
  final VehicleKind kind;
  final String? make;
  final String? model;
  final String? nickname;
  final String? fuelType;
  final int? safeRangeKm;

  String get displayName {
    final List<String> parts = <String?>[
      nickname,
      make,
      model,
    ].whereType<String>().toList(growable: false);

    if (parts.isEmpty) {
      return kind.label;
    }

    return parts.join(' · ');
  }

  factory VehicleProfile.fromJson(Map<String, Object?> json) {
    return VehicleProfile(
      id: json['id'] as String,
      kind: VehicleKind.fromWireValue(json['kind'] as String),
      make: json['make'] as String?,
      model: json['model'] as String?,
      nickname: json['nickname'] as String?,
      fuelType: json['fuelType'] as String?,
      safeRangeKm: json['safeRangeKm'] as int?,
    );
  }
}

class VehicleProfileInput {
  const VehicleProfileInput({
    required this.kind,
    this.make,
    this.model,
    this.nickname,
    this.fuelType,
    this.safeRangeKm,
  });

  final VehicleKind kind;
  final String? make;
  final String? model;
  final String? nickname;
  final String? fuelType;
  final int? safeRangeKm;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'make': make,
      'model': model,
      'nickname': nickname,
      'fuelType': fuelType,
      'safeRangeKm': safeRangeKm,
    };
  }
}
