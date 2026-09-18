import 'dart:async';

import 'package:flutter/material.dart';

import '../../active_ride/live_group_controller.dart';
import '../../active_ride/live_group_models.dart';
import '../../active_ride/location_provider.dart';
import '../../active_ride/realtime_client.dart';
import '../../models/club_ride.dart';

class LiveGroupScreen extends StatefulWidget {
  const LiveGroupScreen({
    required this.ride,
    required this.controller,
    this.now,
    this.autoRefresh = true,
    super.key,
  });

  final Ride ride;
  final ActiveRideGroupController controller;
  final DateTime Function()? now;
  final bool autoRefresh;

  @override
  State<LiveGroupScreen> createState() => _LiveGroupScreenState();
}

class _LiveGroupScreenState extends State<LiveGroupScreen> {
  Timer? _freshnessTimer;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
    widget.controller.start();

    if (widget.autoRefresh) {
      _freshnessTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => widget.controller.refreshFreshness(),
      );
    }
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    widget.controller.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ActiveRideGroupState state = widget.controller.state;
    final ActiveRideGroupCounts counts = state.counts(_now);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Group')),
      floatingActionButton: state.hasEnded
          ? null
          : FloatingActionButton.extended(
              onPressed: _showQuickActions,
              icon: const Icon(Icons.bolt_outlined),
              label: const Text('Quick Actions'),
            ),
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: ListView(
          children: <Widget>[
            Text(
              widget.ride.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            _ConnectionCard(state: state),
            const SizedBox(height: 14),
            _GroupSummary(counts: counts),
            const SizedBox(height: 18),
            _QuickActionsPanel(
              enabled: !state.hasEnded,
              onSend: _sendQuickAction,
              onSendWithReason: _sendQuickActionWithReason,
            ),
            if (state.quickActions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                'Perlu perhatian',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...state.quickActions
                  .take(5)
                  .map(
                    (LiveQuickAction action) =>
                        _QuickActionCard(action: action, now: _now),
                  ),
            ],
            const SizedBox(height: 18),
            Text('Riders', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (state.presences.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Belum ada posisi Rider yang diterima untuk Ride ini.',
                  ),
                ),
              )
            else
              ...state.presences.map(
                (LiveRiderPresence presence) =>
                    _PresenceCard(presence: presence, now: _now),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showQuickActions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return _QuickActionsSheet(
          onSend: (LiveQuickActionKind kind, {String? reason}) =>
              _sendQuickAction(sheetContext, kind, reason: reason),
        );
      },
    );
  }

  Future<void> _sendQuickAction(
    BuildContext sheetContext,
    LiveQuickActionKind kind, {
    String? reason,
  }) async {
    try {
      await widget.controller.raiseQuickAction(kind, reason: reason);
      if (!mounted) {
        return;
      }
      if (sheetContext.mounted && Navigator.of(sheetContext).canPop()) {
        Navigator.of(sheetContext).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${kind.label} terkirim.')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quick action belum terkirim. Periksa koneksi realtime.',
          ),
        ),
      );
    }
  }

  Future<void> _sendQuickAction(LiveQuickActionKind kind) async {
    try {
      await widget.controller.raiseQuickAction(kind);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${kind.label} terkirim.')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quick action belum terkirim. Periksa koneksi realtime.',
          ),
        ),
      );
    }
  }

  Future<void> _sendQuickActionWithReason(LiveQuickActionKind kind) async {
    final TextEditingController reasonController = TextEditingController();
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(kind.label),
          content: TextField(
            controller: reasonController,
            maxLength: 240,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Alasan opsional',
              hintText: 'Contoh: berhenti isi BBM atau terpisah di lampu merah',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(reasonController.text.trim()),
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );
    reasonController.dispose();

    if (reason == null || !mounted) {
      return;
    }

    try {
      await widget.controller.raiseQuickAction(
        kind,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${kind.label} terkirim.')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Quick action belum terkirim. Periksa koneksi realtime.',
          ),
        ),
      );
    }
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

typedef _QuickActionSender =
    Future<void> Function(LiveQuickActionKind kind, {String? reason});

class _QuickActionsSheet extends StatelessWidget {
  const _QuickActionsSheet({required this.onSend});

