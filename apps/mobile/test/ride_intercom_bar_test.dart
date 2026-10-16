import 'dart:convert';

import 'package:commride_mobile/src/active_ride/realtimekit_voice_transport.dart';
import 'package:commride_mobile/src/active_ride/voice_intercom.dart';
import 'package:commride_mobile/src/api/http_intercom_api.dart';
import 'package:commride_mobile/src/api/intercom_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/widgets/ride_intercom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'voice_intercom_controller_test.dart' show FakeVoiceTransport;

class _TokenAuth implements AuthGateway {
  @override
  Future<String> idToken() async => 'id-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(RideIntercomBar bar) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(8), child: bar),
  ),
);

void main() {
  late FakeVoiceTransport transport;

  setUp(() => transport = FakeVoiceTransport(supportsLocalMute: false));
  tearDown(() => transport.controller.close());

  RideVoiceController voice({bool leader = false}) => RideVoiceController(
    rideId: 'ride-1',
    transport: transport,
    canModerate: leader,
    speakerHold: const Duration(milliseconds: 200),
  );

  testWidgets('flag off keeps the row visibly unavailable', (tester) async {
    await tester.pumpWidget(
      _host(
        const RideIntercomBar(voiceIntercomEnabled: false, controller: null),
      ),
    );
    expect(find.text('Interkom segera tersedia'), findsOneWidget);
    expect(find.byIcon(Icons.mic_off), findsNothing);
  });

  testWidgets('listening, mic on and speaker states in one 48 dp row', (
    tester,
  ) async {
    final RideVoiceController controller = voice();
    await tester.pumpWidget(
      _host(
        RideIntercomBar(voiceIntercomEnabled: true, controller: controller),
      ),
    );
    expect(find.text('Interkom belum tersambung'), findsOneWidget);

    await controller.join();
    await tester.pumpWidget(
      _host(
        RideIntercomBar(voiceIntercomEnabled: true, controller: controller),
      ),
    );
    expect(find.text('Mendengar · belum ada rider lain'), findsOneWidget);
    expect(tester.getSize(find.byType(RideIntercomBar)).height, 48);

    await tester.tap(find.byKey(const ValueKey<String>('intercom-mic')));
    await tester.pump();
    await tester.pumpWidget(
      _host(
        RideIntercomBar(voiceIntercomEnabled: true, controller: controller),
      ),
    );
    expect(transport.microphoneEnabled, isTrue);
    expect(find.text('Mic menyala · belum ada rider lain'), findsOneWidget);

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
    await tester.pump();
    await tester.pumpWidget(
      _host(
        RideIntercomBar(voiceIntercomEnabled: true, controller: controller),
      ),
    );
    expect(find.text('Sweep bicara'), findsOneWidget);
    expect(tester.getSize(find.byType(RideIntercomBar)).height, 48);

    await tester.pump(const Duration(milliseconds: 250));
    controller.dispose();
  });

  testWidgets('Leader can switch to tap-to-talk and mute a Rider', (
    tester,
  ) async {
    final RideVoiceController controller = voice(leader: true);
    await controller.join();
    transport.controller.add(
      const RideVoiceParticipantsChanged(<RideVoiceParticipant>[
        RideVoiceParticipant(
          riderId: 'rider-2',
          name: 'Sweep',
          audioEnabled: true,
        ),
      ]),
    );
    await tester.pumpWidget(
      _host(
        RideIntercomBar(voiceIntercomEnabled: true, controller: controller),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('intercom-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Mic aktif terus'), findsOneWidget);
    expect(find.text('Tap untuk bicara'), findsOneWidget);
    expect(find.text('Sweep'), findsOneWidget);
    expect(find.byTooltip('Bisukan untuk saya'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('intercom-mute-rider-2')),
    );
    await tester.pump();
    expect(transport.moderatorMuted, <String>['rider-2']);

    await tester.tap(find.byKey(const ValueKey<String>('intercom-mode-ptt')));
    await tester.pump();
    expect(controller.state.mode, RideVoiceMode.pushToTalk);
    controller.dispose();
  });

  testWidgets('a member sees no mute-for-everyone control', (tester) async {
    final RideVoiceController controller = voice();
    await controller.join();
    transport.controller.add(
      const RideVoiceParticipantsChanged(<RideVoiceParticipant>[
        RideVoiceParticipant(
          riderId: 'rider-2',
          name: 'Sweep',
          audioEnabled: true,
        ),
      ]),
    );
    await tester.pumpWidget(
      _host(
        RideIntercomBar(voiceIntercomEnabled: true, controller: controller),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('intercom-settings')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('intercom-mute-rider-2')),
      findsNothing,
    );
    controller.dispose();
  });

  testWidgets('Leader mute is shown to the muted Rider', (tester) async {
    final RideVoiceController controller = voice();
    await controller.join();
    await controller.toggleMicrophone();
    transport.controller.add(const RideVoiceModeratorMutedChanged(muted: true));
    await tester.pump();
    await tester.pumpWidget(
      _host(
        RideIntercomBar(voiceIntercomEnabled: true, controller: controller),
      ),
    );
    expect(find.text('Mic dimatikan Ketua'), findsOneWidget);
    controller.dispose();
  });

  group('RealtimeKit bridge events', () {
    test('decode connection, speaker, mute and participants', () {
      expect(
        decodeNativeIntercomEvent(<String, Object?>{
          'type': 'connection',
          'state': 'reconnecting',
        }),
        isA<RideVoiceTransportDegraded>(),
      );
      expect(
        decodeNativeIntercomEvent(<String, Object?>{
          'type': 'connection',
          'state': 'ended',
        }),
        isA<RideVoiceTransportClosed>(),
      );
      final RideVoiceEvent? speaker = decodeNativeIntercomEvent(
        <String, Object?>{'type': 'speaker', 'riderId': 'rider-2'},
      );
      expect((speaker! as RideVoiceActiveSpeakersChanged).riderIds, <String>{
        'rider-2',
      });
      expect(
        decodeNativeIntercomEvent(<String, Object?>{'type': 'moderatorMuted'}),
        isA<RideVoiceModeratorMutedChanged>(),
      );
      final RideVoiceEvent? participants = decodeNativeIntercomEvent(
        <String, Object?>{
          'type': 'participants',
          'participants': <Object?>[
            <String, Object?>{
              'riderId': 'rider-2',
              'name': 'Sweep',
              'audioEnabled': true,
            },
            <String, Object?>{'name': 'no id'},
          ],
        },
      );
      expect(
        (participants! as RideVoiceParticipantsChanged)
            .participants
            .single
            .riderId,
        'rider-2',
      );
      expect(decodeNativeIntercomEvent('junk'), isNull);
      expect(
        decodeNativeIntercomEvent(<String, Object?>{'type': 'other'}),
        isNull,
      );
    });
  });

  group('HttpIntercomApi', () {
    test('posts to the Ride token endpoint with the Firebase token', () async {
      late http.Request seen;
      final HttpIntercomApi api = HttpIntercomApi(
        apiBaseUrl: Uri.parse('https://api.example'),
        authGateway: _TokenAuth(),
        client: MockClient((http.Request request) async {
          seen = request;
          return http.Response(
            jsonEncode(<String, Object?>{
              'intercom': <String, Object?>{
                'provider': 'cloudflare_realtimekit',
                'authToken': 'join-token',
                'baseDomain': 'realtime.cloudflare.com',
                'role': 'leader',
                'canModerate': true,
              },
            }),
            200,
          );
        }),
      );

      final IntercomJoinGrant grant = await api.requestJoin('ride 1');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/v1/rides/ride%201/intercom/token');
      expect(seen.headers['authorization'], 'Bearer id-token');
      expect(grant.authToken, 'join-token');
      expect(grant.canModerate, isTrue);
    });

    test('surfaces API errors with their code', () async {
      final HttpIntercomApi api = HttpIntercomApi(
        apiBaseUrl: Uri.parse('https://api.example'),
        authGateway: _TokenAuth(),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{
                'code': 'intercom_not_configured',
                'message': 'off',
                'requestId': 'r',
              },
            }),
            503,
          ),
        ),
      );
      await expectLater(
        api.requestJoin('ride-1'),
        throwsA(
          isA<IntercomApiException>().having(
            (IntercomApiException e) => e.code,
            'code',
            'intercom_not_configured',
          ),
        ),
      );
    });
  });
}
