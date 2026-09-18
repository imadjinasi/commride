import 'location_provider.dart';

enum ActiveRideRealtimeConnectionState {
  disconnected,
  connecting,
  connected,
}

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

abstract interface class ActiveRideRealtimeClient {
  Stream<ActiveRideRealtimeEvent> get events;

  Future<void> connect(String rideId);

  Future<void> disconnect();

  Future<void> sendPresence(RideLocationSample sample);
}
