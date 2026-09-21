enum ConvoySeparationPhase {
  insufficientData,
  normal,
  splitCandidate,
  separatedAttention;

  String get wireValue {
    return switch (this) {
      ConvoySeparationPhase.insufficientData => 'insufficient_data',
      ConvoySeparationPhase.normal => 'normal',
      ConvoySeparationPhase.splitCandidate => 'split_candidate',
      ConvoySeparationPhase.separatedAttention => 'separated_attention',
    };
  }

  static ConvoySeparationPhase fromWireValue(String value) {
    return ConvoySeparationPhase.values.firstWhere(
      (ConvoySeparationPhase phase) => phase.wireValue == value,
      orElse: () =>
          throw FormatException('Unknown convoy separation phase: $value'),
    );
  }
}

class LiveConvoySeparation {
  const LiveConvoySeparation({
    required this.phase,
    required this.dataSufficient,
    required this.components,
    required this.isolatedRiderIds,
    required this.sweeperComponentRiderIds,
    required this.firstSplitObservedAt,
    required this.confirmedAt,
    required this.recoveryObservedAt,
    required this.lastUpdatedAt,
  });

  final ConvoySeparationPhase phase;
  final bool dataSufficient;
  final List<List<String>> components;
  final List<String> isolatedRiderIds;
  final List<String>? sweeperComponentRiderIds;
  final DateTime? firstSplitObservedAt;
  final DateTime? confirmedAt;
  final DateTime? recoveryObservedAt;
  final DateTime lastUpdatedAt;

  bool get hasConfirmedAttention =>
      phase == ConvoySeparationPhase.separatedAttention;

  factory LiveConvoySeparation.fromJson(Map<String, Object?> json) {
    return LiveConvoySeparation(
      phase: ConvoySeparationPhase.fromWireValue(
        _requiredString(json['phase'], 'phase'),
      ),
      dataSufficient: _requiredBool(json['dataSufficient'], 'dataSufficient'),
      components: _stringMatrix(json['components'], 'components'),
      isolatedRiderIds: _stringList(
        json['isolatedRiderIds'],
        'isolatedRiderIds',
      ),
      sweeperComponentRiderIds: _optionalStringList(
        json['sweeperComponentRiderIds'],
        'sweeperComponentRiderIds',
      ),
      firstSplitObservedAt: _optionalDate(
        json['firstSplitObservedAt'],
        'firstSplitObservedAt',
      ),
      confirmedAt: _optionalDate(json['confirmedAt'], 'confirmedAt'),
      recoveryObservedAt: _optionalDate(
        json['recoveryObservedAt'],
        'recoveryObservedAt',
      ),
      lastUpdatedAt: _requiredDate(json['lastUpdatedAt'], 'lastUpdatedAt'),
    );
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field is required.');
  }
  return value.trim();
}

bool _requiredBool(Object? value, String field) {
  if (value is! bool) {
    throw FormatException('$field must be a boolean.');
  }
  return value;
}

List<String> _stringList(Object? value, String field) {
  if (value is! List<Object?>) {
    throw FormatException('$field must be a string list.');
  }

  return value
      .map((Object? item) {
        if (item is! String || item.trim().isEmpty) {
          throw FormatException('$field contains an invalid Rider ID.');
        }
        return item.trim();
      })
      .toList(growable: false);
}

List<String>? _optionalStringList(Object? value, String field) {
  if (value == null) {
    return null;
  }
  return _stringList(value, field);
}

List<List<String>> _stringMatrix(Object? value, String field) {
  if (value is! List<Object?>) {
    throw FormatException('$field must be a list of Rider groups.');
  }

  return value
      .map((Object? item) {
        if (item is! List<Object?>) {
          throw FormatException('$field contains an invalid Rider group.');
        }
        return _stringList(item, field);
      })
      .toList(growable: false);
}

DateTime _requiredDate(Object? value, String field) {
  final DateTime? parsed = _optionalDate(value, field);
  if (parsed == null) {
    throw FormatException('$field timestamp is required.');
  }
  return parsed;
}

DateTime? _optionalDate(Object? value, String field) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('$field must be an ISO timestamp or null.');
  }

  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$field timestamp is invalid.');
  }
  return parsed;
}
