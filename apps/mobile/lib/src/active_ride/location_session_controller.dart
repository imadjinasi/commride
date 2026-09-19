import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/club_ride.dart';
import 'location_provider.dart';
import 'realtime_client.dart';

enum RideLocationSessionPhase {
  inactive,
  permissionRequired,
  starting,
  active,
  degraded,
  stopping,
  stoppedByRideEnd,
  denied,
  error,
}

class RideLocationSessionState {
  const RideLocationSessionState({
    required this.phase,
    required this.connectionState,
    required this.lastSample,
    required this.pendingSample,
    required this.message,
  });

  const RideLocationSessionState.inactive()
    : phase = RideLocationSessionPhase.inactive,
      connectionState = ActiveRideRealtimeConnectionState.disconnected,
      lastSample = null,
      pendingSample = null,
      message = null;

  final RideLocationSessionPhase phase;
  final ActiveRideRealtimeConnectionState connectionState;
  final RideLocationSample? lastSample;
  final RideLocationSample? pendingSample;
  final String? message;

  bool get isTracking =>
      phase == RideLocationSessionPhase.active ||
      phase == RideLocationSessionPhase.degraded;

  RideLocationSessionState copyWith({
    RideLocationSessionPhase? phase,
    ActiveRideRealtimeConnectionState? connectionState,
    RideLocationSample? lastSample,
    bool clearLastSample = false,
    RideLocationSample? pendingSample,
    bool clearPendingSample = false,
    String? message,
    bool clearMessage = false,
  }) {
    return RideLocationSessionState(
      phase: phase ?? this.phase,
      connectionState: connectionState ?? this.connectionState,
      lastSample: clearLastSample ? null : (lastSample ?? this.lastSample),
      pendingSample: clearPendingSample
          ? null
          : (pendingSample ?? this.pendingSample),
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class RideLocationSessionController extends ChangeNotifier {
  RideLocationSessionController({
    required RideLocationProvider locationProvider,
    required ActiveRideRealtimeClient realtimeClient,
    bool ownsRealtimeConnection = true,
  }) : _locationProvider = locationProvider,
       _realtimeClient = realtimeClient,
       _ownsRealtimeConnection = ownsRealtimeConnection;

  final RideLocationProvider _locationProvider;
  final ActiveRideRealtimeClient _realtimeClient;
  final bool _ownsRealtimeConnection;

  RideLocationSessionState _state = const RideLocationSessionState.inactive();
  StreamSubscription<RideLocationSample>? _sampleSubscription;
  StreamSubscription<ActiveRideRealtimeEvent>? _realtimeSubscription;
  String? _rideId;
  bool _disposed = false;

  RideLocationSessionState get state => _state;

  Future<void> startTracking(Ride ride) async {
    if (_disposed) {
      return;
    }

    if (ride.status != RideStatus.active) {
      _setState(
        _state.copyWith(
          phase: RideLocationSessionPhase.error,
          message: 'Tracking hanya dapat dimulai ketika Ride sudah Active.',
        ),
      );
      return;
    }

    if (_state.isTracking ||
        _state.phase == RideLocationSessionPhase.starting) {
      return;
    }

    _rideId = ride.id;
    _setState(
      _state.copyWith(
        phase: RideLocationSessionPhase.permissionRequired,
        clearMessage: true,
      ),
    );

    RideLocationPermission permission;
    try {
      permission = await _locationProvider.checkPermission();
      if (permission != RideLocationPermission.granted) {
        permission = await _locationProvider.requestPermission();
      }
    } catch (_) {
      _setState(
        _state.copyWith(
          phase: RideLocationSessionPhase.error,
          message: 'Status izin lokasi belum dapat diperiksa.',
        ),
      );
      return;
    }

    if (permission != RideLocationPermission.granted) {
      _setState(
        _state.copyWith(
          phase: RideLocationSessionPhase.denied,
          message: permission == RideLocationPermission.deniedPermanently
              ? 'Izin lokasi diblokir. Buka pengaturan perangkat untuk '
                    'mengaktifkannya.'
              : 'Izin lokasi diperlukan untuk berbagi posisi saat Ride.',
        ),
      );
      return;
    }

    _setState(
      _state.copyWith(
        phase: RideLocationSessionPhase.starting,
        connectionState: ActiveRideRealtimeConnectionState.connecting,
        clearMessage: true,
      ),
    );

    await _cancelSubscriptions();

    _realtimeSubscription = _realtimeClient.events.listen(
      _handleRealtimeEvent,
      onError: (_) {
        _setDegraded('Koneksi realtime terputus.');
      },
    );

    try {
      if (_ownsRealtimeConnection) {
        await _realtimeClient.connect(ride.id);
      }
      _sampleSubscription = _locationProvider.samples.listen(
        (RideLocationSample sample) {
          unawaited(_handleSample(sample));
        },
        onError: (_) {
          _setDegraded('Lokasi perangkat sementara tidak tersedia.');
        },
      );
      await _locationProvider.start();

      _setState(
        _state.copyWith(
          phase: RideLocationSessionPhase.active,
          connectionState: ActiveRideRealtimeConnectionState.connected,
          clearMessage: true,
        ),
      );
    } catch (_) {
      await _stopResources();
      _setState(
        _state.copyWith(
          phase: RideLocationSessionPhase.error,
          connectionState: ActiveRideRealtimeConnectionState.disconnected,
          message: 'Tracking Ride belum dapat dimulai.',
        ),
      );
    }
  }

  Future<void> stopTracking() async {
    await _stop(finalPhase: RideLocationSessionPhase.inactive, message: null);
  }

  Future<void> stopForRideEnd() async {
    await _stop(
      finalPhase: RideLocationSessionPhase.stoppedByRideEnd,
      message: 'Tracking berhenti karena Ride telah selesai.',
    );
  }

  Future<void> stopForSignOut() async {
    await _stop(finalPhase: RideLocationSessionPhase.inactive, message: null);
  }

  Future<void> _handleSample(RideLocationSample sample) async {
    if (!_state.isTracking ||
        _rideId == null ||
        _state.phase == RideLocationSessionPhase.stopping) {
      return;
    }

    _setState(
      _state.copyWith(
        lastSample: sample,
        clearMessage: _state.phase == RideLocationSessionPhase.active,
      ),
    );

    try {
      await _realtimeClient.sendPresence(sample);
      if (_state.phase == RideLocationSessionPhase.degraded &&
          _state.connectionState ==
              ActiveRideRealtimeConnectionState.connected) {
        _setState(
          _state.copyWith(
            phase: RideLocationSessionPhase.active,
            clearPendingSample: true,
            clearMessage: true,
          ),
        );
      } else if (_state.pendingSample != null) {
        _setState(_state.copyWith(clearPendingSample: true));
      }
    } catch (_) {
      // One newest unsent observation is enough for operational recovery.
      // This deliberately does not grow into an offline GPS trace.
      _setState(
        _state.copyWith(
          phase: RideLocationSessionPhase.degraded,
          pendingSample: sample,
          message: 'Posisi terbaru menunggu koneksi realtime.',
        ),
      );
    }
  }

  void _handleRealtimeEvent(ActiveRideRealtimeEvent event) {
    if (event is ActiveRideEnded) {
      final StreamSubscription<ActiveRideRealtimeEvent>? subscription =
          _realtimeSubscription;
      _realtimeSubscription = null;
      unawaited(subscription?.cancel());
      unawaited(stopForRideEnd());
      return;
    }

    if (event is! ActiveRideConnectionChanged) {
      return;
    }

    _setState(_state.copyWith(connectionState: event.state));

    if (event.state == ActiveRideRealtimeConnectionState.connected) {
      final RideLocationSample? pending = _state.pendingSample;
      if (pending == null) {
        if (_state.phase == RideLocationSessionPhase.degraded) {
          _setState(
            _state.copyWith(
              phase: RideLocationSessionPhase.active,
              clearMessage: true,
            ),
          );
        }
        return;
      }

      unawaited(_flushPending(pending));
      return;
    }

    if (_state.isTracking) {
      _setDegraded('Koneksi realtime terputus. Posisi terbaru akan ditahan.');
    }
  }

  Future<void> _flushPending(RideLocationSample pending) async {
    try {
      await _realtimeClient.sendPresence(pending);
      if (_state.pendingSample == pending) {
        _setState(
          _state.copyWith(
            phase: RideLocationSessionPhase.active,
            clearPendingSample: true,
            clearMessage: true,
          ),
        );
      }
    } catch (_) {
      _setDegraded('Posisi terbaru masih menunggu koneksi realtime.');
    }
  }

  Future<void> _stop({
    required RideLocationSessionPhase finalPhase,
    required String? message,
  }) async {
    if (_disposed) {
      return;
    }

    if (_state.phase == RideLocationSessionPhase.stopping) {
      return;
    }

    _setState(
      _state.copyWith(
        phase: RideLocationSessionPhase.stopping,
        clearMessage: true,
      ),
    );

    await _stopResources();
    _rideId = null;

    _setState(
      RideLocationSessionState(
        phase: finalPhase,
        connectionState: ActiveRideRealtimeConnectionState.disconnected,
        lastSample: _state.lastSample,
        pendingSample: null,
        message: message,
      ),
    );
  }

  Future<void> _stopResources() async {
    await _cancelSubscriptions();

    try {
      await _locationProvider.stop();
    } catch (_) {
      // Stopping is best-effort; realtime disconnect still proceeds.
    }

    if (_ownsRealtimeConnection) {
      try {
        await _realtimeClient.disconnect();
      } catch (_) {
        // Local state still becomes stopped even if transport teardown fails.
      }
    }
  }

  Future<void> _cancelSubscriptions() async {
    await _sampleSubscription?.cancel();
    _sampleSubscription = null;
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }

  void _setDegraded(String message) {
    if (_disposed) {
      return;
    }

    _setState(
      _state.copyWith(
        phase: RideLocationSessionPhase.degraded,
        message: message,
      ),
    );
  }

  void _setState(RideLocationSessionState next) {
    if (_disposed) {
      return;
    }

    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sampleSubscription?.cancel());
    unawaited(_realtimeSubscription?.cancel());
    unawaited(_locationProvider.stop());
    if (_ownsRealtimeConnection) {
      unawaited(_realtimeClient.disconnect());
    }
    super.dispose();
  }
}
