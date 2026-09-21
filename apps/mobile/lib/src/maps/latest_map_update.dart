import 'dart:async';

/// Serializes native writes and keeps only the newest waiting snapshot.
/// Disposal drops pending work; the active writer must also check its lifetime.
class LatestMapUpdate<T extends Object> {
  LatestMapUpdate({required this.apply, required this.onError});

  final Future<void> Function(T value) apply;
  final void Function() onError;
  T? _pending;
  Completer<void>? _idle;
  bool _disposed = false;

  Future<void> get idle => _idle?.future ?? Future<void>.value();

  void submit(T value) {
    if (_disposed) {
      return;
    }
    _pending = value;
    if (_idle != null) {
      return;
    }
    _idle = Completer<void>();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (!_disposed && _pending != null) {
        final T value = _pending!;
        _pending = null;
        await apply(value);
      }
    } catch (_) {
      if (!_disposed) {
        dispose();
        onError();
      }
    } finally {
      _idle?.complete();
      _idle = null;
    }
  }

  void dispose() {
    _disposed = true;
    _pending = null;
  }
}
