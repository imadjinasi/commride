import 'dart:async';

import 'package:flutter/material.dart';

import '../../active_ride/convoy_separation.dart';
import '../../active_ride/live_group_controller.dart';
import '../../active_ride/live_group_map_models.dart';
import '../../active_ride/live_group_models.dart';
import '../../active_ride/location_provider.dart';
import '../../active_ride/realtime_client.dart';
import '../../maps/live_group_map_view.dart';
import '../../models/club_ride.dart';

class LiveGroupScreen extends StatefulWidget {
  const LiveGroupScreen({
    required this.ride,
    required this.controller,
    this.now,
    this.autoRefresh = true,
    this.mapsEnabled = false,
    super.key,
  });

  final Ride ride;
  final ActiveRideGroupController controller;
  final DateTime Function()? now;
  final bool autoRefresh;
  final bool mapsEnabled;

  @override
  State<LiveGroupScreen> createState() => _LiveGroupScreenState();
}

class _LiveGroupScreenState extends State<LiveGroupScreen> {
  Timer? _freshnessTimer;
  late bool _showMap;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // Positions already sit on the riding map; this screen leads with the
    // log and each Rider's status, with the map one tap away.
    _showMap = false;
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
    final DateTime now = _now;
    final ActiveRideGroupCounts counts = state.counts(now);

