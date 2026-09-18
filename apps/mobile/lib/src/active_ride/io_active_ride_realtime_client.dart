import 'dart:async';
import 'dart:convert';

import '../auth/auth_gateway.dart';
import 'live_group_models.dart';
import 'location_provider.dart';
import 'realtime_client.dart';
import 'socket.dart';

typedef ReconnectDelay = Future<void> Function(Duration duration);

class IoActiveRideRealtimeClient implements ActiveRideRealtimeClient {
  IoActiveRideRealtimeClient({
    required Uri apiBaseUrl,
    required AuthGateway authGateway,
    ActiveRideSocketConnector socketConnector =
        const IoActiveRideSocketConnector(),
    DateTime Function()? now,
    String Function()? eventIdFactory,
    ReconnectDelay? reconnectDelay,
  }) : _apiBaseUrl = apiBaseUrl,
       _authGateway = authGateway,
       _socketConnector = socketConnector,
       _now = now ?? DateTime.now,
       _eventIdFactory = eventIdFactory ?? _defaultEventId,
       _reconnectDelay = reconnectDelay ?? Future<void>.delayed;

  static const int protocolVersion = 1;

  final Uri _apiBaseUrl;
  final AuthGateway _authGateway;
  final ActiveRideSocketConnector _socketConnector;
  final DateTime Function() _now;
  final String Function() _eventIdFactory;
  final ReconnectDelay _reconnectDelay;

  final StreamController<ActiveRideRealtimeEvent> _events =
      StreamController<ActiveRideRealtimeEvent>.broadcast();

  ActiveRideSocket? _socket;
  StreamSubscription<Object?>? _socketSubscription;
  String? _rideId;
  bool _shouldReconnect = false;
  bool _reconnectScheduled = false;
  int _generation = 0;
  int _reconnectAttempt = 0;

  @override
  Stream<ActiveRideRealtimeEvent> get events => _events.stream;

