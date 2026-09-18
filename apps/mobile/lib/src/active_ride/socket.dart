import 'dart:io';

abstract interface class ActiveRideSocket {
  Stream<Object?> get messages;

  void send(String message);

  Future<void> close([int? code, String? reason]);
}

abstract interface class ActiveRideSocketConnector {
  Future<ActiveRideSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
  });
}

class IoActiveRideSocketConnector implements ActiveRideSocketConnector {
  const IoActiveRideSocketConnector();

  @override
  Future<ActiveRideSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    final WebSocket socket = await WebSocket.connect(
      uri.toString(),
      headers: headers,
    );
    return _IoActiveRideSocket(socket);
  }
}

class _IoActiveRideSocket implements ActiveRideSocket {
  _IoActiveRideSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get messages => _socket;

  @override
  void send(String message) {
    _socket.add(message);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _socket.close(code, reason);
  }
}
