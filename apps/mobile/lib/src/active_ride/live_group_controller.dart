import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/club_ride.dart';
import 'live_group_models.dart';
import 'realtime_client.dart';

const int defaultLiveQuickActionLimit = 20;

class ActiveRideGroupCounts {
  const ActiveRideGroupCounts({
    required this.live,
    required this.stale,
    required this.offline,
  });

  final int live;
  final int stale;
  final int offline;

  int get total => live + stale + offline;
}

class ActiveRideGroupState {
  const ActiveRideGroupState({
    required this.connectionState,
    required this.presences,
    required this.quickActions,
    required this.endedAt,
    required this.latestError,
  });

  const ActiveRideGroupState.initial()
    : connectionState = ActiveRideRealtimeConnectionState.disconnected,
      presences = const <LiveRiderPresence>[],
      quickActions = const <LiveQuickAction>[],
      endedAt = null,
      latestError = null;

  final ActiveRideRealtimeConnectionState connectionState;
  final List<LiveRiderPresence> presences;
  final List<LiveQuickAction> quickActions;
  final DateTime? endedAt;
  final ActiveRideServerError? latestError;

  bool get hasEnded => endedAt != null;

  ActiveRideGroupCounts counts(
    DateTime now, {
    Duration liveWindow = livePresenceFreshnessWindow,
  }) {
    int live = 0;
    int stale = 0;
    int offline = 0;

    for (final LiveRiderPresence presence in presences) {
      switch (presence.effectiveFreshness(now, liveWindow: liveWindow)) {
        case LivePresenceFreshness.live:
          live += 1;
        case LivePresenceFreshness.stale:
          stale += 1;
        case LivePresenceFreshness.offline:
          offline += 1;
      }
    }

    return ActiveRideGroupCounts(
      live: live,
      stale: stale,
      offline: offline,
    );
  }

  ActiveRideGroupState copyWith({
    ActiveRideRealtimeConnectionState? connectionState,
    List<LiveRiderPresence>? presences,
    List<LiveQuickAction>? quickActions,
    DateTime? endedAt,
    bool clearEndedAt = false,
    ActiveRideServerError? latestError,
    bool clearLatestError = false,
  }) {
    return ActiveRideGroupState(
      connectionState: connectionState ?? this.connectionState,
      presences: presences ?? this.presences,
      quickActions: quickActions ?? this.quickActions,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      latestError: clearLatestError
          ? null
          : (latestError ?? this.latestError),
    );
  }
}

class ActiveRideGroupController extends ChangeNotifier {
  ActiveRideGroupController({
    required String rideId,
    required ActiveRideRealtimeClient realtimeClient,
    int quickActionLimit = defaultLiveQuickActionLimit,
  }) : _rideId = rideId,
       _realtimeClient = realtimeClient,
       _quickActionLimit = quickActionLimit {
    if (rideId.trim().isEmpty) {
      throw ArgumentError.value(rideId, 'rideId', 'Ride ID is required.');
    }
    if (quickActionLimit <= 0) {
      throw ArgumentError.value(
        quickActionLimit,
        'quickActionLimit',
        'Quick action limit must be positive.',
      );
    }
  }

  final String _rideId;
  final ActiveRideRealtimeClient _realtimeClient;
  final int _quickActionLimit;

  ActiveRideGroupState _state = const ActiveRideGroupState.initial();
  StreamSubscription<ActiveRideRealtimeEvent>? _subscription;
  bool _disposed = false;

  ActiveRideGroupState get state => _state;

  void start() {
    if (_disposed || _subscription != null) {
      return;
    }

    _subscription = _realtimeClient.events.listen(_handleEvent);
  }

  void refreshFreshness() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  void _handleEvent(ActiveRideRealtimeEvent event) {
    if (_disposed) {
      return;
    }

    if (event is ActiveRideConnectionChanged) {
      _setState(_state.copyWith(connectionState: event.state));
      return;
    }

    if (event is ActiveRideSnapshotReceived) {
      if (event.rideId != _rideId) {
        return;
      }
      _setState(
        _state.copyWith(
          presences: _sortedPresences(event.presences),
          clearLatestError: true,
        ),
      );
      return;
    }

    if (event is ActiveRidePresenceUpdated) {
      final Map<String, LiveRiderPresence> byRider =
          <String, LiveRiderPresence>{
            for (final LiveRiderPresence presence in _state.presences)
              presence.riderId: presence,
          };
      final LiveRiderPresence? current =
          byRider[event.presence.riderId];

      if (current != null &&
          event.presence.observedAt.isBefore(current.observedAt)) {
        return;
      }

      byRider[event.presence.riderId] = event.presence;
      _setState(
        _state.copyWith(
          presences: _sortedPresences(byRider.values),
          clearLatestError: true,
        ),
      );
      return;
    }

    if (event is ActiveRideQuickActionRaised) {
      if (_state.quickActions.any(
        (LiveQuickAction action) =>
            action.eventId == event.action.eventId,
      )) {
        return;
      }

      final List<LiveQuickAction> actions = <LiveQuickAction>[
        event.action,
        ..._state.quickActions,
      ]..sort(
          (LiveQuickAction a, LiveQuickAction b) =>
              b.raisedAt.compareTo(a.raisedAt),
        );

      _setState(
        _state.copyWith(
          quickActions: actions
              .take(_quickActionLimit)
              .toList(growable: false),
          clearLatestError: true,
        ),
      );
      return;
    }

    if (event is ActiveRideEnded) {
      _setState(
        _state.copyWith(
          endedAt: event.endedAt,
          connectionState:
              ActiveRideRealtimeConnectionState.disconnected,
        ),
      );
      return;
    }

    if (event is ActiveRideServerError) {
      _setState(_state.copyWith(latestError: event));
    }
  }

  List<LiveRiderPresence> _sortedPresences(
    Iterable<LiveRiderPresence> values,
  ) {
    final List<LiveRiderPresence> sorted = values.toList(growable: false)
      ..sort((LiveRiderPresence a, LiveRiderPresence b) {
        final int roleCompare =
            _roleRank(a.role).compareTo(_roleRank(b.role));
        if (roleCompare != 0) {
          return roleCompare;
        }

        final int nameCompare = a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
        if (nameCompare != 0) {
          return nameCompare;
        }

        return a.riderId.compareTo(b.riderId);
      });

    return List<LiveRiderPresence>.unmodifiable(sorted);
  }

  int _roleRank(RideRole role) {
    return switch (role) {
      RideRole.leader => 0,
      RideRole.sweeper => 1,
      RideRole.navigator => 2,
      RideRole.member => 3,
    };
  }

  void _setState(ActiveRideGroupState next) {
    if (_disposed) {
      return;
    }

    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