  @override
  Future<void> connect(String rideId) async {
    final String normalizedRideId = rideId.trim();
    if (normalizedRideId.isEmpty) {
      throw ArgumentError.value(rideId, 'rideId', 'Ride ID is required.');
    }

    await _disconnectCurrent(emitEvent: false);

    _rideId = normalizedRideId;
    _shouldReconnect = true;
    _reconnectAttempt = 0;
    _generation += 1;
    final int generation = _generation;

    _emitConnection(ActiveRideRealtimeConnectionState.connecting);

    try {
      await _openSocket(generation);
    } catch (_) {
      if (generation == _generation) {
        _shouldReconnect = false;
        _rideId = null;
        _emitConnection(ActiveRideRealtimeConnectionState.disconnected);
      }
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _rideId = null;
    _generation += 1;
    _reconnectScheduled = false;
    await _disconnectCurrent(emitEvent: true);
  }

  @override
  Future<void> sendQuickAction(
    LiveQuickActionKind kind, {
    String? reason,
  }) async {
    final ActiveRideSocket? socket = _socket;
    if (socket == null) {
      throw StateError('Active Ride realtime is not connected.');
    }

    final String? normalizedReason = switch (reason?.trim()) {
      null || '' => null,
      final String value when value.length <= 240 => value,
      _ => throw ArgumentError.value(
        reason,
        'reason',
        'Quick action reason must be at most 240 characters.',
      ),
    };

    socket.send(
      jsonEncode(<String, Object?>{
        'v': protocolVersion,
        'type': 'quick_action.raise',
        'eventId': _eventIdFactory(),
        'sentAt': _now().toUtc().toIso8601String(),
        'payload': <String, Object?>{
          'kind': kind.wireValue,
          'reason': normalizedReason,
        },
      }),
    );
  }

  @override
  Future<void> sendPresence(RideLocationSample sample) async {
    final ActiveRideSocket? socket = _socket;
    if (socket == null) {
      throw StateError('Active Ride realtime is not connected.');
    }

    final Map<String, Object?> event = <String, Object?>{
      'v': protocolVersion,
      'type': 'presence.update',
      'eventId': _eventIdFactory(),
      'sentAt': _now().toUtc().toIso8601String(),
      'payload': <String, Object?>{
        'latitude': sample.latitude,
        'longitude': sample.longitude,
        'observedAt': sample.observedAt.toUtc().toIso8601String(),
        'movement': switch (sample.movement) {
          RideMovementState.moving => 'moving',
          RideMovementState.stopped => 'stopped',
          RideMovementState.unknown => 'unknown',
        },
      },
    };

    socket.send(jsonEncode(event));
  }

  Future<void> _openSocket(int generation) async {
    final String? rideId = _rideId;
    if (!_shouldReconnect || rideId == null || generation != _generation) {
      return;
    }

    final String token = await _authGateway.idToken();
    final ActiveRideSocket socket = await _socketConnector.connect(
      _liveUri(rideId),
      headers: <String, String>{
        'authorization': <String>['Bearer', token].join(' '),
      },
    );

    if (!_shouldReconnect || generation != _generation || rideId != _rideId) {
      await socket.close(1000, 'Connection no longer needed');
      return;
    }

    await _socketSubscription?.cancel();
    _socket = socket;
    _reconnectAttempt = 0;
    _reconnectScheduled = false;

    _socketSubscription = socket.messages.listen(
      _handleMessage,
      onError: (_) {
        _handleUnexpectedDisconnect(generation);
      },
      onDone: () {
        _handleUnexpectedDisconnect(generation);
      },
      cancelOnError: false,
    );

    _emitConnection(ActiveRideRealtimeConnectionState.connected);
  }

  void _handleMessage(Object? raw) {
    if (raw is! String) {
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }

    if (decoded is! Map<String, Object?>) {
      return;
    }

    if (decoded['v'] != protocolVersion) {
      return;
    }

    final Object? type = decoded['type'];
    final Object? rawPayload = decoded['payload'];
    if (rawPayload is! Map<String, Object?>) {
      return;
    }

    if (type == 'ride.snapshot') {
      final Object? rawRideId = rawPayload['rideId'];
      final Object? rawPresences = rawPayload['presences'];
      if (rawRideId is! String || rawPresences is! List<Object?>) {
        return;
      }

      try {
        final List<LiveRiderPresence> presences = rawPresences
            .map((Object? value) {
              if (value is! Map<String, Object?>) {
                throw const FormatException('Invalid Rider presence.');
              }
              return LiveRiderPresence.fromJson(value);
            })
            .toList(growable: false);
        _events.add(
          ActiveRideSnapshotReceived(rideId: rawRideId, presences: presences),
        );
      } on FormatException {
        return;
      }
      return;
    }

    if (type == 'presence.updated') {
      final Object? rawPresence = rawPayload['presence'];
      if (rawPresence is! Map<String, Object?>) {
        return;
      }

      try {
        _events.add(
          ActiveRidePresenceUpdated(
            presence: LiveRiderPresence.fromJson(rawPresence),
          ),
        );
      } on FormatException {
        return;
      }
      return;
    }

    if (type == 'quick_action.raised') {
      try {
        _events.add(
          ActiveRideQuickActionRaised(
            action: LiveQuickAction.fromJson(rawPayload),
          ),
        );
      } on FormatException {
        return;
      }
      return;
    }

    if (type == 'ride.ended') {
      final Object? endedAt = rawPayload['endedAt'];
      if (endedAt is! String) {
        return;
      }

      final DateTime? parsed = DateTime.tryParse(endedAt);
      if (parsed == null) {
        return;
      }

      _events.add(ActiveRideEnded(endedAt: parsed));
      _shouldReconnect = false;
      _rideId = null;
      _generation += 1;
      _reconnectScheduled = false;
      final ActiveRideSocket? socket = _socket;
      _socket = null;
      unawaited(_socketSubscription?.cancel());
      _socketSubscription = null;
      if (socket != null) {
        unawaited(socket.close(1000, 'Ride ended'));
      }
      _emitConnection(ActiveRideRealtimeConnectionState.disconnected);
      return;
    }

    if (type == 'error') {
      final Object? code = rawPayload['code'];
      final Object? message = rawPayload['message'];
      if (code is String && message is String) {
        _events.add(ActiveRideServerError(code: code, message: message));
      }
    }
  }

  void _handleUnexpectedDisconnect(int generation) {
    if (generation != _generation || !_shouldReconnect) {
      return;
    }

    _socket = null;
    _socketSubscription = null;
    _emitConnection(ActiveRideRealtimeConnectionState.disconnected);
    _scheduleReconnect(generation);
  }

  void _scheduleReconnect(int generation) {
    if (_reconnectScheduled ||
        !_shouldReconnect ||
        generation != _generation ||
        _rideId == null) {
      return;
    }

    _reconnectScheduled = true;
    _reconnectAttempt += 1;
    final Duration delay = _reconnectBackoff(_reconnectAttempt);

    unawaited(() async {
      await _reconnectDelay(delay);
      if (!_shouldReconnect || generation != _generation || _rideId == null) {
        _reconnectScheduled = false;
        return;
      }

      _reconnectScheduled = false;
      _emitConnection(ActiveRideRealtimeConnectionState.connecting);

      try {
        await _openSocket(generation);
      } catch (_) {
        _emitConnection(ActiveRideRealtimeConnectionState.disconnected);
        _scheduleReconnect(generation);
      }
    }());
  }

  Future<void> _disconnectCurrent({required bool emitEvent}) async {
    final StreamSubscription<Object?>? subscription = _socketSubscription;
    _socketSubscription = null;
    await subscription?.cancel();

    final ActiveRideSocket? socket = _socket;
    _socket = null;
    if (socket != null) {
      await socket.close(1000, 'Client disconnected');
    }

    if (emitEvent) {
      _emitConnection(ActiveRideRealtimeConnectionState.disconnected);
    }
  }

  Uri _liveUri(String rideId) {
    final Uri httpUri = _apiBaseUrl.resolve(
      '/v1/rides/${Uri.encodeComponent(rideId)}/live',
    );

    final String socketScheme = switch (httpUri.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      'wss' || 'ws' => httpUri.scheme,
      _ => throw StateError(
        'CommRide API base URL must use http, https, ws, or wss.',
      ),
    };

    return httpUri.replace(
      scheme: socketScheme,
      queryParameters: <String, String>{
        ...httpUri.queryParameters,
        'v': '$protocolVersion',
      },
    );
  }

  void _emitConnection(ActiveRideRealtimeConnectionState state) {
    if (!_events.isClosed) {
      _events.add(ActiveRideConnectionChanged(state));
    }
  }

  static Duration _reconnectBackoff(int attempt) {
    if (attempt <= 1) {
      return const Duration(seconds: 1);
    }
    if (attempt == 2) {
      return const Duration(seconds: 2);
    }
    if (attempt == 3) {
      return const Duration(seconds: 5);
    }
    return const Duration(seconds: 10);
  }

  static String _defaultEventId() {
    return '${DateTime.now().microsecondsSinceEpoch}-'
        '${Object().hashCode}';
  }
}
