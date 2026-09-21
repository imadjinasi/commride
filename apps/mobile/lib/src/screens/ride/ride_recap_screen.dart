import 'package:flutter/material.dart';

import '../../api/ride_recap_api.dart';
import '../../models/ride_recap.dart';

class RideRecapScreen extends StatefulWidget {
  const RideRecapScreen({
    required this.rideId,
    required this.rideRecapApi,
    super.key,
  });

  final String rideId;
  final RideRecapApi rideRecapApi;

  @override
  State<RideRecapScreen> createState() => _RideRecapScreenState();
}

class _RideRecapScreenState extends State<RideRecapScreen> {
  late Future<RideRecap> _recapFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ride Recap')),
      body: FutureBuilder<RideRecap>(
        future: _recapFuture,
        builder: (BuildContext context, AsyncSnapshot<RideRecap> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return SafeArea(
              minimum: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Ride Recap belum dapat dimuat.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(_reload),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            );
          }

          return _RecapBody(recap: snapshot.data!);
        },
      ),
    );
  }

  void _reload() {
    _recapFuture = widget.rideRecapApi.fetchRecap(widget.rideId);
  }
}

class _RecapBody extends StatelessWidget {
  const _RecapBody({required this.recap});

  final RideRecap recap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(20),
      child: ListView(
        children: <Widget>[
          Text(recap.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            _durationLabel(recap.durationSeconds),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (recap.actualStartAt != null && recap.endedAt != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '${_dateTime(recap.actualStartAt!)} – '
              '${_dateTime(recap.endedAt!)}',
            ),
          ],
          const SizedBox(height: 20),
          _PlannedRouteCard(route: recap.plannedRoute),
          const SizedBox(height: 12),
          _JourneyCard(journey: recap.journey),
          const SizedBox(height: 24),
          _SectionTitle(title: 'Riders', count: recap.participants.length),
          const SizedBox(height: 8),
          ...recap.participants.map(
            (RideRecapParticipant participant) => Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(participant.displayName),
                subtitle: Text(participant.role.label),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: 'Checkpoints', count: recap.checkpoints.length),
          const SizedBox(height: 8),
          if (recap.checkpoints.isEmpty)
            const _EmptyCard(message: 'Tidak ada checkpoint pada Ride ini.')
          else
            ...recap.checkpoints.map(
              (RideRecapCheckpoint checkpoint) => Card(
                child: ListTile(
                  leading: Icon(
                    checkpoint.releasedAt == null
                        ? Icons.flag_outlined
                        : Icons.flag,
                  ),
                  title: Text(checkpoint.label),
                  subtitle: Text(
                    '${checkpoint.checkInCount}/'
                    '${checkpoint.participantCount} Rider check-in'
                    '${checkpoint.releasedAt == null ? '' : ' · Released'}',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          _SectionTitle(title: 'Insiden SOS', count: recap.incidents.length),
          const SizedBox(height: 8),
          if (recap.incidents.isEmpty)
            const _EmptyCard(message: 'Tidak ada insiden SOS pada Ride ini.')
          else
            ...recap.incidents.map(
              (RideRecapIncident incident) => Card(
                child: ListTile(
                  leading: const Icon(Icons.sos_outlined),
                  title: Text(incident.riderDisplayName),
                  subtitle: Text(
                    '${_incidentState(incident.state)} · '
                    '${_dateTime(incident.raisedAt)}'
                    '${incident.reason == null ? '' : '\n${incident.reason}'}',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Recap dibuat dari catatan operasional Ride. '
            'Lokasi aktual menggunakan sampel berkala, bukan rekaman '
            'setiap ping GPS.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PlannedRouteCard extends StatelessWidget {
  const _PlannedRouteCard({required this.route});

  final RideRecapPlannedRoute? route;

  @override
  Widget build(BuildContext context) {
    if (route == null) {
      return const _EmptyCard(
        message: 'Rute rencana tidak tersedia untuk Ride ini.',
      );
    }

    final String routeLabel = <String?>[
      route!.originLabel,
      route!.destinationLabel,
    ].whereType<String>().join(' → ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Rencana', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (routeLabel.isNotEmpty) Text(routeLabel),
            Text(
              '${_distance(route!.distanceMeters)} · '
              '${_durationLabel(route!.durationSeconds)} · '
              '${route!.stopCount} stop',
            ),
            const SizedBox(height: 4),
            Text(
              'RoutePlan revision ${route!.revision}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.journey});

  final RideRecapJourney journey;

  @override
  Widget build(BuildContext context) {
    if (!journey.hasSamples) {
      return const _EmptyCard(
        message:
            'Perjalanan aktual: tidak ada sampel lokasi yang tersedia. '
            'CommRide tidak menebak jarak aktual.',
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Perjalanan tersampel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${journey.sampleCount} sampel · '
              '${journey.trackedRiderCount} Rider terlacak',
            ),
            if (journey.leaderTrackedDistanceMeters != null)
              Text(
                'Jejak Leader: '
                '${_distance(journey.leaderTrackedDistanceMeters!)}',
              ),
            if (journey.firstObservedAt != null &&
                journey.lastObservedAt != null)
              Text(
                '${_dateTime(journey.firstObservedAt!)} – '
                '${_dateTime(journey.lastObservedAt!)}',
              ),
            const SizedBox(height: 4),
            Text(
              'Jarak ini berasal dari sampel berkala dan dapat lebih pendek '
              'dari jarak perjalanan sebenarnya.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$title · $count',
      style: Theme.of(context).textTheme.titleLarge,
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

String _durationLabel(int? seconds) {
  if (seconds == null) {
    return 'Durasi tidak tersedia';
  }
  final Duration duration = Duration(seconds: seconds);
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes.remainder(60);
  if (hours == 0) {
    return '$minutes menit';
  }
  return '$hours jam $minutes menit';
}

String _distance(int meters) {
  if (meters < 1000) {
    return '$meters m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

String _dateTime(DateTime value) {
  final DateTime local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} · '
      '${two(local.hour)}:${two(local.minute)}';
}

String _incidentState(String state) {
  return switch (state) {
    'resolved' => 'Selesai',
    'cancelled' => 'Dibatalkan',
    _ => 'Aktif',
  };
}
