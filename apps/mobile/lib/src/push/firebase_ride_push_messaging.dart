import 'package:firebase_messaging/firebase_messaging.dart';

import 'ride_push_messaging.dart';

class FirebaseRidePushMessaging implements RidePushMessaging {
  FirebaseRidePushMessaging(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<RidePushPermission> checkPermission() async {
    final NotificationSettings settings =
        await _messaging.getNotificationSettings();
    return _permission(settings.authorizationStatus);
  }

  @override
  Future<RidePushPermission> requestPermission() async {
    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    return _permission(settings.authorizationStatus);
  }

  @override
  Future<String?> currentToken() {
    return _messaging.getToken();
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<RideForegroundPush> get foregroundMessages {
    return FirebaseMessaging.onMessage.map((RemoteMessage message) {
      return RideForegroundPush(
        title: message.notification?.title,
        body: message.notification?.body,
        data: Map<String, String>.unmodifiable(
          message.data.map(
            (String key, Object value) =>
                MapEntry<String, String>(key, value.toString()),
          ),
        ),
      );
    });
  }

  RidePushPermission _permission(AuthorizationStatus status) {
    return switch (status) {
      AuthorizationStatus.authorized => RidePushPermission.authorized,
      AuthorizationStatus.provisional => RidePushPermission.provisional,
      AuthorizationStatus.denied => RidePushPermission.denied,
      AuthorizationStatus.notDetermined => RidePushPermission.notDetermined,
    };
  }
}
