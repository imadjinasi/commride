import 'dart:async';

import 'package:commride_mobile/src/api/push_token_api.dart';
import 'package:commride_mobile/src/push/ride_push_controller.dart';
import 'package:commride_mobile/src/push/ride_push_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePushTokenApi implements PushTokenApi {
  final List<String> registered = <String>[];
  final List<String> unregistered = <String>[];
  bool failRegister = false;
  bool failUnregister = false;

  @override
  Future<void> registerToken({
    required String token,
    required RidePushPlatform platform,
  }) async {
    if (failRegister) {
      throw const PushTokenApiException(
        statusCode: 503,
        code: 'offline',
        message: 'offline',
      );
    }
    registered.add('${platform.name}:$token');
  }

  @override
  Future<void> unregisterToken({
    required String token,
    required RidePushPlatform platform,
  }) async {
    if (failUnregister) {
      throw const PushTokenApiException(
        statusCode: 503,
        code: 'offline',
        message: 'offline',
      );
    }
    unregistered.add('${platform.name}:$token');
  }
}

class FakeMessaging implements RidePushMessaging {
  FakeMessaging({
    this.permission = RidePushPermission.notDetermined,
    this.requestedPermission = RidePushPermission.authorized,
    this.token = 'device-token',
  });

  RidePushPermission permission;
  RidePushPermission requestedPermission;
  String? token;
  int checkCalls = 0;
  int requestCalls = 0;

  final StreamController<String> tokenRefreshController =
      StreamController<String>.broadcast();
  final StreamController<RideForegroundPush> foregroundController =
      StreamController<RideForegroundPush>.broadcast();

  @override
  Future<RidePushPermission> checkPermission() async {
    checkCalls += 1;
    return permission;
  }

  @override
  Future<RidePushPermission> requestPermission() async {
    requestCalls += 1;
    permission = requestedPermission;
    return requestedPermission;
  }

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<RideForegroundPush> get foregroundMessages =>
      foregroundController.stream;

  @override
  Stream<String> get tokenRefreshes => tokenRefreshController.stream;

  Future<void> close() async {
    await tokenRefreshController.close();
    await foregroundController.close();
  }
}

void main() {
  test('start never prompts when notification permission is undecided', () async {
    final FakePushTokenApi api = FakePushTokenApi();
    final FakeMessaging messaging = FakeMessaging();
    final RidePushController controller = RidePushController(
      tokenApi: api,
      messaging: messaging,
      platform: RidePushPlatform.android,
    );

    await controller.start();

    expect(messaging.checkCalls, 1);
    expect(messaging.requestCalls, 0);
    expect(api.registered, isEmpty);
    expect(controller.state.permission, RidePushPermission.notDetermined);

    controller.dispose();
    await messaging.close();
  });

  test('start silently syncs token when permission already exists', () async {
    final FakePushTokenApi api = FakePushTokenApi();
    final FakeMessaging messaging = FakeMessaging(
      permission: RidePushPermission.authorized,
    );
    final RidePushController controller = RidePushController(
      tokenApi: api,
      messaging: messaging,
      platform: RidePushPlatform.android,
    );

    await controller.start();

    expect(messaging.requestCalls, 0);
    expect(api.registered, <String>['android:device-token']);
    expect(controller.state.registered, isTrue);

    controller.dispose();
    await messaging.close();
  });

  test('enable explicitly requests permission then registers token', () async {
    final FakePushTokenApi api = FakePushTokenApi();
    final FakeMessaging messaging = FakeMessaging();
    final RidePushController controller = RidePushController(
      tokenApi: api,
      messaging: messaging,
      platform: RidePushPlatform.ios,
    );

    await controller.start();
    await controller.enable();

    expect(messaging.requestCalls, 1);
    expect(api.registered, <String>['ios:device-token']);
    expect(controller.state.permission, RidePushPermission.authorized);
    expect(controller.state.registered, isTrue);

    controller.dispose();
    await messaging.close();
  });

  test('denied permission never registers a device token', () async {
    final FakePushTokenApi api = FakePushTokenApi();
    final FakeMessaging messaging = FakeMessaging(
      requestedPermission: RidePushPermission.denied,
    );
    final RidePushController controller = RidePushController(
      tokenApi: api,
      messaging: messaging,
      platform: RidePushPlatform.android,
    );

    await controller.start();
    await controller.enable();

    expect(api.registered, isEmpty);
    expect(controller.state.registered, isFalse);
    expect(controller.state.latestError, isNotNull);

    controller.dispose();
    await messaging.close();
  });

  test('Firebase token rotation re-registers the new token', () async {
    final FakePushTokenApi api = FakePushTokenApi();
    final FakeMessaging messaging = FakeMessaging(
      permission: RidePushPermission.authorized,
    );
    final RidePushController controller = RidePushController(
      tokenApi: api,
      messaging: messaging,
      platform: RidePushPlatform.android,
    );

    await controller.start();
    messaging.tokenRefreshController.add('device-token-2');
    await Future<void>.delayed(Duration.zero);

    expect(
      api.registered,
      <String>['android:device-token', 'android:device-token-2'],
    );

    controller.dispose();
    await messaging.close();
  });

  test('foreground message becomes visible controller state', () async {
    final FakePushTokenApi api = FakePushTokenApi();
    final FakeMessaging messaging = FakeMessaging(
      permission: RidePushPermission.authorized,
    );
    final RidePushController controller = RidePushController(
      tokenApi: api,
      messaging: messaging,
      platform: RidePushPlatform.android,
    );

    await controller.start();
    messaging.foregroundController.add(
      const RideForegroundPush(
        title: 'SOS · Rider Two',
        body: 'Butuh bantuan',
        data: <String, String>{'rideId': 'ride-1'},
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.state.latestForegroundPush?.displayText,
      'SOS · Rider Two · Butuh bantuan',
    );

    controller.dispose();
    await messaging.close();
  });

  test('sign-out cleanup failure never blocks caller', () async {
    final FakePushTokenApi api = FakePushTokenApi()..failUnregister = true;
    final FakeMessaging messaging = FakeMessaging(
      permission: RidePushPermission.authorized,
    );
    final RidePushController controller = RidePushController(
      tokenApi: api,
      messaging: messaging,
      platform: RidePushPlatform.android,
    );

    await controller.start();

    await expectLater(
      controller.unregisterBestEffort(),
      completes,
    );

    controller.dispose();
    await messaging.close();
  });
}
