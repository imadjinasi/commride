import 'package:flutter/material.dart';

import '../../api/checkpoint_api.dart';
import '../../models/club_ride.dart';
import '../../models/ride_checkpoint.dart';

class CheckpointsScreen extends StatefulWidget {
  const CheckpointsScreen({
    required this.ride,
    required this.membership,
    required this.checkpointApi,
    super.key,
  });

  final Ride ride;
  final RideMembership membership;
  final CheckpointApi checkpointApi;

  @override
  State<CheckpointsScreen> createState() => _CheckpointsScreenState();
}

class _CheckpointsScreenState extends State<CheckpointsScreen> {
  late Future<RideCheckpointView> _viewFuture;
  bool _working = false;

  bool get _canMutate => widget.ride.status == RideStatus.active;
  bool get _isLeader => widget.membership.role == RideRole.leader;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkpoints'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _working ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: FutureBuilder<RideCheckpointView>(
          future: _viewFuture,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<RideCheckpointView> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _LoadError(onRetry: _refresh);
                }

                final RideCheckpointView view = snapshot.data!;
                if (view.checkpoints.isEmpty) {
                  return const _EmptyCheckpoints();
                }

                return ListView(
                  children: <Widget>[
                    Text(
                      widget.ride.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'RoutePlan revision ${view.routePlanRevision}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(Icons.info_outline),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Check-in di sini bersifat manual. '
                                'Ini bukan verifikasi GPS.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...view.checkpoints.map(
                      (RideCheckpointItem checkpoint) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CheckpointCard(
                          checkpoint: checkpoint,
                          canCheckIn:
                              _canMutate && !checkpoint.currentRiderCheckedIn,
                          canRelease:
                              _canMutate &&
                              _isLeader &&
                              checkpoint.state == RideCheckpointState.current,
                          working: _working,
                          onCheckIn: () => _checkIn(checkpoint),
                          onRelease: () => _release(checkpoint),
                        ),
                      ),
                    ),
                  ],
                );
              },
        ),
      ),
    );
  }

  void _reload() {
    _viewFuture = widget.checkpointApi.fetchCheckpoints(widget.ride.id);
  }

  void _refresh() {
    setState(_reload);
  }

  Future<void> _checkIn(RideCheckpointItem checkpoint) async {
    await _run(() {
      return widget.checkpointApi.checkIn(
        rideId: widget.ride.id,
        checkpointId: checkpoint.checkpointId,
      );
    }, successMessage: 'Check-in tercatat.');
  }

  Future<void> _release(RideCheckpointItem checkpoint) async {
    if (checkpoint.missingCount > 0) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Lepas Checkpoint?'),
            content: Text(
              '${checkpoint.missingCount} Rider belum check-in. '
              'Checkpoint tetap dapat dilepas, tetapi Rider tersebut '
              'akan tetap tercatat belum tiba.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Tetap lepas'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    await _run(() {
      return widget.checkpointApi.release(
        rideId: widget.ride.id,
        checkpointId: checkpoint.checkpointId,
      );
    }, successMessage: 'Checkpoint dilepas.');
  }

  Future<void> _run(
    Future<RideCheckpointView> Function() operation, {
    required String successMessage,
  }) async {
    setState(() {
      _working = true;
    });

    try {
      final RideCheckpointView updated = await operation();
      if (!mounted) {
        return;
      }
      setState(() {
        _viewFuture = Future<RideCheckpointView>.value(updated);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status Checkpoint belum dapat diperbarui.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }
}

class _CheckpointCard extends StatelessWidget {
  const _CheckpointCard({
    required this.checkpoint,
    required this.canCheckIn,
    required this.canRelease,
    required this.working,
    required this.onCheckIn,
    required this.onRelease,
  });

  final RideCheckpointItem checkpoint;
  final bool canCheckIn;
  final bool canRelease;
  final bool working;
  final VoidCallback onCheckIn;
  final VoidCallback onRelease;

  @override
  Widget build(BuildContext context) {
    final List<CheckpointParticipant> checkedIn = checkpoint.participants
        .where((CheckpointParticipant item) => item.checkedIn)
        .toList(growable: false);
    final List<CheckpointParticipant> missing = checkpoint.participants
        .where((CheckpointParticipant item) => !item.checkedIn)
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        checkpoint.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        checkpoint.checkpointType.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(checkpoint.state.label)),
              ],
            ),
            if (checkpoint.formattedAddress != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(checkpoint.formattedAddress!),
            ],
            const SizedBox(height: 12),
            Text(
              '${checkpoint.checkedInCount}/${checkpoint.expectedCount} '
              'Rider sudah tiba · ${checkpoint.missingCount} belum',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (checkpoint.releasedAt != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Dilepas ${_formatTime(checkpoint.releasedAt!.toLocal())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Riders'),
              subtitle: Text(
                '${checkedIn.length} arrived · ${missing.length} missing',
              ),
              children: checkpoint.participants
                  .map(
                    (CheckpointParticipant participant) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        participant.checkedIn
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(participant.displayName),
                      subtitle: Text(participant.role.label),
                      trailing: participant.checkedInAt == null
                          ? const Text('Belum')
                          : Text(
                              _formatTime(participant.checkedInAt!.toLocal()),
                            ),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (canCheckIn)
              FilledButton.icon(
                onPressed: working ? null : onCheckIn,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Saya sudah tiba'),
              )
            else if (checkpoint.currentRiderCheckedIn)
              const Row(
                children: <Widget>[
                  Icon(Icons.check_circle_outline, size: 18),
                  SizedBox(width: 7),
                  Text('Anda sudah check-in.'),
                ],
              ),
            if (canRelease) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: working ? null : onRelease,
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Lepas Checkpoint'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Status Checkpoint belum dapat dimuat.'),
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCheckpoints extends StatelessWidget {
  const _EmptyCheckpoints();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Ride ini belum memiliki Stop yang ditandai sebagai Checkpoint.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

String _formatTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}';
}