    return Scaffold(
      appBar: AppBar(title: const Text('Rombongan')),
      bottomNavigationBar: state.hasEnded
          ? null
          : _StatusBar(
              onSend: (LiveQuickActionKind kind) =>
                  _sendQuickAction(null, kind),
              onAddNote: _showQuickActions,
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
            if (state.separation != null &&
                state.separation!.phase !=
                    ConvoySeparationPhase.normal) ...<Widget>[
              const SizedBox(height: 12),
              _SeparationCard(separation: state.separation!),
            ],
            const SizedBox(height: 18),
            Text(
              'Log rombongan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (state.quickActions.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Belum ada status dari Rider di Ride ini.'),
                ),
              )
            else
              ..._newestFirst(state.quickActions).map(
                (LiveQuickAction action) =>
                    _QuickActionCard(action: action, now: now),
              ),
            const SizedBox(height: 18),
            if (widget.mapsEnabled) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Status Rider',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.map_outlined),
                        label: Text('Peta'),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.list_alt_outlined),
                        label: Text('Daftar'),
                      ),
                    ],
                    selected: <bool>{_showMap},
                    onSelectionChanged: (Set<bool> selected) {
                      setState(() {
                        _showMap = selected.first;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ] else ...<Widget>[
              Text(
                'Status Rider',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
            ],
            if (state.presences.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Belum ada posisi Rider yang diterima untuk Ride ini.',
                  ),
                ),
              )
            else if (widget.mapsEnabled && _showMap)
              LiveGroupMapView(
                presentation: LiveGroupMapPresentation.fromPresences(
                  presences: state.presences,
                  now: now,
                  separation: state.separation,
                ),
                now: now,
                fallback: Column(
                  children: state.presences
                      .map(
                        (LiveRiderPresence presence) =>
                            _PresenceCard(presence: presence, now: now),
                      )
                      .toList(growable: false),
                ),
              )
            else
              ..._attentionFirst(state.presences, now).map(
                (LiveRiderPresence presence) =>
                    _PresenceCard(presence: presence, now: now),
              ),
          ],
        ),
      ),
    );
  }

  List<LiveQuickAction> _newestFirst(List<LiveQuickAction> actions) {
    return actions.toList()..sort(
      (LiveQuickAction a, LiveQuickAction b) =>
          b.raisedAt.compareTo(a.raisedAt),
    );
  }

  /// Offline, then stale, then live: the Riders who need a look come first.
  List<LiveRiderPresence> _attentionFirst(
    List<LiveRiderPresence> presences,
    DateTime now,
  ) {
    int rank(LiveRiderPresence presence) =>
        switch (presence.effectiveFreshness(now)) {
          LivePresenceFreshness.offline => 0,
          LivePresenceFreshness.stale => 1,
          LivePresenceFreshness.live => 2,
        };
    return presences.toList()..sort((LiveRiderPresence a, LiveRiderPresence b) {
      final int byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.displayName.compareTo(b.displayName);
    });
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

  /// [sheetContext] is the note sheet to close after sending; null when the
  /// status comes straight from the bottom bar.
  Future<void> _sendQuickAction(
    BuildContext? sheetContext,
    LiveQuickActionKind kind, {
    String? reason,
  }) async {
    try {
      await widget.controller.raiseQuickAction(kind, reason: reason);
      if (!mounted) {
        return;
      }
      if (sheetContext != null &&
          sheetContext.mounted &&
          Navigator.of(sheetContext).canPop()) {
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
              'Status + keterangan',
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

class _SeparationCard extends StatelessWidget {
  const _SeparationCard({required this.separation});

  final LiveConvoySeparation separation;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String detail;
    final IconData icon;

    switch (separation.phase) {
      case ConvoySeparationPhase.insufficientData:
        title = 'Data jarak rombongan belum cukup';
        detail =
            'Belum ada cukup posisi Rider Live untuk menilai kontinuitas '
            'rombongan. Stale/Offline tetap ditampilkan terpisah.';
        icon = Icons.sensors_off_outlined;
      case ConvoySeparationPhase.splitCandidate:
        title = 'Memeriksa jarak rombongan';
        detail =
            'Posisi Rider Live tampak terbagi, tetapi CommRide masih '
            'menunggu konfirmasi agar satu sampel GPS tidak menjadi alarm.';
        icon = Icons.travel_explore_outlined;
      case ConvoySeparationPhase.separatedAttention:
        if (separation.dataSufficient) {
          title = 'Jarak rombongan melebar';
          detail =
              'Posisi Rider Live mungkin terbagi menjadi '
              '${separation.components.length} kelompok. Periksa kondisi '
              'rombongan; ini bukan kepastian ada Rider tersesat.';
        } else {
          title = 'Perhatian rombongan belum dapat diverifikasi ulang';
          detail =
              'Separation sebelumnya sudah terkonfirmasi, tetapi posisi Live '
              'saat ini belum cukup untuk menyatakan kondisi sudah pulih.';
        }
        icon = Icons.warning_amber_rounded;
      case ConvoySeparationPhase.normal:
        title = 'Rombongan terhubung';
        detail = 'Posisi Rider Live membentuk satu kontinuitas.';
        icon = Icons.link;
    }

    final List<String> facts = <String>[
      if (separation.isolatedRiderIds.isNotEmpty)
        '${separation.isolatedRiderIds.length} Rider terisolasi secara posisi',
      if (separation.sweeperComponentRiderIds != null)
        'Komponen Sweeper: '
            '${separation.sweeperComponentRiderIds!.length} Rider',
    ];

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
                  if (facts.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      facts.join(' · '),
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

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action, required this.now});

  final LiveQuickAction action;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final String age = _formatAge(now.difference(action.raisedAt));

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

/// Same one-tap statuses as the riding dock; long-press adds a note.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.onSend, required this.onAddNote});

  final Future<void> Function(LiveQuickActionKind kind) onSend;
  final Future<void> Function() onAddNote;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.all(8),
        child: SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final LiveQuickActionKind kind
                  in LiveQuickActionKind.values) ...<Widget>[
                if (kind != LiveQuickActionKind.values.first)
                  const SizedBox(width: 6),
                Expanded(
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => unawaited(onSend(kind)),
                      onLongPress: () => unawaited(onAddNote()),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Icon(_quickActionIcon(kind), size: 26),
                          const SizedBox(height: 4),
                          Text(
                            switch (kind) {
                              LiveQuickActionKind.stopping => 'Berhenti',
                              LiveQuickActionKind.leftBehind => 'Tertinggal',
                              LiveQuickActionKind.needHelp => 'Bantuan',
                            },
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
