import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../api/intercom_api.dart';
import 'voice_intercom.dart';

/// Ride intercom over LiveKit Cloud. The CommRide API mints the join token
/// and performs Leader mute; no provider credential lives in the app.
class LiveKitVoiceTransport implements RideVoiceTransport {
  LiveKitVoiceTransport({
    required IntercomApi api,
    MethodChannel serviceChannel = const MethodChannel(
      'commride/intercom_service',
    ),
  }) : _api = api,
       _service = serviceChannel;

  final IntercomApi _api;
  final MethodChannel _service;
  final StreamController<RideVoiceEvent> _events =
      StreamController<RideVoiceEvent>.broadcast();
  final Set<String> _locallyMuted = <String>{};

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  String? _rideId;

  /// What the Rider asked for; a local mute without asking is a Leader mute.
  bool _wantMic = false;
  bool _leaving = false;

  static bool get platformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<RideVoiceEvent> get events => _events.stream;

  @override
  bool get supportsLocalMute => true;

  @override
  Future<void> connect({
    required String rideId,
    required RideVoiceMode mode,
    required bool microphoneEnabled,
  }) async {
    await disconnect();
    final IntercomJoinGrant grant = await _api.requestJoin(rideId);
    final lk.Room room = lk.Room(
      roomOptions: const lk.RoomOptions(
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(
          noiseSuppression: true,
          echoCancellation: true,
          autoGainControl: true,
        ),
        // Silence costs almost no data on Indonesian mobile networks.
        defaultAudioPublishOptions: lk.AudioPublishOptions(dtx: true),
      ),
    );
    _rideId = rideId;
    _room = room;
    _leaving = false;
    _listener = room.createListener()
      ..on<lk.ParticipantConnectedEvent>((_) => _emitParticipants())
      ..on<lk.ParticipantDisconnectedEvent>((_) => _emitParticipants())
      ..on<lk.TrackPublishedEvent>((lk.TrackPublishedEvent event) {
        if (_locallyMuted.contains(event.participant.identity)) {
          unawaited(event.publication.disable());
        }
        _emitParticipants();
      })
      ..on<lk.TrackUnpublishedEvent>((_) => _emitParticipants())
      ..on<lk.TrackMutedEvent>(_onMuted)
      ..on<lk.TrackUnmutedEvent>((_) => _emitParticipants())
      ..on<lk.ActiveSpeakersChangedEvent>((lk.ActiveSpeakersChangedEvent e) {
        _add(
          RideVoiceActiveSpeakersChanged(<String>{
            for (final lk.Participant speaker in e.speakers)
              if (speaker is lk.RemoteParticipant) speaker.identity,
          }),
        );
      })
      ..on<lk.RoomReconnectingEvent>(
        (_) => _add(
          const RideVoiceTransportDegraded('Sinyal lemah, menyambung ulang…'),
        ),
      )
      ..on<lk.RoomReconnectedEvent>(
        (_) => _add(const RideVoiceTransportRecovered()),
      )
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (!_leaving) {
          _add(const RideVoiceTransportClosed('Interkom terputus.'));
          unawaited(_stopService());
        }
      });

    await room.connect(grant.serverUrl, grant.authToken);
    _emitParticipants();
    if (microphoneEnabled) {
      await setMicrophoneEnabled(true);
    }
  }

  @override
  Future<void> disconnect() async {
    final lk.Room? room = _room;
    _room = null;
    _wantMic = false;
    _leaving = true;
    await _listener?.dispose();
    _listener = null;
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
    await _stopService();
  }

  @override
  Future<void> setMode(RideVoiceMode mode) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    final lk.Room? room = _room;
    if (room == null) {
      throw StateError('Intercom is not connected.');
    }
    _wantMic = enabled;
    try {
      await room.localParticipant?.setMicrophoneEnabled(enabled);
    } catch (_) {
      _wantMic = false;
      rethrow;
    }
    if (enabled) {
      // Keeps the microphone working with the screen locked.
      await _invokeService('start');
    }
  }

  @override
  Future<void> setPushToTalkActive(bool active) => setMicrophoneEnabled(active);

  @override
  Future<void> setParticipantAudioEnabled(String riderId, bool enabled) async {
    if (enabled) {
      _locallyMuted.remove(riderId);
    } else {
      _locallyMuted.add(riderId);
    }
    final lk.RemoteParticipant? participant =
        _room?.remoteParticipants[riderId];
    if (participant == null) return;
    for (final lk.RemoteTrackPublication publication
        in participant.audioTrackPublications) {
      await (enabled ? publication.enable() : publication.disable());
    }
  }

  @override
  Future<void> moderatorMute(String riderId) async {
    final String? rideId = _rideId;
    if (rideId == null) return;
    await _api.muteRider(rideId: rideId, riderId: riderId);
  }

  void _onMuted(lk.TrackMutedEvent event) {
    if (event.participant is lk.LocalParticipant) {
      if (_wantMic) {
        // The Rider did not ask for this: the Leader muted them.
        _wantMic = false;
        _add(const RideVoiceModeratorMutedChanged(muted: true));
      }
      return;
    }
    _emitParticipants();
  }

  void _emitParticipants() {
    final lk.Room? room = _room;
    if (room == null) return;
    _add(
      RideVoiceParticipantsChanged(<RideVoiceParticipant>[
        for (final lk.RemoteParticipant participant
            in room.remoteParticipants.values)
          RideVoiceParticipant(
            riderId: participant.identity,
            name: participant.name.isEmpty
                ? participant.identity
                : participant.name,
            audioEnabled: participant.hasAudio && !participant.isMuted,
          ),
      ]),
    );
  }

  void _add(RideVoiceEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> _stopService() => _invokeService('stop');

  Future<void> _invokeService(String method) async {
    try {
      await _service.invokeMethod<void>(method);
    } on MissingPluginException {
      // Builds without the service keep foreground-only voice.
    } on PlatformException {
      // Voice continues while the app is visible.
    }
  }
}
