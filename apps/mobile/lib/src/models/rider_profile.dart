class RiderProfile {
  const RiderProfile({
    required this.id,
    required this.displayName,
    required this.callsign,
    required this.homeArea,
  });

  final String id;
  final String displayName;
  final String? callsign;
  final String? homeArea;

  factory RiderProfile.fromJson(Map<String, Object?> json) {
    return RiderProfile(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      callsign: json['callsign'] as String?,
      homeArea: json['homeArea'] as String?,
    );
  }
}

class RiderProfileInput {
  const RiderProfileInput({
    required this.displayName,
    this.callsign,
    this.homeArea,
  });

  final String displayName;
  final String? callsign;
  final String? homeArea;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'displayName': displayName,
      'callsign': callsign,
      'homeArea': homeArea,
    };
  }
}
