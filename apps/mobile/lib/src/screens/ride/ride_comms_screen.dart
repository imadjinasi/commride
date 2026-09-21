import 'dart:async';

import 'package:flutter/material.dart';

import '../../active_ride/ride_comms_controller.dart';
import '../../models/club_ride.dart';
import '../../models/ride_message.dart';

class RideCommsScreen extends StatefulWidget {
  const RideCommsScreen({
    required this.ride,
    required this.membership,
    required this.controller,
    super.key,
  });

  final Ride ride;
  final RideMembership membership;
  final RideCommsController controller;

  @override
  State<RideCommsScreen> createState() => _RideCommsScreenState();
}

class _RideCommsScreenState extends State<RideCommsScreen> {
  final TextEditingController _composer = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.start();
    unawaited(widget.controller.loadInitial());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.dispose();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RideCommsState state = widget.controller.state;
    final bool canSend =
        widget.ride.status == RideStatus.active && !state.rideEnded;
    final bool canAnnounce =
        canSend && widget.membership.role == RideRole.leader;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comms'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: state.loading
                ? null
                : () => widget.controller.loadInitial(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (state.latestAnnouncement != null)
              _PinnedAnnouncement(message: state.latestAnnouncement!),
            if (state.errorMessage != null)
              _ErrorBanner(
                message: state.errorMessage!,
                failedSend: state.failedSend,
                sending: state.sending,
                onRetrySend: _retryFailed,
                onDismiss: widget.controller.clearError,
              ),
            Expanded(
              child: _MessageHistory(
                state: state,
                currentRiderId: widget.membership.riderId,
                onLoadOlder: widget.controller.loadOlder,
                onRefresh: widget.controller.loadInitial,
              ),
            ),
            if (canSend)
              _Composer(
                controller: _composer,
                sending: state.sending,
                canAnnounce: canAnnounce,
                onSendChat: _sendChat,
                onSendAnnouncement: _sendAnnouncement,
              )
            else
              const _ReadOnlyBanner(),
          ],
        ),
      ),
    );
  }

  Future<void> _sendChat() async {
    final String body = _composer.text.trim();
    if (body.isEmpty) {
      return;
    }

    try {
      await widget.controller.sendChat(body);
      if (mounted) {
        _composer.clear();
      }
    } catch (_) {
      // Controller state carries a retryable failure.
    }
  }

  Future<void> _retryFailed() async {
    try {
      await widget.controller.retryFailed();
      if (mounted) {
        _composer.clear();
      }
    } catch (_) {
      // Controller state keeps the retryable failure visible.
    }
  }

  Future<void> _sendAnnouncement() async {
    final String? body = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return const _AnnouncementDialog();
      },
    );
    if (body == null || body.isEmpty) {
      return;
    }

    try {
      await widget.controller.sendAnnouncement(body);
    } catch (_) {
      // Controller state carries a retryable failure.
    }
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _PinnedAnnouncement extends StatelessWidget {
  const _PinnedAnnouncement({required this.message});

  final RideMessage message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.campaign_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Pengumuman Leader',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(message.body),
                  const SizedBox(height: 3),
                  Text(
                    '${message.senderDisplayName} · '
                    '${_formatTime(message.createdAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.failedSend,
    required this.sending,
    required this.onRetrySend,
    required this.onDismiss,
  });

  final String message;
  final FailedRideMessageSend? failedSend;
  final bool sending;
  final Future<void> Function() onRetrySend;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.error_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            if (failedSend != null)
              TextButton(
                onPressed: sending
                    ? null
                    : () {
                        unawaited(onRetrySend());
                      },
                child: const Text('Kirim ulang'),
              ),
            IconButton(
              tooltip: 'Tutup',
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageHistory extends StatelessWidget {
  const _MessageHistory({
    required this.state,
    required this.currentRiderId,
    required this.onLoadOlder,
    required this.onRefresh,
  });

  final RideCommsState state;
  final String currentRiderId;
  final Future<void> Function() onLoadOlder;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.messages.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: const <Widget>[
            SizedBox(height: 80),
            Icon(Icons.forum_outlined, size: 42),
            SizedBox(height: 12),
            Center(child: Text('Belum ada pesan di Ride ini.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: <Widget>[
          if (state.nextCursor != null)
            Center(
              child: TextButton.icon(
                onPressed: state.loadingOlder ? null : onLoadOlder,
                icon: state.loadingOlder
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history),
                label: const Text('Muat pesan sebelumnya'),
              ),
            ),
          ...state.messages.map(
            (RideMessage message) => _MessageCard(
              message: message,
              mine: message.senderRiderId == currentRiderId,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.mine});

  final RideMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final bool announcement = message.kind == RideMessageKind.announcement;

    return Align(
      alignment: announcement
          ? Alignment.center
          : mine
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (announcement) ...<Widget>[
                      const Icon(Icons.campaign_outlined, size: 18),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        announcement
                            ? 'Pengumuman Leader'
                            : message.senderDisplayName,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                if (!announcement) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    message.senderRideRole.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 6),
                Text(message.body),
                const SizedBox(height: 6),
                Text(
                  _formatTime(message.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.canAnnounce,
    required this.onSendChat,
    required this.onSendAnnouncement,
  });

  final TextEditingController controller;
  final bool sending;
  final bool canAnnounce;
  final Future<void> Function() onSendChat;
  final Future<void> Function() onSendAnnouncement;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (canAnnounce)
              IconButton(
                tooltip: 'Pengumuman Leader',
                onPressed: sending
                    ? null
                    : () {
                        unawaited(onSendAnnouncement());
                      },
                icon: const Icon(Icons.campaign_outlined),
              ),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !sending,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  hintText: 'Pesan ke Rider...',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) {
                  if (!sending) {
                    unawaited(onSendChat());
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Kirim pesan',
              onPressed: sending
                  ? null
                  : () {
                      unawaited(onSendChat());
                    },
              icon: sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const SafeArea(
        top: false,
        minimum: EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(Icons.lock_outline),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ride selesai. Riwayat Comms tetap dapat dibaca, '
                'tetapi pesan baru tidak dapat dikirim.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog();

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pengumuman Leader'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 1000,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(
          hintText: 'Tulis pengumuman operasional untuk semua Rider.',
          border: OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final String value = _controller.text.trim();
            if (value.isNotEmpty) {
              Navigator.of(context).pop(value);
            }
          },
          child: const Text('Publikasikan'),
        ),
      ],
    );
  }
}

String _formatTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}';
}
