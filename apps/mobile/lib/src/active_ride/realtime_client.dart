import 'live_group_models.dart';
import 'location_provider.dart';

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
  });

  final String rideId;
  final List<LiveRiderPresence> presences;
}

class ActiveRidePresenceUpdated extends ActiveRideRealtimeEvent {
  const ActiveRidePresenceUpdated({required this.presence});

  final LiveRiderPresence presence;
}

class ActiveRideQuickActionRaised extends ActiveRideRealtimeEvent {
  const ActiveRideQuickActionRaised({required this.action});

  final LiveQuickAction action;
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

  Future<void> sendQuickAction(
    LiveQuickActionKind kind, {
    String? reason,
  });
}
