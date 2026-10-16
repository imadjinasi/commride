import 'dart:async';

import 'package:flutter/foundation.dart';

enum RideVoiceMode {
  /// Open mic: once switched on the microphone stays on until turned off.
  groupIntercom,

  /// Tap to talk: each tap opens the microphone for one bounded turn.
  pushToTalk,
  listenOnly;

  String get label {
    return switch (this) {
      RideVoiceMode.groupIntercom => 'Mic aktif terus',
      RideVoiceMode.pushToTalk => 'Tap untuk bicara',
      RideVoiceMode.listenOnly => 'Dengar saja',
    };
  }
}

enum RideVoiceConnectionPhase { disconnected, connecting, connected, degraded }

class RideVoiceParticipant {
  const RideVoiceParticipant({
    required this.riderId,
    required this.name,
    required this.audioEnabled,
  });

  final String riderId;
  final String name;

  /// Whether this Rider's microphone is currently transmitting to the room.
  final bool audioEnabled;
}

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

/// The media connection recovered after a degraded period.
class RideVoiceTransportRecovered extends RideVoiceEvent {
  const RideVoiceTransportRecovered();
}

/// The room closed underneath the Rider (Ride ended, removed, fatal error).
class RideVoiceTransportClosed extends RideVoiceEvent {
  const RideVoiceTransportClosed(this.message);

  final String message;
}

class RideVoiceParticipantsChanged extends RideVoiceEvent {
  const RideVoiceParticipantsChanged(this.participants);

  final List<RideVoiceParticipant> participants;
}

abstract interface class RideVoiceTransport {
  Stream<RideVoiceEvent> get events;

  /// Whether one Rider can be silenced only for this listener. Providers
  /// that cannot do this keep the control hidden instead of faking it.
  bool get supportsLocalMute;

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
    required this.participants,
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
      participants = const <RideVoiceParticipant>[],
      message = null;

  final RideVoiceConnectionPhase connectionPhase;
  final RideVoiceMode mode;

  /// True only after the Rider has explicitly enabled their microphone.
  final bool microphoneEnabled;

  /// The Leader silenced this Rider. It never turns a microphone back on;
  /// only the Rider's own tap does.
  final bool moderatorMuted;
  final bool pushToTalkActive;
  final Set<String> locallyMutedRiderIds;
  final Set<String> activeSpeakerRiderIds;
  final List<RideVoiceParticipant> participants;
  final String? message;

  bool get connected =>
      connectionPhase == RideVoiceConnectionPhase.connected ||
      connectionPhase == RideVoiceConnectionPhase.degraded;

  bool get canTransmit =>
      connectionPhase == RideVoiceConnectionPhase.connected &&
      !moderatorMuted &&
      switch (mode) {
        RideVoiceMode.groupIntercom => microphoneEnabled,
        RideVoiceMode.pushToTalk => pushToTalkActive,
        RideVoiceMode.listenOnly => false,
      };