  final _QuickActionSender onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Kirim kondisi penting ke semua Rider tanpa membuka chat.',
            ),
            const SizedBox(height: 12),
            _QuickActionSendTile(
              kind: LiveQuickActionKind.stopping,
              subtitle:
                  'Berhenti sementara untuk BBM, istirahat, atau kendala.',
              onSend: onSend,
            ),
            _QuickActionSendTile(
              kind: LiveQuickActionKind.leftBehind,
              subtitle: 'Beri tahu rombongan bahwa kamu tertinggal.',
              onSend: onSend,
            ),
            _QuickActionSendTile(
              kind: LiveQuickActionKind.needHelp,
              subtitle: 'Minta bantuan rombongan. Ini bukan layanan SOS.',
              onSend: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionSendTile extends StatelessWidget {
  const _QuickActionSendTile({
    required this.kind,
    required this.subtitle,
    required this.onSend,
  });

  final LiveQuickActionKind kind;
  final String subtitle;
  final _QuickActionSender onSend;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_quickActionIcon(kind)),
      title: Text(kind.label),
      subtitle: Text(subtitle),
      onTap: () => onSend(kind),
      trailing: IconButton(
        tooltip: 'Kirim ${kind.label} dengan alasan',
        icon: const Icon(Icons.note_add_outlined),
        onPressed: () => _sendWithReason(context),
      ),
    );
  }

  Future<void> _sendWithReason(BuildContext context) async {
    String draftReason = '';
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('${kind.label} — alasan'),
          content: TextField(
            maxLength: 240,
            minLines: 1,
            maxLines: 3,
            onChanged: (String value) {
              draftReason = value;
            },
            decoration: const InputDecoration(
              hintText: 'Opsional, mis. isi BBM atau kendala mesin',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(draftReason.trim()),
              child: const Text('Kirim'),
            ),
          ],
        );
      },
    );

    if (reason == null) {
      return;
    }
    await onSend(kind, reason: reason);
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.state});

  final ActiveRideGroupState state;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String detail;
    final IconData icon;

    if (state.hasEnded) {
      title = 'Ride selesai';
      detail = 'Live Group sudah ditutup. Posisi terakhir tidak dianggap live.';
      icon = Icons.flag_outlined;
    } else {
      switch (state.connectionState) {
        case ActiveRideRealtimeConnectionState.connected:
          title = 'Live Group terhubung';
          detail = 'Status Rider diperbarui dari ruang Ride.';
          icon = Icons.link;
        case ActiveRideRealtimeConnectionState.connecting:
          title = 'Menghubungkan Live Group';
          detail = 'Menunggu koneksi realtime.';
          icon = Icons.sync;
        case ActiveRideRealtimeConnectionState.disconnected:
          title = 'Live Group terputus';
          detail =
              'Posisi yang terlihat adalah data terakhir dengan timestamp.';
          icon = Icons.link_off;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(detail),
                  if (state.latestError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      state.latestError!.message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupSummary extends StatelessWidget {
  const _GroupSummary({required this.counts});

  final ActiveRideGroupCounts counts;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _Count(label: 'Live', value: counts.live),
            ),
            Expanded(
              child: _Count(label: 'Stale', value: counts.stale),
            ),
            Expanded(
              child: _Count(label: 'Offline', value: counts.offline),
            ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text('$value', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(label),
      ],
    );
  }
}

class _PresenceCard extends StatelessWidget {
  const _PresenceCard({required this.presence, required this.now});

  final LiveRiderPresence presence;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final LivePresenceFreshness freshness = presence.effectiveFreshness(now);
    final String age = _formatAge(now.difference(presence.observedAt));

    return Card(
      child: ListTile(
        leading: Icon(_freshnessIcon(freshness)),
        title: Text(presence.displayName),
        subtitle: Text(
          '${presence.role.label} · '
          '${_movementLabel(presence.movement)} · '
          'observasi $age lalu',
        ),
        trailing: Chip(label: Text(freshness.label)),
      ),
    );
  }
}

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({
    required this.enabled,
    required this.onSend,
    required this.onSendWithReason,
  });

  final bool enabled;
  final Future<void> Function(LiveQuickActionKind kind) onSend;
  final Future<void> Function(LiveQuickActionKind kind) onSendWithReason;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Kirim kondisi singkat ke semua Rider tanpa membuka chat.',
            ),
            const SizedBox(height: 14),
            ...LiveQuickActionKind.values.map(
              (LiveQuickActionKind kind) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: enabled ? () => onSend(kind) : null,
                        icon: Icon(_quickActionIcon(kind)),
                        label: Text(kind.label),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Kirim ${kind.label} dengan alasan',
                      onPressed: enabled ? () => onSendWithReason(kind) : null,
                      icon: const Icon(Icons.edit_note_outlined),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Butuh Bantuan memberi tahu grup Ride. Ini bukan SOS dan tidak '
              'menghubungi layanan darurat.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action, required this.now});

  final LiveQuickAction action;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final String age = _formatAge(now.difference(action.raisedAt));
    final LivePresenceFreshness? presenceFreshness = action.presence
        ?.effectiveFreshness(now);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(_quickActionIcon(action.kind)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    action.kind.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${action.displayName} · ${action.role.label} · $age lalu',
                  ),
                  if (action.reason != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(action.reason!),
                  ],
                  if (action.presence != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Lokasi ${presenceFreshness!.label} · '
                      'observasi ${_formatAge(now.difference(action.presence!.observedAt))} lalu',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (action.presence != null) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      'Lokasi ${action.presence!.effectiveFreshness(now).label}'
                      ' · observasi '
                      '${_formatAge(now.difference(action.presence!.observedAt))}'
                      ' lalu',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _freshnessIcon(LivePresenceFreshness freshness) {
  return switch (freshness) {
    LivePresenceFreshness.live => Icons.my_location,
    LivePresenceFreshness.stale => Icons.schedule,
    LivePresenceFreshness.offline => Icons.location_off_outlined,
  };
}

IconData _quickActionIcon(LiveQuickActionKind kind) {
  return switch (kind) {
    LiveQuickActionKind.stopping => Icons.stop_circle_outlined,
    LiveQuickActionKind.leftBehind => Icons.person_pin_circle_outlined,
    LiveQuickActionKind.needHelp => Icons.help_outline,
  };
}

String _movementLabel(RideMovementState movement) {
  return switch (movement) {
    RideMovementState.moving => 'Bergerak',
    RideMovementState.stopped => 'Berhenti',
    RideMovementState.unknown => 'Status gerak belum diketahui',
  };
}

String _formatAge(Duration duration) {
  final Duration age = duration.isNegative ? Duration.zero : duration;

  if (age.inSeconds < 60) {
    return '${age.inSeconds} dtk';
  }
  if (age.inMinutes < 60) {
    return '${age.inMinutes} mnt';
  }
  return '${age.inHours} jam';
}
