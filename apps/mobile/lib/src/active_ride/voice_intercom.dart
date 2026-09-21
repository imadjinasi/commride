import 'dart:async';

import 'package:flutter/foundation.dart';

enum RideVoiceMode {
  groupIntercom,
  pushToTalk,
  listenOnly;

  String get label {
    return switch (this) {
      RideVoiceMode.groupIntercom => 'Group Intercom',
      RideVoiceMode.pushToTalk => 'Push to Talk',
      RideVoiceMode.listenOnly => 'Listen Only',
    };
  }
}

enum RideVoiceConnectionPhase { disconnected, connecting, connected, degraded }

sealed class RideVoiceEvent {
  const RideVoiceEvent();
}

class RideVoiceActiveSpeakersChanged extends RideVoiceEvent {
  const RideVoiceActiveSpeakersChanged(this.riderIds);

  final Set<String> riderIds;
}

class RideVoiceModeratorMutedChanged extends RideVoiceEvent {
  const RideVoiceModeratorMutedChanged({required this.muted});

  final bool muted;
}

class RideVoiceTransportDegraded extends RideVoiceEvent {
  const RideVoiceTransportDegraded(this.message);

  final String message;
}

abstract interface class RideVoiceTransport {
  Stream<RideVoiceEvent> get events;

  Future<void> connect({
    required String rideId,
    required RideVoiceMode mode,
    required bool microphoneEnabled,
  });

  Future<void> disconnect();

  Future<void> setMode(RideVoiceMode mode);

  Future<void> setMicrophoneEnabled(bool enabled);

  Future<void> setPushToTalkActive(bool active);

  Future<void> setParticipantAudioEnabled(String riderId, bool enabled);

  Future<void> moderatorMute(String riderId);
}

class RideVoiceState {
  const RideVoiceState({
    required this.connectionPhase,
    required this.mode,
    required this.microphoneEnabled,
    required this.moderatorMuted,
    required this.pushToTalkActive,
    required this.locallyMutedRiderIds,
    required this.activeSpeakerRiderIds,
    required this.message,
  });

  const RideVoiceState.initial()
    : connectionPhase = RideVoiceConnectionPhase.disconnected,
      mode = RideVoiceMode.groupIntercom,
      microphoneEnabled = false,
      moderatorMuted = false,
      pushToTalkActive = false,
      locallyMutedRiderIds = const <String>{},
      activeSpeakerRiderIds = const <String>{},
      message = null;

  final RideVoiceConnectionPhase connectionPhase;
  final RideVoiceMode mode;

  /// True only after the Rider has explicitly joined/enabled their microphone.
  final bool microphoneEnabled;

  /// Server/media moderation may disable transmit. It never grants remote unmute.
  final bool moderatorMuted;
  final bool pushToTalkActive;
  final Set<String> locallyMutedRiderIds;
  final Set<String> activeSpeakerRiderIds;
  final String? message;

  bool get canTransmit =>
      connectionPhase == RideVoiceConnectionPhase.connected &&
      mode != RideVoiceMode.listenOnly &&
      microphoneEnabled &&
      !moderatorMuted;

