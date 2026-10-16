import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum MediaKey { previous, playPause, next }

/// Sends media keys to whatever music app is playing, like a Bluetooth
/// headset button. Android only; needs no special permission and cannot read
/// what is playing.
abstract final class MediaKeys {
  static const MethodChannel _channel = MethodChannel('commride/media_keys');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether any app is playing audio right now (no track details).
  static Future<bool> isMusicActive() async {
    if (!supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('isMusicActive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> send(MediaKey key) async {
    if (!supported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('send', key.name);
    } on PlatformException {
      // No media session or the platform refused: nothing to control.
    } on MissingPluginException {
      // Older native build without the channel.
    }
  }
}
