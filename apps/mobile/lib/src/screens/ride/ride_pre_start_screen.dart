import 'package:flutter/material.dart';

import '../../api/ride_briefing_api.dart';
import '../../models/club_ride.dart';
import '../../models/ride_briefing.dart';

class RidePreStartScreen extends StatefulWidget {
  const RidePreStartScreen({
    required this.ride,
    required this.rideBriefingApi,
    super.key,
  });

  final Ride ride;
  final RideBriefingApi rideBriefingApi;

  @override
  State<RidePreStartScreen> createState() => _RidePreStartScreenState();
}

class _RidePreStartScreenState extends State<RidePreStartScreen> {
  late Future<RideBriefingView?> _briefingFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sebelum Start Ride')),
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: FutureBuilder<RideBriefingView?>(
          future: _briefingFuture,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<RideBriefingView?> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _LoadError(
                    onRetry: _refresh,
                    onContinue: () => Navigator.of(context).pop(true),
                  );
                }

                final RideBriefingView? view = snapshot.data;
                return ListView(
                  children: <Widget>[
                    Text(
                      widget.ride.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Review kesiapan rombongan sebelum Ride menjadi Active.',
                    ),
                    const SizedBox(height: 20),
                    _BriefingReadinessCard(view: view),
                    const SizedBox(height: 12),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Start Ride tidak menyalakan GPS Rider lain secara '
                          'otomatis. Setiap Rider tetap mengaktifkan tracking '
                          'secara eksplisit dari Active Ride.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(
                        view == null || !view.routePlanIsCurrent
                            ? 'Tetap Start Ride'
                            : 'Start Ride',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Kembali'),
                    ),
                  ],
                );
              },
        ),
      ),
    );
  }

  void _reload() {
    _briefingFuture = widget.rideBriefingApi.fetchBriefing(widget.ride.id);
  }

  void _refresh() {
    setState(_reload);
  }
}

class _BriefingReadinessCard extends StatelessWidget {
  const _BriefingReadinessCard({required this.view});

  final RideBriefingView? view;

  @override
  Widget build(BuildContext context) {
    if (view == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Briefing belum dipublikasikan. Readiness bersifat advisory pada '
            'MVP, tetapi Leader sebaiknya memastikan rombongan memahami rute '
            'dan peran sebelum berangkat.',
          ),
        ),
      );
    }

    final BriefingReadiness readiness = view!.readiness;
    final int pending = readiness.expectedCount - readiness.readyCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Briefing v${view!.briefing.revision}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${readiness.readyCount}/${readiness.expectedCount} Rider Ready',
            ),
            if (pending > 0) ...<Widget>[
              const SizedBox(height: 6),
              Text('$pending Rider belum menandai Ready.'),
            ],
            if (!view!.routePlanIsCurrent) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                'RoutePlan sudah berubah setelah Briefing dipublikasikan. '
                'Sebaiknya publish Briefing baru sebelum berangkat.',
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Readiness bersifat advisory dan tidak memblokir Start Ride.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry, required this.onContinue});

  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('Status Briefing belum dapat dimuat.'),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Coba lagi'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onContinue,
            child: const Text('Start tanpa status Briefing'),
          ),
        ],
      ),
    );
  }
}
