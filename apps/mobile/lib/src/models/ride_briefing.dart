import 'route_planner.dart';

class BriefingRoleIdentity {
  const BriefingRoleIdentity({
    required this.riderId,
    required this.displayName,
  });

  final String riderId;
  final String displayName;

  factory BriefingRoleIdentity.fromJson(Map<String, Object?> json) {
    return BriefingRoleIdentity(
      riderId: json['riderId'] as String,
      displayName: json['displayName'] as String,
    );
  }
}

class RideBriefing {
  const RideBriefing({
    required this.id,
    required this.rideId,
    required this.revision,
    required this.routePlanId,
    required this.createdByRiderId,
    required this.scheduledStartAt,
    required this.leader,
    required this.sweeper,
    required this.notes,
    required this.isCurrent,
    required this.publishedAt,
  });

  final String id;
  final String rideId;
  final int revision;
  final String routePlanId;
  final String createdByRiderId;
  final DateTime? scheduledStartAt;
  final BriefingRoleIdentity leader;
  final BriefingRoleIdentity? sweeper;
  final String? notes;
  final bool isCurrent;
  final DateTime publishedAt;

  factory RideBriefing.fromJson(Map<String, Object?> json) {
    final Object? rawSweeper = json['sweeper'];
    final Object? rawScheduledStartAt = json['scheduledStartAt'];

    return RideBriefing(
      id: json['id'] as String,
      rideId: json['rideId'] as String,
      revision: json['revision'] as int,
      routePlanId: json['routePlanId'] as String,
      createdByRiderId: json['createdByRiderId'] as String,
      scheduledStartAt: rawScheduledStartAt is String
          ? DateTime.parse(rawScheduledStartAt)
          : null,
      leader: BriefingRoleIdentity.fromJson(
        json['leader'] as Map<String, Object?>,
      ),
      sweeper: rawSweeper is Map<String, Object?>
          ? BriefingRoleIdentity.fromJson(rawSweeper)
          : null,
      notes: json['notes'] as String?,
      isCurrent: json['isCurrent'] as bool,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
    );
  }
}

class BriefingReadiness {
  const BriefingReadiness({
    required this.expectedCount,
    required this.readyCount,
    required this.currentRiderAcknowledged,
  });

  final int expectedCount;
  final int readyCount;
  final bool currentRiderAcknowledged;

  factory BriefingReadiness.fromJson(Map<String, Object?> json) {
    return BriefingReadiness(
      expectedCount: json['expectedCount'] as int,
      readyCount: json['readyCount'] as int,
      currentRiderAcknowledged:
          json['currentRiderAcknowledged'] as bool,
    );
  }
}

class RideBriefingView {
  const RideBriefingView({
    required this.briefing,
    required this.routePlan,
    required this.readiness,
    required this.routePlanIsCurrent,
  });

  final RideBriefing briefing;
  final SavedRoutePlan routePlan;
  final BriefingReadiness readiness;
  final bool routePlanIsCurrent;

  factory RideBriefingView.fromJson(Map<String, Object?> json) {
    return RideBriefingView(
      briefing: RideBriefing.fromJson(
        json['briefing'] as Map<String, Object?>,
      ),
      routePlan: SavedRoutePlan.fromJson(
        json['routePlan'] as Map<String, Object?>,
      ),
      readiness: BriefingReadiness.fromJson(
        json['readiness'] as Map<String, Object?>,
      ),
      routePlanIsCurrent: json['routePlanIsCurrent'] as bool,
    );
  }
}
