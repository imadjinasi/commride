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
            if (state.quickActions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                'Perlu perhatian',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...state.quickActions.take(5).map(
                (LiveQuickAction action) => _QuickActionCard(
                  action: action,
                  now: _now,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Riders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
                (LiveRiderPresence presence) => _PresenceCard(
                  presence: presence,
                  now: _now,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
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
          detail = 'Posisi yang terlihat adalah data terakhir dengan timestamp.';
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
            Expanded(child: _Count(label: 'Live', value: counts.live)),
            Expanded(child: _Count(label: 'Stale', value: counts.stale)),
            Expanded(child: _Count(label: 'Offline', value: counts.offline)),
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
    final LivePresenceFreshness freshness =
        presence.effectiveFreshness(now);
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
