import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/ride_comms_api.dart';
import '../models/ride_message.dart';
import 'realtime_client.dart';

class FailedRideMessageSend {
  const FailedRideMessageSend({
    required this.kind,
    required this.body,
    required this.clientMessageId,
  });

  final RideMessageKind kind;
  final String body;
  final String clientMessageId;
}

class RideCommsState {
  const RideCommsState({
    required this.messages,
    required this.nextCursor,
    required this.loading,
    required this.loadingOlder,
    required this.sending,
    required this.rideEnded,
    required this.failedSend,
    required this.errorMessage,
  });

  const RideCommsState.initial()
    : messages = const <RideMessage>[],
      nextCursor = null,
      loading = false,
      loadingOlder = false,
      sending = false,
      rideEnded = false,
      failedSend = null,
      errorMessage = null;

  final List<RideMessage> messages;
  final String? nextCursor;
  final bool loading;
  final bool loadingOlder;
  final bool sending;
  final bool rideEnded;
  final FailedRideMessageSend? failedSend;
  final String? errorMessage;

  RideMessage? get latestAnnouncement {
    for (final RideMessage message in messages.reversed) {
      if (message.kind == RideMessageKind.announcement) {
        return message;
      }
    }
    return null;
  }

  RideCommsState copyWith({
    List<RideMessage>? messages,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? loading,
    bool? loadingOlder,
    bool? sending,
    bool? rideEnded,
    FailedRideMessageSend? failedSend,
    bool clearFailedSend = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RideCommsState(
      messages: messages ?? this.messages,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      loading: loading ?? this.loading,
      loadingOlder: loadingOlder ?? this.loadingOlder,
      sending: sending ?? this.sending,
      rideEnded: rideEnded ?? this.rideEnded,
      failedSend: clearFailedSend ? null : (failedSend ?? this.failedSend),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class RideCommsController extends ChangeNotifier {
  RideCommsController({
    required String rideId,
    required RideCommsApi api,
    ActiveRideRealtimeClient? realtimeClient,
    String Function()? clientMessageIdFactory,
  }) : _rideId = rideId,
       _api = api,
       _realtimeClient = realtimeClient,
       _clientMessageIdFactory =
           clientMessageIdFactory ?? _defaultClientMessageId {
    if (rideId.trim().isEmpty) {
      throw ArgumentError.value(rideId, 'rideId', 'Ride ID is required.');
    }
  }

  final String _rideId;
  final RideCommsApi _api;
  final ActiveRideRealtimeClient? _realtimeClient;
  final String Function() _clientMessageIdFactory;

  RideCommsState _state = const RideCommsState.initial();
  StreamSubscription<ActiveRideRealtimeEvent>? _realtimeSubscription;
  bool _disposed = false;

  RideCommsState get state => _state;

  void start() {
    if (_disposed || _realtimeSubscription != null) {
      return;
    }
    final ActiveRideRealtimeClient? client = _realtimeClient;
    if (client == null) {
      return;
    }
    _realtimeSubscription = client.events.listen(_handleRealtimeEvent);
  }

  Future<void> loadInitial() async {
    if (_disposed || _state.loading) {
      return;
    }

    _setState(
      _state.copyWith(
        loading: true,
        clearError: true,
      ),
    );

    try {
      final RideMessagePage page = await _api.fetchMessages(_rideId);
      _setState(
        _state.copyWith(
          messages: _sortedUnique(page.messages),
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          loading: false,
          clearError: true,
        ),
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          loading: false,
          errorMessage: 'Pesan Ride belum dapat dimuat.',
        ),
      );
    }
  }

  Future<void> loadOlder() async {
    final String? cursor = _state.nextCursor;
    if (_disposed || cursor == null || _state.loadingOlder) {
      return;
    }

    _setState(
      _state.copyWith(
        loadingOlder: true,
        clearError: true,
      ),
    );

    try {
      final RideMessagePage page = await _api.fetchMessages(
        _rideId,
        cursor: cursor,
      );
      _setState(
        _state.copyWith(
          messages: _sortedUnique(<RideMessage>[
            ...page.messages,
            ..._state.messages,
          ]),
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
          loadingOlder: false,
          clearError: true,
        ),
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          loadingOlder: false,
          errorMessage: 'Pesan sebelumnya belum dapat dimuat.',
        ),
      );
    }
  }

  Future<void> sendChat(String body) {
    return _send(
      kind: RideMessageKind.chat,
      body: body,
      clientMessageId: _clientMessageIdFactory(),
    );
  }

  Future<void> sendAnnouncement(String body) {
    return _send(
      kind: RideMessageKind.announcement,
      body: body,
      clientMessageId: _clientMessageIdFactory(),
    );
  }

  Future<void> retryFailed() async {
    final FailedRideMessageSend? failed = _state.failedSend;
    if (failed == null) {
      return;
    }

    await _send(
      kind: failed.kind,
      body: failed.body,
      clientMessageId: failed.clientMessageId,
    );
  }

  void clearError() {
    if (_disposed) {
      return;
    }
    _setState(_state.copyWith(clearError: true));
  }

  Future<void> _send({
    required RideMessageKind kind,
    required String body,
    required String clientMessageId,
  }) async {
    if (_disposed) {
      return;
    }
    if (_state.rideEnded) {
      throw StateError('Ride communication is read-only after Ride end.');
    }
    if (_state.sending) {
      return;
    }

    final String normalized = body.trim();
    if (normalized.isEmpty || normalized.runes.length > 1000) {
      throw ArgumentError.value(
        body,
        'body',
        'Ride message must contain 1-1000 characters.',
      );
    }

    _setState(
      _state.copyWith(
        sending: true,
        clearFailedSend: true,
        clearError: true,
      ),
    );

    try {
      final RideMessage message = kind == RideMessageKind.announcement
          ? await _api.sendAnnouncement(
              rideId: _rideId,
              clientMessageId: clientMessageId,
              body: normalized,
            )
          : await _api.sendChat(
              rideId: _rideId,
              clientMessageId: clientMessageId,
              body: normalized,
            );

      _setState(
        _state.copyWith(
          messages: _sortedUnique(<RideMessage>[
            ..._state.messages,
            message,
          ]),
          sending: false,
          clearFailedSend: true,
          clearError: true,
        ),
      );
    } catch (_) {
      _setState(
        _state.copyWith(
          sending: false,
          failedSend: FailedRideMessageSend(
            kind: kind,
            body: normalized,
            clientMessageId: clientMessageId,
          ),
          errorMessage: 'Pesan belum terkirim.',
        ),
      );
      rethrow;
    }
  }

  void _handleRealtimeEvent(ActiveRideRealtimeEvent event) {
    if (_disposed) {
      return;
    }

    if (event is ActiveRideMessageCreated) {
      if (event.message.rideId != _rideId) {
        return;
      }
      _setState(
        _state.copyWith(
          messages: _sortedUnique(<RideMessage>[
            ..._state.messages,
            event.message,
          ]),
        ),
      );
      return;
    }

    if (event is ActiveRideEnded) {
      _setState(_state.copyWith(rideEnded: true));
    }
  }

  List<RideMessage> _sortedUnique(Iterable<RideMessage> values) {
    final Map<String, RideMessage> byId = <String, RideMessage>{};

    for (final RideMessage message in values) {
      final RideMessage? existing = byId[message.id];
      if (existing == null || !existing.createdAt.isAfter(message.createdAt)) {
        byId[message.id] = message;
      }
    }

    final List<RideMessage> sorted = byId.values.toList(growable: false)
      ..sort((RideMessage a, RideMessage b) {
        final int time = a.createdAt.compareTo(b.createdAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });

    final Set<String> seenClientIds = <String>{};
    return List<RideMessage>.unmodifiable(
      sorted.where(
        (RideMessage message) => seenClientIds.add(message.clientMessageId),
      ),
    );
  }

  void _setState(RideCommsState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
    super.dispose();
  }

  static String _defaultClientMessageId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${Object().hashCode}';
  }
}
