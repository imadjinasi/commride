import 'package:flutter/material.dart';

import '../../api/ride_briefing_api.dart';
import '../../api/route_planner_api.dart';
import '../../models/club_ride.dart';
import '../../models/ride_briefing.dart';
import '../../models/route_planner.dart';

class RideBriefingScreen extends StatefulWidget {
  const RideBriefingScreen({
    required this.ride,
    required this.rideBriefingApi,
    required this.routePlannerApi,
    required this.canPublish,
    required this.canAcknowledge,
    super.key,
  });

  final Ride ride;
  final RideBriefingApi rideBriefingApi;
  final RoutePlannerApi routePlannerApi;
  final bool canPublish;
  final bool canAcknowledge;

  @override
  State<RideBriefingScreen> createState() => _RideBriefingScreenState();
}

class _RideBriefingScreenState extends State<RideBriefingScreen> {
  late Future<_BriefingState> _stateFuture;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Briefing')),
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: FutureBuilder<_BriefingState>(
          future: _stateFuture,
          builder: (
            BuildContext context,
            AsyncSnapshot<_BriefingState> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorState(onRetry: _refresh);
            }

            final _BriefingState state =
                snapshot.data ?? const _BriefingState();
            final RideBriefingView? view = state.view;
            if (view == null) {
              return _buildUnpublished(state.currentPlan);
            }

            return _buildPublished(view);
          },
        ),
      ),
    );
  }

  Widget _buildUnpublished(SavedRoutePlan? currentPlan) {
    if (!widget.canPublish) {
      return const Center(
        child: Text(
          'Leader belum mempublikasikan Briefing untuk Ride ini.',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (currentPlan == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.route_outlined, size: 42),
            const SizedBox(height: 14),
            const Text(
              'Simpan RoutePlan terlebih dahulu sebelum membuat Briefing.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _working ? null : _refresh,
              child: const Text('Muat ulang'),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: <Widget>[
        Text(
          widget.ride.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Review rencana terakhir sebelum dibagikan ke Rider.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        _RouteSummary(routePlan: currentPlan),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _working
              ? null
              : () => _publishBriefing(
                    currentNotes: widget.ride.notes,
                  ),
          icon: const Icon(Icons.campaign_outlined),
          label: Text(_working ? 'Mempublikasikan…' : 'Publish Briefing'),
        ),
      ],
    );
  }

  Widget _buildPublished(RideBriefingView view) {
    final RideBriefing briefing = view.briefing;
    final BriefingReadiness readiness = view.readiness;

    return ListView(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.ride.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Chip(label: Text('Briefing v${briefing.revision}')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Dipublikasikan ${_formatDateTime(briefing.publishedAt.toLocal())}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (!view.routePlanIsCurrent) ...<Widget>[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.warning_amber_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'RoutePlan sudah berubah setelah Briefing ini '
                      'dipublikasikan. Rider tidak dapat menandai Ready '
                      'sampai Leader mempublikasikan Briefing baru.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _InfoCard(
          title: 'Waktu & Peran',
          children: <Widget>[
            _InfoRow(
              label: 'Berangkat',
              value: briefing.scheduledStartAt == null
                  ? 'Belum dijadwalkan'
                  : _formatDateTime(
                      briefing.scheduledStartAt!.toLocal(),
                    ),
            ),
            _InfoRow(
              label: 'Leader',
              value: briefing.leader.displayName,
            ),
            _InfoRow(
              label: 'Sweeper',
              value: briefing.sweeper?.displayName ?? 'Belum ditetapkan',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _RouteSummary(routePlan: view.routePlan),
        if (briefing.notes != null) ...<Widget>[
          const SizedBox(height: 12),
          _InfoCard(
            title: 'Catatan',
            children: <Widget>[Text(briefing.notes!)],
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Readiness',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${readiness.readyCount}/${readiness.expectedCount} '
                  'Rider sudah membaca Briefing ini.',
                ),
                if (readiness.currentRiderAcknowledged) ...<Widget>[
                  const SizedBox(height: 12),
                  const Chip(
                    avatar: Icon(Icons.check, size: 18),
                    label: Text('Ready · Sudah dibaca'),
                  ),
                ] else if (widget.canAcknowledge &&
                    view.routePlanIsCurrent) ...<Widget>[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _working ? null : _acknowledge,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      _working ? 'Menyimpan…' : 'Ready · Sudah dibaca',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (widget.canPublish) ...<Widget>[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () => _publishBriefing(
                      currentNotes: briefing.notes,
                    ),
            icon: const Icon(Icons.refresh),
            label: Text(
              view.routePlanIsCurrent
                  ? 'Perbarui Briefing'
                  : 'Publish Briefing Baru',
            ),
          ),
        ],
      ],
    );
  }

  void _reload() {
    _stateFuture = _loadState();
  }

  void _refresh() {
    setState(_reload);
  }

  Future<_BriefingState> _loadState() async {
    final RideBriefingView? view =
        await widget.rideBriefingApi.fetchBriefing(widget.ride.id);
    if (view != null) {
      return _BriefingState(view: view);
    }

    if (!widget.canPublish) {
      return const _BriefingState();
    }

    final SavedRoutePlan? currentPlan =
        await widget.routePlannerApi.fetchRoutePlan(widget.ride.id);
    return _BriefingState(currentPlan: currentPlan);
  }

  Future<void> _publishBriefing({
    required String? currentNotes,
  }) async {
    final String? notes = await showDialog<String?>(
      context: context,
      builder: (BuildContext context) => _BriefingNotesDialog(
        initialNotes: currentNotes,
      ),
    );

    if (!mounted || notes == _cancelledDialogValue) {
      return;
    }

    await _run(() async {
      final RideBriefingView view =
          await widget.rideBriefingApi.publishBriefing(
        rideId: widget.ride.id,
        notes: notes,
      );
      _replaceState(view);
      _showMessage('Briefing v${view.briefing.revision} dipublikasikan.');
    });
  }

  Future<void> _acknowledge() async {
    await _run(() async {
      final RideBriefingView view =
          await widget.rideBriefingApi.acknowledgeBriefing(
        widget.ride.id,
      );
      _replaceState(view);
      _showMessage('Readiness tersimpan untuk Briefing ini.');
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_working) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await operation();
    } on RideBriefingApiException catch (error) {
      if (!mounted) {
        return;
      }

      if (error.code == 'briefing_stale') {
        _showMessage(
          'RoutePlan sudah berubah. Leader perlu publish Briefing baru.',
        );
      } else {
        _showMessage('Briefing belum dapat diperbarui.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Briefing belum dapat diperbarui.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  void _replaceState(RideBriefingView view) {
    if (!mounted) {
      return;
    }

    setState(() {
      _stateFuture = Future<_BriefingState>.value(
        _BriefingState(view: view),
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

const String _cancelledDialogValue = '__commride_cancelled__';

class _BriefingNotesDialog extends StatefulWidget {
  const _BriefingNotesDialog({required this.initialNotes});

  final String? initialNotes;

  @override
  State<_BriefingNotesDialog> createState() => _BriefingNotesDialogState();
}

class _BriefingNotesDialogState extends State<_BriefingNotesDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Publish Briefing'),
      content: TextField(
        controller: _controller,
        maxLines: 5,
        maxLength: 4000,
        decoration: const InputDecoration(
          labelText: 'Catatan penting',
          hintText: 'Contoh: kumpul 05:30, isi BBM sebelum berangkat.',
          border: OutlineInputBorder(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_cancelledDialogValue),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final String value = _controller.text.trim();
            Navigator.of(context).pop(value.isEmpty ? null : value);
          },
          child: const Text('Publish'),
        ),
      ],
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.routePlan});

  final SavedRoutePlan routePlan;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Route',
      children: <Widget>[
        Text(
          '${_formatDistance(routePlan.route.distanceMeters)} · '
          '${_formatDuration(routePlan.route.durationSeconds)}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          '${routePlan.originLabel ?? 'Start'} → '
          '${routePlan.destinationLabel ?? 'Finish'}',
        ),
        if (routePlan.stops.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          ...routePlan.stops.asMap().entries.map(
            (MapEntry<int, PlanningStop> entry) {
              final PlanningStop stop = entry.value;
              final String checkpoint = stop.checkpointType == null
                  ? ''
                  : ' · ${stop.checkpointType!.label}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${entry.key + 1}. ${stop.label}${checkpoint}',
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Briefing belum dapat dimuat.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}

class _BriefingState {
  const _BriefingState({
    this.view,
    this.currentPlan,
  });

  final RideBriefingView? view;
  final SavedRoutePlan? currentPlan;
}

String _formatDistance(int meters) {
  if (meters < 1000) {
    return '$meters m';
  }

  final double km = meters / 1000;
  return '${km.toStringAsFixed(km >= 100 ? 0 : 1)} km';
}

String _formatDuration(int seconds) {
  final int minutes = (seconds / 60).round();
  final int hours = minutes ~/ 60;
  final int remainder = minutes % 60;

  if (hours == 0) {
    return '$minutes mnt';
  }
  if (remainder == 0) {
    return '$hours jam';
  }
  return '$hours j $remainder mnt';
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} · '
      '${two(value.hour)}:${two(value.minute)}';
}
