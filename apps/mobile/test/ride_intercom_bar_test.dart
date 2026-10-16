import 'dart:convert';

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

  testWidgets('local mute appears only where the provider supports it', (
    tester,
  ) async {
    final FakeVoiceTransport local = FakeVoiceTransport();
    final RideVoiceController controller = RideVoiceController(
      rideId: 'ride-1',
      transport: local,
      canModerate: false,
    );
    await controller.join();
    local.controller.add(
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
    await tester.tap(find.byTooltip('Bisukan untuk saya'));
    await tester.pump();
    expect(local.mutedLocally, contains('rider-2'));
    expect(find.byTooltip('Dengarkan lagi'), findsOneWidget);
    controller.dispose();
    await local.controller.close();
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
                'provider': 'livekit',
                'serverUrl': 'wss://commride.livekit.cloud',
                'authToken': 'join-token',
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
      expect(grant.serverUrl, 'wss://commride.livekit.cloud');
      expect(grant.authToken, 'join-token');
      expect(grant.canModerate, isTrue);
    });

    test('asks the API to mute a Rider for everyone', () async {
      late http.Request seen;
      final HttpIntercomApi api = HttpIntercomApi(
        apiBaseUrl: Uri.parse('https://api.example'),
        authGateway: _TokenAuth(),
        client: MockClient((http.Request request) async {
          seen = request;
          return http.Response('{"muted":true}', 200);
        }),
      );

      await api.muteRider(rideId: 'ride-1', riderId: 'rider-2');
      expect(seen.url.path, '/v1/rides/ride-1/intercom/mute');
      expect(jsonDecode(seen.body), <String, Object?>{'riderId': 'rider-2'});
      expect(seen.headers['content-type'], startsWith('application/json'));
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
