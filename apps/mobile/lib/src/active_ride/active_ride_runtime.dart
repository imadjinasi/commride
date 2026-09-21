import 'dart:async';

import '../auth/auth_gateway.dart';
import '../models/club_ride.dart';
import 'geolocator_ride_location_provider.dart';
import 'io_active_ride_realtime_client.dart';
import 'live_group_controller.dart';
import 'location_session_controller.dart';

class ActiveRideRuntime {
  ActiveRideRuntime({
    required this.rideId,
    required this.realtimeClient,
    required this.locationProvider,
    required this.locationSession,
    required this.groupController,
  });

  final String rideId;
  final IoActiveRideRealtimeClient realtimeClient;
  final GeolocatorRideLocationProvider locationProvider;
  final RideLocationSessionController locationSession;
  final ActiveRideGroupController groupController;

  Future<void> close({bool rideEnded = false}) async {
    if (rideEnded) {
      await locationSession.stopForRideEnd();
    } else {
      await locationSession.stopForSignOut();
    }
    groupController.dispose();
    await realtimeClient.disconnect();
    await locationProvider.dispose();
    locationSession.dispose();
  }
}

class ActiveRideRuntimeManager {
  ActiveRideRuntimeManager({
    required Uri apiBaseUrl,
    required AuthGateway authGateway,
  }) : _apiBaseUrl = apiBaseUrl,
       _authGateway = authGateway;

  final Uri _apiBaseUrl;
  final AuthGateway _authGateway;

  ActiveRideRuntime? _current;
  Future<ActiveRideRuntime>? _opening;
  bool _disposed = false;

  ActiveRideRuntime? get current => _current;

  Future<ActiveRideRuntime> open(Ride ride) {
    if (_disposed) {
      throw StateError('Active Ride runtime sudah ditutup.');
    }
    if (ride.status != RideStatus.active) {
      throw StateError('Active Ride runtime hanya tersedia untuk Ride Active.');
    }

    final ActiveRideRuntime? current = _current;
    if (current != null && current.rideId == ride.id) {
      return Future<ActiveRideRuntime>.value(current);
    }

    final Future<ActiveRideRuntime>? opening = _opening;
    if (opening != null) {
      return opening.then((ActiveRideRuntime runtime) {
        if (runtime.rideId == ride.id) {
          return runtime;
        }
        return open(ride);
      });
    }

    final Future<ActiveRideRuntime> operation = _openFresh(ride);
    _opening = operation;
    return operation.whenComplete(() {
      if (identical(_opening, operation)) {
        _opening = null;
      }
    });
  }

  Future<ActiveRideRuntime> _openFresh(Ride ride) async {
    await close();

    final IoActiveRideRealtimeClient realtimeClient =
        IoActiveRideRealtimeClient(
          apiBaseUrl: _apiBaseUrl,
          authGateway: _authGateway,
        );
    final GeolocatorRideLocationProvider locationProvider =
        GeolocatorRideLocationProvider();
    final RideLocationSessionController locationSession =
        RideLocationSessionController(
          locationProvider: locationProvider,
          realtimeClient: realtimeClient,
          ownsRealtimeConnection: false,
        );
    final ActiveRideGroupController groupController = ActiveRideGroupController(
      rideId: ride.id,
      realtimeClient: realtimeClient,
    )..start();

    final ActiveRideRuntime runtime = ActiveRideRuntime(
      rideId: ride.id,
      realtimeClient: realtimeClient,
      locationProvider: locationProvider,
      locationSession: locationSession,
      groupController: groupController,
    );

    try {
      await realtimeClient.connect(ride.id);
      _current = runtime;
      return runtime;
    } catch (_) {
      await runtime.close();
      rethrow;
    }
  }

  Future<void> stopForRideEnd(String rideId) async {
    final ActiveRideRuntime? runtime = _current;
    if (runtime == null || runtime.rideId != rideId) {
      return;
    }

    _current = null;
    await runtime.close(rideEnded: true);
  }

  Future<void> close() async {
    final ActiveRideRuntime? runtime = _current;
    _current = null;
    if (runtime != null) {
      await runtime.close();
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    unawaited(close());
  }
}
