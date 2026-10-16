import 'dart:async';

import 'package:commride_mobile/src/active_ride/voice_intercom.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVoiceTransport implements RideVoiceTransport {
  FakeVoiceTransport({this.supportsLocalMute = true});

  final StreamController<RideVoiceEvent> controller =
      StreamController<RideVoiceEvent>.broadcast();

  @override
  final bool supportsLocalMute;

  RideVoiceMode? mode;
  bool? microphoneEnabled;
  bool pttActive = false;
  int connectCalls = 0;
  bool failConnect = false;
  final Set<String> mutedLocally = <String>{};
  final List<String> moderatorMuted = <String>[];

  @override
  Stream<RideVoiceEvent> get events => controller.stream;

  @override
  Future<void> connect({
    required String rideId,
    required RideVoiceMode mode,
    required bool microphoneEnabled,
  }) async {
    connectCalls += 1;
    if (failConnect) throw StateError('offline');
    this.mode = mode;
    this.microphoneEnabled = microphoneEnabled;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> moderatorMute(String riderId) async {
    moderatorMuted.add(riderId);
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    microphoneEnabled = enabled;
  }

  @override
  Future<void> setMode(RideVoiceMode mode) async {
    this.mode = mode;
  }

  @override
  Future<void> setParticipantAudioEnabled(String riderId, bool enabled) async {
    if (enabled) {
      mutedLocally.remove(riderId);
    } else {
      mutedLocally.add(riderId);
    }
  }

  @override
  Future<void> setPushToTalkActive(bool active) async {
    pttActive = active;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeVoiceTransport transport;

  setUp(() => transport = FakeVoiceTransport());
  tearDown(() => transport.controller.close());

  RideVoiceController create({bool canModerate = false}) => RideVoiceController(
    rideId: 'ride-1',
    transport: transport,
    canModerate: canModerate,
    pushToTalkLimit: const Duration(milliseconds: 50),
    speakerHold: const Duration(milliseconds: 50),
  );

  test('joining listens first; the mic needs the Rider own tap', () async {
    final RideVoiceController voice = create();

    await voice.join();

    expect(transport.connectCalls, 1);
    expect(transport.microphoneEnabled, isFalse);
    expect(voice.state.connectionPhase, RideVoiceConnectionPhase.connected);
    expect(voice.state.mode, RideVoiceMode.groupIntercom);
    expect(voice.state.microphoneEnabled, isFalse);
    expect(voice.state.canTransmit, isFalse);

    await voice.toggleMicrophone();
    expect(transport.microphoneEnabled, isTrue);
    expect(voice.state.canTransmit, isTrue);

    await voice.toggleMicrophone();
    expect(transport.microphoneEnabled, isFalse);
    expect(voice.state.canTransmit, isFalse);
    voice.dispose();
  });

  test('a failed join is visible and can be retried', () async {
    final RideVoiceController voice = create();
    transport.failConnect = true;

    await voice.join();
    expect(voice.state.connectionPhase, RideVoiceConnectionPhase.disconnected);
    expect(voice.state.message, 'Interkom belum tersambung.');

    transport.failConnect = false;
    await voice.join();
    expect(voice.state.connectionPhase, RideVoiceConnectionPhase.connected);
    expect(transport.connectCalls, 2);
    voice.dispose();
  });

  test('tap to talk opens one bounded turn', () async {
    final RideVoiceController voice = create();
    await voice.join();

    await voice.setPushToTalkActive(true);
    expect(transport.pttActive, isFalse, reason: 'not in tap-to-talk mode');

    await voice.toggleMicrophone();
    await voice.setMode(RideVoiceMode.pushToTalk);
    expect(
      transport.microphoneEnabled,
      isFalse,
      reason: 'switching mode closes the open mic',
    );
    expect(voice.state.microphoneEnabled, isFalse);

    await voice.togglePushToTalk();
    expect(transport.pttActive, isTrue);
    expect(voice.state.canTransmit, isTrue);

    await voice.togglePushToTalk();
    expect(transport.pttActive, isFalse);

    await voice.togglePushToTalk();
    expect(transport.pttActive, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(transport.pttActive, isFalse, reason: 'turn closes by itself');
    expect(voice.state.pushToTalkActive, isFalse);
    voice.dispose();
  });

  test('listen only never transmits', () async {
    final RideVoiceController voice = create();
    await voice.join();
    await voice.setMode(RideVoiceMode.listenOnly);

    await voice.setMicrophoneEnabled(true);
    await voice.setPushToTalkActive(true);
    expect(voice.state.canTransmit, isFalse);
    expect(transport.microphoneEnabled, isFalse);
    voice.dispose();
  });

  test('Leader mute closes the mic; only the Rider tap reopens it', () async {
    final RideVoiceController voice = create();
    await voice.join();
    await voice.toggleMicrophone();

    transport.controller.add(const RideVoiceModeratorMutedChanged(muted: true));
    await flush();
    expect(voice.state.moderatorMuted, isTrue);
    expect(voice.state.microphoneEnabled, isFalse);

    transport.controller.add(
      const RideVoiceModeratorMutedChanged(muted: false),
    );
    await flush();
    expect(
      voice.state.microphoneEnabled,
      isFalse,
      reason: 'nothing remote turns a mic on',
    );

    transport.controller.add(const RideVoiceModeratorMutedChanged(muted: true));
    await flush();
    await voice.toggleMicrophone();
    expect(voice.state.moderatorMuted, isFalse);
    expect(voice.state.microphoneEnabled, isTrue);
    voice.dispose();
  });

  test('only a Leader can mute someone for everyone', () async {
    final RideVoiceController member = create();
    await member.join();
    await member.moderatorMute('rider-3');
    expect(transport.moderatorMuted, isEmpty);
    member.dispose();

    final RideVoiceController leader = create(canModerate: true);
    await leader.join();
    await leader.moderatorMute('rider-3');
    expect(transport.moderatorMuted, <String>['rider-3']);
    expect(leader.state.locallyMutedRiderIds, isEmpty);
    leader.dispose();
  });

  test('local mute stays local and is off where unsupported', () async {
    final RideVoiceController voice = create();
    await voice.join();
    await voice.setLocalMute('rider-2', true);
    expect(voice.state.locallyMutedRiderIds, contains('rider-2'));
    expect(transport.mutedLocally, contains('rider-2'));
    voice.dispose();

    final FakeVoiceTransport unsupported = FakeVoiceTransport(
      supportsLocalMute: false,
    );
    final RideVoiceController limited = RideVoiceController(
      rideId: 'ride-1',
      transport: unsupported,
      canModerate: false,
    );
    await limited.join();
    await limited.setLocalMute('rider-2', true);
    expect(limited.supportsLocalMute, isFalse);
    expect(limited.state.locallyMutedRiderIds, isEmpty);
    limited.dispose();
    await unsupported.controller.close();
  });

  test(
    'speaker shows briefly; participants and reconnects follow events',
    () async {
      final RideVoiceController voice = create();
      await voice.join();

      transport.controller
        ..add(
          const RideVoiceParticipantsChanged(<RideVoiceParticipant>[
            RideVoiceParticipant(
              riderId: 'rider-2',
              name: 'Sweep',
              audioEnabled: true,
            ),
          ]),
        )
        ..add(const RideVoiceActiveSpeakersChanged(<String>{'rider-2'}));
      await flush();
      expect(voice.state.participants.single.name, 'Sweep');
      expect(voice.state.activeSpeakerRiderIds, <String>{'rider-2'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(voice.state.activeSpeakerRiderIds, isEmpty);

      transport.controller.add(const RideVoiceTransportDegraded('lemah'));
      await flush();
      expect(voice.state.connectionPhase, RideVoiceConnectionPhase.degraded);
      transport.controller.add(const RideVoiceTransportRecovered());
      await flush();
      expect(voice.state.connectionPhase, RideVoiceConnectionPhase.connected);

      transport.controller.add(const RideVoiceTransportClosed('ditutup'));
      await flush();
      expect(
        voice.state.connectionPhase,
        RideVoiceConnectionPhase.disconnected,
      );
      expect(voice.state.message, 'ditutup');
      voice.dispose();
    },
  );
}
