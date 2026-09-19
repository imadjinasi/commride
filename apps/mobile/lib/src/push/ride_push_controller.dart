import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/push_token_api.dart';
import 'ride_push_messaging.dart';

class RidePushState {
  const RidePushState({
    required this.permission,
    required this.registered,
    required this.working,
    required this.latestForegroundPush,
    required this.latestError,
  });

  const RidePushState.initial()
    : permission = RidePushPermission.notDetermined,
      registered = false,
      working = false,
      latestForegroundPush = null,
      latestError = null;

  final RidePushPermission permission;
  final bool registered;
  final bool working;
  final RideForegroundPush? latestForegroundPush;
  final String? latestError;

  RidePushState copyWith({
    RidePushPermission? permission,
    bool? registered,
    bool? working,
    RideForegroundPush? latestForegroundPush,
    bool clearForegroundPush = false,
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
      _setState(
        _state.copyWith(latestForegroundPush: message, clearLatestError: true),
      );
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
