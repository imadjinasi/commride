import '../models/club_ride.dart';
import '../models/ride_message.dart';
import 'convoy_separation.dart';
import 'live_group_models.dart';
import 'location_provider.dart';
import '../models/ride_sos.dart';

enum ActiveRideRealtimeConnectionState { disconnected, connecting, connected }

sealed class ActiveRideRealtimeEvent {
  const ActiveRideRealtimeEvent();
}

class ActiveRideConnectionChanged extends ActiveRideRealtimeEvent {
  const ActiveRideConnectionChanged(this.state);

  final ActiveRideRealtimeConnectionState state;
}

class ActiveRideEnded extends ActiveRideRealtimeEvent {
  const ActiveRideEnded({required this.endedAt});

  final DateTime endedAt;
}

class ActiveRideSnapshotReceived extends ActiveRideRealtimeEvent {
  const ActiveRideSnapshotReceived({
    required this.rideId,
    required this.presences,
    this.separation,
  });

  final String rideId;
  final List<LiveRiderPresence> presences;
  final LiveConvoySeparation? separation;
}

class ActiveRidePresenceUpdated extends ActiveRideRealtimeEvent {
  const ActiveRidePresenceUpdated({required this.presence});

  final LiveRiderPresence presence;
}

class ActiveRideSeparationUpdated extends ActiveRideRealtimeEvent {
  const ActiveRideSeparationUpdated({required this.separation});

  final LiveConvoySeparation separation;
}

class ActiveRideQuickActionRaised extends ActiveRideRealtimeEvent {
  const ActiveRideQuickActionRaised({required this.action});

  final LiveQuickAction action;
}

class ActiveRideMessageCreated extends ActiveRideRealtimeEvent {
  const ActiveRideMessageCreated({required this.message});

  final RideMessage message;
}

class ActiveRideSosChanged extends ActiveRideRealtimeEvent {
  const ActiveRideSosChanged({required this.type, required this.sos});

  final String type;
  final RideSos sos;
}

class ActiveRideRoutePlanUpdated extends ActiveRideRealtimeEvent {
  const ActiveRideRoutePlanUpdated({
    required this.rideId,
    required this.revision,
    required this.updatedByRiderId,
    required this.updatedByRole,
  });

  final String rideId;
  final int revision;
  final String updatedByRiderId;
  final RideRole updatedByRole;
}

class ActiveRideServerError extends ActiveRideRealtimeEvent {
  const ActiveRideServerError({required this.code, required this.message});

  final String code;
  final String message;
}

abstract interface class ActiveRideRealtimeClient {
  Stream<ActiveRideRealtimeEvent> get events;

  Future<void> connect(String rideId);

  Future<void> disconnect();

  Future<void> sendPresence(RideLocationSample sample);

  Future<void> sendQuickAction(LiveQuickActionKind kind, {String? reason});
}