  RideVoiceState copyWith({
    RideVoiceConnectionPhase? connectionPhase,
    RideVoiceMode? mode,
    bool? microphoneEnabled,
    bool? moderatorMuted,
    bool? pushToTalkActive,
    Set<String>? locallyMutedRiderIds,
    Set<String>? activeSpeakerRiderIds,
    String? message,
    bool clearMessage = false,
  }) {
    return RideVoiceState(
      connectionPhase: connectionPhase ?? this.connectionPhase,
      mode: mode ?? this.mode,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      moderatorMuted: moderatorMuted ?? this.moderatorMuted,
      pushToTalkActive: pushToTalkActive ?? this.pushToTalkActive,
      locallyMutedRiderIds: locallyMutedRiderIds ?? this.locallyMutedRiderIds,
      activeSpeakerRiderIds:
          activeSpeakerRiderIds ?? this.activeSpeakerRiderIds,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class RideVoiceController extends ChangeNotifier {
  RideVoiceController({
    required String rideId,
    required RideVoiceTransport transport,
    required bool canModerate,
  }) : _rideId = rideId,
       _transport = transport,
       _canModerate = canModerate {
    if (rideId.trim().isEmpty) {
      throw ArgumentError.value(rideId, 'rideId', 'Ride ID is required.');
    }
  }

  final String _rideId;
  final RideVoiceTransport _transport;
  final bool _canModerate;

  RideVoiceState _state = const RideVoiceState.initial();
  StreamSubscription<RideVoiceEvent>? _subscription;
  bool _disposed = false;

  RideVoiceState get state => _state;

  /// Joining voice is explicit. Once joined, Group Intercom is the default and
  /// the local microphone starts enabled unless the Rider chooses otherwise.
  Future<void> join({bool microphoneEnabled = true}) async {
    if (_disposed ||
        _state.connectionPhase == RideVoiceConnectionPhase.connected ||
        _state.connectionPhase == RideVoiceConnectionPhase.connecting) {
      return;
    }

    _subscription ??= _transport.events.listen(_handleEvent);
    _setState(
      _state.copyWith(
        connectionPhase: RideVoiceConnectionPhase.connecting,
        mode: RideVoiceMode.groupIntercom,
        microphoneEnabled: microphoneEnabled,
        pushToTalkActive: false,
        clearMessage: true,
      ),
    );

    try {
      await _transport.connect(
        rideId: _rideId,
        mode: RideVoiceMode.groupIntercom,
        microphoneEnabled: microphoneEnabled,
      );
      _setState(
        _state.copyWith(
          connectionPhase: RideVoiceConnectionPhase.connected,
          clearMessage: true,
        ),
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          connectionPhase: RideVoiceConnectionPhase.disconnected,
          microphoneEnabled: false,
          message: 'Interkom Ride belum dapat dihubungkan.',
        ),
      );
    }
  }

  Future<void> leave() async {
    if (_disposed) return;
    try {
      await _transport.disconnect();
    } finally {
      _setState(const RideVoiceState.initial());
    }
  }

  Future<void> setMode(RideVoiceMode mode) async {
    if (_disposed ||
        _state.connectionPhase != RideVoiceConnectionPhase.connected) {
      return;
    }

    if (mode == RideVoiceMode.listenOnly && _state.microphoneEnabled) {
      await _transport.setMicrophoneEnabled(false);
    }
    if (_state.pushToTalkActive) {
      await _transport.setPushToTalkActive(false);
    }

    await _transport.setMode(mode);
    _setState(
      _state.copyWith(
        mode: mode,
        microphoneEnabled: mode == RideVoiceMode.listenOnly
            ? false
            : _state.microphoneEnabled,
        pushToTalkActive: false,
        clearMessage: true,
      ),
    );
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_disposed ||
        _state.connectionPhase != RideVoiceConnectionPhase.connected) {
      return;
    }
    if (enabled &&
        (_state.mode == RideVoiceMode.listenOnly || _state.moderatorMuted)) {
      return;
    }

    await _transport.setMicrophoneEnabled(enabled);
    _setState(
      _state.copyWith(
        microphoneEnabled: enabled,
        pushToTalkActive: enabled ? _state.pushToTalkActive : false,
        clearMessage: true,
      ),
    );
  }

  Future<void> toggleMicrophone() =>
      setMicrophoneEnabled(!_state.microphoneEnabled);

  Future<void> setPushToTalkActive(bool active) async {
    if (_disposed ||
        _state.connectionPhase != RideVoiceConnectionPhase.connected ||
        _state.mode != RideVoiceMode.pushToTalk ||
        _state.moderatorMuted) {
      return;
    }

    await _transport.setPushToTalkActive(active);
    _setState(_state.copyWith(pushToTalkActive: active, clearMessage: true));
  }

  Future<void> setLocalMute(String riderId, bool muted) async {
    if (_disposed || riderId.trim().isEmpty) return;

    await _transport.setParticipantAudioEnabled(riderId, !muted);
    final Set<String> next = <String>{..._state.locallyMutedRiderIds};
    if (muted) {
      next.add(riderId);
    } else {
      next.remove(riderId);
    }
    _setState(
      _state.copyWith(
        locallyMutedRiderIds: Set<String>.unmodifiable(next),
        clearMessage: true,
      ),
    );
  }

  Future<void> moderatorMute(String riderId) async {
    if (_disposed || !_canModerate || riderId.trim().isEmpty) {
      return;
    }
    await _transport.moderatorMute(riderId);
  }

  void _handleEvent(RideVoiceEvent event) {
    if (_disposed) return;

    switch (event) {
      case RideVoiceActiveSpeakersChanged():
        _setState(
          _state.copyWith(
            activeSpeakerRiderIds: Set<String>.unmodifiable(event.riderIds),
          ),
        );
      case RideVoiceModeratorMutedChanged():
        _setState(
          _state.copyWith(
            moderatorMuted: event.muted,
            microphoneEnabled: event.muted ? false : _state.microphoneEnabled,
            pushToTalkActive: event.muted ? false : _state.pushToTalkActive,
          ),
        );
      case RideVoiceTransportDegraded():
        _setState(
          _state.copyWith(
            connectionPhase: RideVoiceConnectionPhase.degraded,
            message: event.message,
          ),
        );
    }
  }

  void _setState(RideVoiceState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    unawaited(_transport.disconnect());
    super.dispose();
  }
}