  RideVoiceState copyWith({
    RideVoiceConnectionPhase? connectionPhase,
    RideVoiceMode? mode,
    bool? microphoneEnabled,
    bool? moderatorMuted,
    bool? pushToTalkActive,
    Set<String>? locallyMutedRiderIds,
    Set<String>? activeSpeakerRiderIds,
    List<RideVoiceParticipant>? participants,
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
      participants: participants ?? this.participants,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class RideVoiceController extends ChangeNotifier {
  RideVoiceController({
    required String rideId,
    required RideVoiceTransport transport,
    required bool canModerate,
    this.pushToTalkLimit = const Duration(seconds: 30),
    this.speakerHold = const Duration(seconds: 3),
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

  /// A tap-to-talk turn closes by itself so a forgotten tap never leaves the
  /// microphone open for the rest of the Ride.
  final Duration pushToTalkLimit;

  /// How long a speaker stays shown after the provider's last speech signal.
  final Duration speakerHold;

  RideVoiceState _state = const RideVoiceState.initial();
  StreamSubscription<RideVoiceEvent>? _subscription;
  Timer? _pushToTalkTimer;
  Timer? _speakerTimer;
  bool _disposed = false;

  RideVoiceState get state => _state;
  bool get canModerate => _canModerate;
  bool get supportsLocalMute => _transport.supportsLocalMute;

  /// Joining is explicit and starts listening only: the microphone turns on
  /// with the Rider's own tap, never as a side effect of joining.
  Future<void> join({bool microphoneEnabled = false}) async {
    if (_disposed ||
        _state.connectionPhase == RideVoiceConnectionPhase.connected ||
        _state.connectionPhase == RideVoiceConnectionPhase.connecting) {
      return;
    }

    _subscription ??= _transport.events.listen(_handleEvent);
    _setState(
      _state.copyWith(
        connectionPhase: RideVoiceConnectionPhase.connecting,
        microphoneEnabled: microphoneEnabled,
        pushToTalkActive: false,
        moderatorMuted: false,
        clearMessage: true,
      ),
    );

    try {
      await _transport.connect(
        rideId: _rideId,
        mode: _state.mode,
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
          message: 'Interkom belum tersambung.',
        ),
      );
    }
  }

  Future<void> leave() async {
    if (_disposed) return;
    _pushToTalkTimer?.cancel();
    _speakerTimer?.cancel();
    try {
      await _transport.disconnect();
    } finally {
      _setState(const RideVoiceState.initial().copyWith(mode: _state.mode));
    }
  }

  /// Switching mode always closes the microphone; the Rider opens it again
  /// deliberately in the new mode.
  Future<void> setMode(RideVoiceMode mode) async {
    if (_disposed || mode == _state.mode) {
      return;
    }
    if (!_state.connected) {
      _setState(_state.copyWith(mode: mode));
      return;
    }

    _pushToTalkTimer?.cancel();
    if (_state.microphoneEnabled || _state.pushToTalkActive) {
      await _transport.setMicrophoneEnabled(false);
    }
    await _transport.setMode(mode);
    _setState(
      _state.copyWith(
        mode: mode,
        microphoneEnabled: false,
        pushToTalkActive: false,
        clearMessage: true,
      ),
    );
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    if (_disposed || !_state.connected) {
      return;
    }
    if (enabled && _state.mode != RideVoiceMode.groupIntercom) {
      return;
    }

    try {
      await _transport.setMicrophoneEnabled(enabled);
    } catch (_) {
      _setState(
        _state.copyWith(
          microphoneEnabled: false,
          message: enabled ? 'Mikrofon belum bisa dinyalakan.' : null,
        ),
      );
      return;
    }
    _setState(
      _state.copyWith(
        microphoneEnabled: enabled,
        // The Rider's own tap is the only way back after a Leader mute.
        moderatorMuted: enabled ? false : _state.moderatorMuted,
        clearMessage: true,
      ),
    );
  }

  Future<void> toggleMicrophone() =>
      setMicrophoneEnabled(!_state.microphoneEnabled);

  /// Tap to talk: opens the microphone for one turn of at most
  /// [pushToTalkLimit]; a second tap closes it earlier.
  Future<void> setPushToTalkActive(bool active) async {
    if (_disposed ||
        !_state.connected ||
        _state.mode != RideVoiceMode.pushToTalk ||
        active == _state.pushToTalkActive) {
      return;
    }

    _pushToTalkTimer?.cancel();
    try {
      await _transport.setPushToTalkActive(active);
    } catch (_) {
      _setState(
        _state.copyWith(
          pushToTalkActive: false,
          message: active ? 'Mikrofon belum bisa dinyalakan.' : null,
        ),
      );
      return;
    }
    if (active) {
      _pushToTalkTimer = Timer(
        pushToTalkLimit,
        () => unawaited(setPushToTalkActive(false)),
      );
    }
    _setState(
      _state.copyWith(
        pushToTalkActive: active,
        moderatorMuted: active ? false : _state.moderatorMuted,
        clearMessage: true,
      ),
    );
  }

  Future<void> togglePushToTalk() =>
      setPushToTalkActive(!_state.pushToTalkActive);

  Future<void> setLocalMute(String riderId, bool muted) async {
    if (_disposed || riderId.trim().isEmpty || !supportsLocalMute) return;

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

  /// Leader only: stops a Rider transmitting to everyone. It can never turn
  /// anyone's microphone on.
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
        _speakerTimer?.cancel();
        if (event.riderIds.isNotEmpty) {
          _speakerTimer = Timer(speakerHold, () {
            _setState(_state.copyWith(activeSpeakerRiderIds: const <String>{}));
          });
        }
        _setState(
          _state.copyWith(
            activeSpeakerRiderIds: Set<String>.unmodifiable(event.riderIds),
          ),
        );
      case RideVoiceModeratorMutedChanged():
        if (event.muted) _pushToTalkTimer?.cancel();
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
      case RideVoiceTransportRecovered():
        if (_state.connectionPhase == RideVoiceConnectionPhase.degraded) {
          _setState(
            _state.copyWith(
              connectionPhase: RideVoiceConnectionPhase.connected,
              clearMessage: true,
            ),
          );
        }
      case RideVoiceTransportClosed():
        _pushToTalkTimer?.cancel();
        _speakerTimer?.cancel();
        _setState(
          const RideVoiceState.initial().copyWith(
            mode: _state.mode,
            message: event.message,
          ),
        );
      case RideVoiceParticipantsChanged():
        _setState(
          _state.copyWith(
            participants: List<RideVoiceParticipant>.unmodifiable(
              event.participants,
            ),
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
    _pushToTalkTimer?.cancel();
    _speakerTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_transport.disconnect());
    super.dispose();
  }
}
