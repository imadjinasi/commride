import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/ride_sos_api.dart';
import '../models/ride_sos.dart';
import 'realtime_client.dart';

class FailedRideSosRaise {
  const FailedRideSosRaise({
    required this.clientCommandId,
    required this.reason,
  });

  final String clientCommandId;
  final String? reason;
}

class RideSosViewState {
  const RideSosViewState({
    required this.items,
    required this.loading,
    required this.working,
    required this.rideEnded,
    required this.failedRaise,
    required this.errorMessage,
  });

  const RideSosViewState.initial({bool readOnly = false})
    : items = const <RideSos>[],
      loading = false,
      working = false,
      rideEnded = readOnly,
      failedRaise = null,
      errorMessage = null;

  final List<RideSos> items;
  final bool loading;
  final bool working;
  final bool rideEnded;
  final FailedRideSosRaise? failedRaise;
  final String? errorMessage;

  List<RideSos> get activeItems => items
      .where((RideSos item) => item.status == RideSosStatus.active)
      .toList(growable: false);

  RideSosViewState copyWith({
    List<RideSos>? items,
    bool? loading,
    bool? working,
    bool? rideEnded,
    FailedRideSosRaise? failedRaise,
    bool clearFailedRaise = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RideSosViewState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      working: working ?? this.working,
      rideEnded: rideEnded ?? this.rideEnded,
      failedRaise: clearFailedRaise ? null : (failedRaise ?? this.failedRaise),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class RideSosController extends ChangeNotifier {
  RideSosController({
    required String rideId,
    required RideSosApi api,
    ActiveRideRealtimeClient? realtimeClient,
    String Function()? clientCommandIdFactory,
    bool readOnly = false,
  }) : _rideId = rideId,
       _api = api,
       _realtimeClient = realtimeClient,
       _clientCommandIdFactory =
           clientCommandIdFactory ?? _defaultClientCommandId,
       _state = RideSosViewState.initial(readOnly: readOnly) {
    if (rideId.trim().isEmpty) {
      throw ArgumentError.value(rideId, 'rideId', 'Ride ID is required.');
    }
  }

  final String _rideId;
  final RideSosApi _api;
  final ActiveRideRealtimeClient? _realtimeClient;
  final String Function() _clientCommandIdFactory;

  RideSosViewState _state;
  StreamSubscription<ActiveRideRealtimeEvent>? _realtimeSubscription;
  bool _disposed = false;

  RideSosViewState get state => _state;

  void start() {
    if (_disposed || _realtimeSubscription != null) {
      return;
    }
    final ActiveRideRealtimeClient? client = _realtimeClient;
    if (client == null) {
      return;
    }
    _realtimeSubscription = client.events.listen(_handleRealtimeEvent);
  }

  Future<void> load() async {
    if (_disposed || _state.loading) {
      return;
    }
    _setState(_state.copyWith(loading: true, clearError: true));
    try {
      final List<RideSos> items = await _api.fetchSos(_rideId);
      _setState(
        _state.copyWith(
          items: _sortedUnique(items),
          loading: false,
          clearError: true,
        ),
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          loading: false,
          errorMessage: 'Status SOS belum dapat dimuat.',
        ),
      );
    }
  }

  Future<void> raise(String? reason) {
    final String? normalized = _normalizeReason(reason);
    return _raise(
      clientCommandId: _clientCommandIdFactory(),
      reason: normalized,
    );
  }

  Future<void> retryFailedRaise() async {
    final FailedRideSosRaise? failed = _state.failedRaise;
    if (failed == null) {
      return;
    }
    await _raise(
      clientCommandId: failed.clientCommandId,
      reason: failed.reason,
    );
  }

  Future<void> cancel(String sosId) async {
    await _mutate(
      () => _api.cancelSos(rideId: _rideId, sosId: sosId),
      failureMessage: 'SOS belum dapat dibatalkan.',
    );
  }

  Future<void> resolve(String sosId) async {
    await _mutate(
      () => _api.resolveSos(rideId: _rideId, sosId: sosId),
      failureMessage: 'SOS belum dapat diselesaikan.',
    );
  }

  void clearError() {
    _setState(_state.copyWith(clearError: true));
  }

  Future<void> _raise({
    required String clientCommandId,
    required String? reason,
  }) async {
    if (_disposed) {
      return;
    }
    if (_state.rideEnded) {
      throw StateError('SOS is read-only after Ride end.');
    }
    if (_state.working) {
      return;
    }

    _setState(
      _state.copyWith(working: true, clearFailedRaise: true, clearError: true),
    );

    try {
      final RideSos created = await _api.raiseSos(
        rideId: _rideId,
        clientCommandId: clientCommandId,
        reason: reason,
      );
      _setState(
        _state.copyWith(
          items: _sortedUnique(<RideSos>[..._state.items, created]),
          working: false,
          clearFailedRaise: true,
          clearError: true,
        ),
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          working: false,
          failedRaise: FailedRideSosRaise(
            clientCommandId: clientCommandId,
            reason: reason,
          ),
          errorMessage: 'SOS belum berhasil dikirim ke grup Ride.',
        ),
      );
      rethrow;
    }
  }

  Future<void> _mutate(
    Future<RideSos> Function() action, {
    required String failureMessage,
  }) async {
    if (_disposed || _state.working) {
      return;
    }
    if (_state.rideEnded) {
      throw StateError('SOS is read-only after Ride end.');
    }

    _setState(_state.copyWith(working: true, clearError: true));
    try {
      final RideSos updated = await action();
      _setState(
        _state.copyWith(
          items: _sortedUnique(<RideSos>[..._state.items, updated]),
          working: false,
          clearError: true,
        ),
      );
    } catch (_) {
      _setState(_state.copyWith(working: false, errorMessage: failureMessage));
      rethrow;
    }
  }

  void _handleRealtimeEvent(ActiveRideRealtimeEvent event) {
    if (_disposed) {
      return;
    }
    if (event is ActiveRideSosChanged && event.sos.rideId == _rideId) {
      _setState(
        _state.copyWith(
          items: _sortedUnique(<RideSos>[..._state.items, event.sos]),
        ),
      );
      return;
    }
    if (event is ActiveRideEnded) {
      _setState(_state.copyWith(rideEnded: true));
    }
  }

  List<RideSos> _sortedUnique(Iterable<RideSos> values) {
    final Map<String, RideSos> byId = <String, RideSos>{};
    for (final RideSos item in values) {
      byId[item.id] = item;
    }

    final List<RideSos> sorted = byId.values.toList(growable: false)
      ..sort((RideSos a, RideSos b) {
        final int time = b.raisedAt.compareTo(a.raisedAt);
        return time != 0 ? time : b.id.compareTo(a.id);
      });
    return List<RideSos>.unmodifiable(sorted);
  }

  String? _normalizeReason(String? reason) {
    if (reason == null) {
      return null;
    }
    final String normalized = reason.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.runes.length > 500) {
      throw ArgumentError.value(
        reason,
        'reason',
        'SOS reason must be at most 500 characters.',
      );
    }
    return normalized;
  }

  void _setState(RideSosViewState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
    super.dispose();
  }

  static String _defaultClientCommandId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${Object().hashCode}';
  }
}
