import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/intercom_api.dart';
import 'voice_intercom.dart';

/// Ride intercom over Cloudflare RealtimeKit through CommRide's own Android
/// bridge (the RealtimeKit Flutter SDK was discontinued). The CommRide API
/// mints the join token; no provider credential lives in the app.
class RealtimeKitVoiceTransport implements RideVoiceTransport {
  RealtimeKitVoiceTransport({
    required IntercomApi api,
    MethodChannel methodChannel = const MethodChannel('commride/intercom'),
    EventChannel eventChannel = const EventChannel('commride/intercom/events'),
  }) : _api = api,
       _methods = methodChannel,
       _eventChannel = eventChannel;

  final IntercomApi _api;
  final MethodChannel _methods;
  final EventChannel _eventChannel;
  final StreamController<RideVoiceEvent> _events =
      StreamController<RideVoiceEvent>.broadcast();
  StreamSubscription<Object?>? _nativeEvents;

  static bool get platformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Stream<RideVoiceEvent> get events => _events.stream;

  /// RealtimeKit exposes no per-listener volume for one participant.
  @override
  bool get supportsLocalMute => false;

  @override
  Future<void> connect({
    required String rideId,
    required RideVoiceMode mode,
    required bool microphoneEnabled,
  }) async {
    final IntercomJoinGrant grant = await _api.requestJoin(rideId);
    _nativeEvents ??= _eventChannel.receiveBroadcastStream().listen(
      _handleNative,
      onError: (Object _) {},
    );
    await _methods.invokeMethod<void>('join', <String, Object?>{
      'authToken': grant.authToken,
      'baseDomain': grant.baseDomain,
    });
    if (microphoneEnabled) {
      await setMicrophoneEnabled(true);
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _methods.invokeMethod<void>('leave');
    } on MissingPluginException {
      // No native bridge in this build: nothing to leave.
    } on PlatformException {
      // Leaving is best effort; the room ends for this Rider either way.
    }
    await _nativeEvents?.cancel();
    _nativeEvents = null;
  }

  @override
  Future<void> setMode(RideVoiceMode mode) async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    await _methods.invokeMethod<void>('setMicrophoneEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }

  @override
  Future<void> setPushToTalkActive(bool active) => setMicrophoneEnabled(active);

  @override
  Future<void> setParticipantAudioEnabled(String riderId, bool enabled) {
    throw UnsupportedError('RealtimeKit has no per-listener participant mute.');
  }

  @override
  Future<void> moderatorMute(String riderId) async {
    await _methods.invokeMethod<void>('moderatorMute', <String, Object?>{
      'riderId': riderId,
    });
  }

  void _handleNative(Object? raw) {
    final RideVoiceEvent? event = decodeNativeIntercomEvent(raw);
    if (event != null && !_events.isClosed) {
      _events.add(event);
    }
  }
}

/// Maps one bridge event map to a [RideVoiceEvent]; unknown shapes are
/// ignored so an older or newer bridge cannot crash the riding screen.
@visibleForTesting
RideVoiceEvent? decodeNativeIntercomEvent(Object? raw) {
  if (raw is! Map<Object?, Object?>) return null;
  switch (raw['type']) {
    case 'connection':
      return switch (raw['state']) {
        'connected' => const RideVoiceTransportRecovered(),
        'reconnecting' => const RideVoiceTransportDegraded(
          'Sinyal lemah, menyambung ulang…',
        ),
        'ended' => const RideVoiceTransportClosed('Interkom ditutup.'),
        'failed' => const RideVoiceTransportClosed('Interkom terputus.'),
        _ => null,
      };
    case 'speaker':
      final Object? riderId = raw['riderId'];
      return RideVoiceActiveSpeakersChanged(
        riderId is String && riderId.isNotEmpty
            ? <String>{riderId}
            : const <String>{},
      );
    case 'moderatorMuted':
      return const RideVoiceModeratorMutedChanged(muted: true);
    case 'participants':
      final Object? list = raw['participants'];
      if (list is! List<Object?>) return null;
      return RideVoiceParticipantsChanged(<RideVoiceParticipant>[
        for (final Object? item in list)
          if (item is Map<Object?, Object?> &&
              item['riderId'] is String &&
              item['name'] is String)
            RideVoiceParticipant(
              riderId: item['riderId']! as String,
              name: item['name']! as String,
              audioEnabled: item['audioEnabled'] == true,
            ),
      ]);
  }
  return null;
}
