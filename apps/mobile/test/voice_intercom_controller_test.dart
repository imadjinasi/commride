import 'dart:async';

import 'package:commride_mobile/src/active_ride/voice_intercom.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVoiceTransport implements RideVoiceTransport {
  final StreamController<RideVoiceEvent> controller =
      StreamController<RideVoiceEvent>.broadcast();

  RideVoiceMode? mode;
  bool? microphoneEnabled;
  bool pttActive = false;
  int connectCalls = 0;
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

void main() {
  test('explicit join defaults to always-connected group intercom', () async {
    final FakeVoiceTransport transport = FakeVoiceTransport();
    final RideVoiceController controller = RideVoiceController(
      rideId: 'ride-1',
      transport: transport,
      canModerate: false,
    );

    expect(controller.state.mode, RideVoiceMode.groupIntercom);
    expect(controller.state.microphoneEnabled, isFalse);

    await controller.join();

    expect(transport.connectCalls, 1);
    expect(transport.mode, RideVoiceMode.groupIntercom);
    expect(transport.microphoneEnabled, isTrue);
    expect(controller.state.mode, RideVoiceMode.groupIntercom);
    expect(controller.state.microphoneEnabled, isTrue);
    expect(controller.state.canTransmit, isTrue);

    controller.dispose();
    await transport.controller.close();
  });

  test('PTT is optional and only active in explicit PTT mode', () async {
    final FakeVoiceTransport transport = FakeVoiceTransport();
    final RideVoiceController controller = RideVoiceController(
      rideId: 'ride-1',
      transport: transport,
      canModerate: false,
    );
    await controller.join();
    await controller.setPushToTalkActive(true);
    expect(transport.pttActive, isFalse);

    await controller.setMode(RideVoiceMode.pushToTalk);
    await controller.setPushToTalkActive(true);
    expect(transport.pttActive, isTrue);
    expect(controller.state.pushToTalkActive, isTrue);

    controller.dispose();
    await transport.controller.close();
  });

  test(
    'listen only disables microphone and moderator mute never enables it',
    () async {
      final FakeVoiceTransport transport = FakeVoiceTransport();
      final RideVoiceController controller = RideVoiceController(
        rideId: 'ride-1',
        transport: transport,
        canModerate: true,
      );
      await controller.join();
      await controller.setMode(RideVoiceMode.listenOnly);

      expect(controller.state.microphoneEnabled, isFalse);
      await controller.setMicrophoneEnabled(true);
      expect(controller.state.microphoneEnabled, isFalse);

      transport.controller.add(
        const RideVoiceModeratorMutedChanged(muted: true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.moderatorMuted, isTrue);
      expect(controller.state.microphoneEnabled, isFalse);

      transport.controller.add(
        const RideVoiceModeratorMutedChanged(muted: false),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.moderatorMuted, isFalse);
      expect(controller.state.microphoneEnabled, isFalse);

      controller.dispose();
      await transport.controller.close();
    },
  );

  test('local mute and leader moderator mute remain separate', () async {
    final FakeVoiceTransport transport = FakeVoiceTransport();
    final RideVoiceController controller = RideVoiceController(
      rideId: 'ride-1',
      transport: transport,
      canModerate: true,
    );
    await controller.join();

    await controller.setLocalMute('rider-2', true);
    expect(controller.state.locallyMutedRiderIds, contains('rider-2'));
    expect(transport.mutedLocally, contains('rider-2'));

    await controller.moderatorMute('rider-3');
    expect(transport.moderatorMuted, <String>['rider-3']);
    expect(controller.state.locallyMutedRiderIds, isNot(contains('rider-3')));

    controller.dispose();
    await transport.controller.close();
  });
}
