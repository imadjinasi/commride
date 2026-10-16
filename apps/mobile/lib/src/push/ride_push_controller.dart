import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/push_token_api.dart';
import 'ride_push_messaging.dart';

class RideNotificationEntry {
  const RideNotificationEntry({
    required this.id,
    required this.message,
    required this.receivedAt,
    required this.read,
  });

  final String id;
  final RideForegroundPush message;
  final DateTime receivedAt;
  final bool read;

  String? get rideId => _identifier(message.data['rideId']);
  String? get clubId => _identifier(message.data['clubId']);
  String? get type => _identifier(message.data['type']);

  RideNotificationEntry copyWith({bool? read}) {
    return RideNotificationEntry(
      id: id,
      message: message,
      receivedAt: receivedAt,
      read: read ?? this.read,
    );
  }

  static String? _identifier(String? value) {
    final String normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}

class RidePushState {
  const RidePushState({
    required this.permission,
    required this.registered,
    required this.working,
    required this.latestForegroundPush,
    required this.notifications,
    required this.latestError,
  });

  const RidePushState.initial()
    : permission = RidePushPermission.notDetermined,
      registered = false,
      working = false,
      latestForegroundPush = null,
      notifications = const <RideNotificationEntry>[],
      latestError = null;

  final RidePushPermission permission;
  final bool registered;
  final bool working;
  final RideForegroundPush? latestForegroundPush;
  final List<RideNotificationEntry> notifications;
  final String? latestError;

  int get unreadCount =>
      notifications.where((RideNotificationEntry item) => !item.read).length;

  RidePushState copyWith({
    RidePushPermission? permission,
    bool? registered,
    bool? working,
    RideForegroundPush? latestForegroundPush,
    bool clearForegroundPush = false,
    List<RideNotificationEntry>? notifications,
    String? latestError,
    bool clearLatestError = false,
  }) {
    return RidePushState(
      permission: permission ?? this.permission,
      registered: registered ?? this.registered,
      working: working ?? this.working,
      latestForegroundPush: clearForegroundPush
          ? null
          : (latestForegroundPush ?? this.latestForegroundPush),
      notifications: notifications ?? this.notifications,
      latestError: clearLatestError ? null : (latestError ?? this.latestError),
    );
  }
}

class RidePushController extends ChangeNotifier {
  RidePushController({
    required PushTokenApi tokenApi,
    required RidePushMessaging messaging,
    required RidePushPlatform platform,
  }) : _tokenApi = tokenApi,
       _messaging = messaging,
       _platform = platform;

  final PushTokenApi _tokenApi;
  final RidePushMessaging _messaging;
  final RidePushPlatform _platform;

  RidePushState _state = const RidePushState.initial();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RideForegroundPush>? _foregroundSubscription;
  String? _registeredToken;
  bool _started = false;
  bool _disposed = false;
  int _notificationSequence = 0;

  RidePushState get state => _state;

  Future<void> start() async {
    if (_disposed || _started) {
      return;
    }
    _started = true;

    _tokenSubscription = _messaging.tokenRefreshes.listen((String token) {
      unawaited(_registerToken(token));
    });
    _foregroundSubscription = _messaging.foregroundMessages.listen((
      RideForegroundPush message,
    ) {
      _recordNotification(message);
    });

    try {
      final RidePushPermission permission = await _messaging.checkPermission();
      _setState(_state.copyWith(permission: permission));
      if (permission.canReceive) {
        await _syncToken();
      }
    } catch (_) {
      _setState(
        _state.copyWith(
          latestError: 'Status notifikasi belum dapat diperiksa.',
        ),
      );
    }
  }

  Future<void> enable() async {
    if (_disposed || _state.working) {
      return;
    }

    _setState(_state.copyWith(working: true, clearLatestError: true));

    try {
      final RidePushPermission permission = await _messaging
          .requestPermission();
      _setState(_state.copyWith(permission: permission));

      if (!permission.canReceive) {
        _setState(
          _state.copyWith(
            registered: false,
            latestError: 'Izin notifikasi belum diberikan pada perangkat ini.',
          ),
        );
        return;
      }

      await _syncToken();
    } catch (_) {
      _setState(
        _state.copyWith(latestError: 'Notifikasi Ride belum dapat diaktifkan.'),
      );
    } finally {
      if (!_disposed) {
        _setState(_state.copyWith(working: false));
      }
    }
  }

  Future<void> unregisterBestEffort() async {
    final String? token = _registeredToken ?? await _safeCurrentToken();
    if (token == null || token.isEmpty) {
      return;
    }

    try {
      await _tokenApi.unregisterToken(token: token, platform: _platform);
      _registeredToken = null;
      _setState(_state.copyWith(registered: false));
    } catch (_) {
      // Sign-out must not be blocked by notification cleanup.
    }
  }

  void clearForegroundPush() {
    _setState(_state.copyWith(clearForegroundPush: true));
  }

  void markNotificationRead(String notificationId) {
    bool changed = false;
    final List<RideNotificationEntry> updated = _state.notifications
        .map((RideNotificationEntry item) {
          if (item.id != notificationId || item.read) {
            return item;
          }
          changed = true;
          return item.copyWith(read: true);
        })
        .toList(growable: false);
    if (changed) {
      _setState(_state.copyWith(notifications: updated));
    }
  }

  void markAllNotificationsRead() {
    if (_state.notifications.every((RideNotificationEntry item) => item.read)) {
      return;
    }
    _setState(
      _state.copyWith(
        notifications: _state.notifications
            .map((RideNotificationEntry item) => item.copyWith(read: true))
            .toList(growable: false),
      ),
    );
  }

  Future<void> _syncToken() async {
    final String? token = await _messaging.currentToken();
    if (token == null || token.trim().isEmpty) {
      _setState(
        _state.copyWith(
          registered: false,
          latestError:
              'Firebase belum memberikan token notifikasi untuk perangkat ini.',
        ),
      );
      return;
    }

    await _registerToken(token);
  }

  Future<void> _registerToken(String token) async {
    if (_disposed || !_state.permission.canReceive) {
      return;
    }
    final String normalized = token.trim();
    if (normalized.isEmpty || normalized == _registeredToken) {
      return;
    }

    try {
      await _tokenApi.registerToken(token: normalized, platform: _platform);
      _registeredToken = normalized;
      _setState(_state.copyWith(registered: true, clearLatestError: true));
    } catch (_) {
      _setState(
        _state.copyWith(
          registered: false,
          latestError:
              'Token notifikasi belum dapat didaftarkan. Coba lagi nanti.',
        ),
      );
    }
  }

  void _recordNotification(RideForegroundPush message) {
    if (_disposed) {
      return;
    }
    final DateTime now = DateTime.now().toUtc();
    final RideNotificationEntry entry = RideNotificationEntry(
      id: '${now.microsecondsSinceEpoch}-${_notificationSequence++}',
      message: message,
      receivedAt: now,
      read: false,
    );
    final List<RideNotificationEntry> next = <RideNotificationEntry>[
      entry,
      ..._state.notifications,
    ];
    _setState(
      _state.copyWith(
        latestForegroundPush: message,
        notifications: List<RideNotificationEntry>.unmodifiable(next.take(50)),
        clearLatestError: true,
      ),
    );
  }

  Future<String?> _safeCurrentToken() async {
    try {
      return await _messaging.currentToken();
    } catch (_) {
      return null;
    }
  }

  void _setState(RidePushState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_tokenSubscription?.cancel());
    unawaited(_foregroundSubscription?.cancel());
    _tokenSubscription = null;
    _foregroundSubscription = null;
    super.dispose();
  }
}
