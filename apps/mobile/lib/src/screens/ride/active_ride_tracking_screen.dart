import 'package:flutter/material.dart';

import '../../active_ride/location_session_controller.dart';
import '../../models/club_ride.dart';

class ActiveRideTrackingScreen extends StatefulWidget {
  const ActiveRideTrackingScreen({
    required this.ride,
    required this.controller,
    super.key,
  });

  final Ride ride;
  final RideLocationSessionController controller;

  @override
  State<ActiveRideTrackingScreen> createState() =>
      _ActiveRideTrackingScreenState();
}

class _ActiveRideTrackingScreenState
    extends State<ActiveRideTrackingScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RideLocationSessionState state = widget.controller.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Active Ride')),
      body: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ListView(
          children: <Widget>[
            Text(
              widget.ride.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            _TrackingStatusCard(state: state),
            const SizedBox(height: 18),
            Text(
              'Berbagi lokasi',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Lokasi dibagikan hanya untuk koordinasi Ride yang sedang '
              'Active. CommRide tidak mulai melacak hanya karena Anda '
              'membuka layar ini.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            if (!state.isTracking &&
                state.phase != RideLocationSessionPhase.starting &&
                state.phase != RideLocationSessionPhase.stopping)
              FilledButton.icon(
                onPressed: widget.ride.status == RideStatus.active
                    ? _confirmStartTracking
                    : null,
                icon: const Icon(Icons.location_searching),
                label: const Text('Aktifkan tracking'),
              ),
            if (state.isTracking)
              OutlinedButton.icon(
                onPressed: widget.controller.stopTracking,
                icon: const Icon(Icons.location_off_outlined),
                label: const Text('Hentikan tracking'),
              ),
            if (state.phase == RideLocationSessionPhase.denied) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _confirmStartTracking,
                child: const Text('Coba izin lokasi lagi'),
              ),
            ],
            if (state.lastSample != null) ...<Widget>[
              const SizedBox(height: 22),
              Text(
                'Observasi terakhir',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _formatObservation(state.lastSample!.observedAt.toLocal()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmStartTracking() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Aktifkan lokasi untuk Ride?'),
          content: const Text(
            'CommRide akan membagikan posisi Anda kepada peserta yang '
            'berhak di Ride ini. Tracking dapat berlanjut saat layar '
            'terkunci atau Anda membuka aplikasi navigasi lain jika '
            'platform mengizinkan. Tracking berhenti saat sesi Ride '
            'dihentikan.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Nanti'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Lanjutkan'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await widget.controller.startTracking(widget.ride);
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _TrackingStatusCard extends StatelessWidget {
  const _TrackingStatusCard({required this.state});

  final RideLocationSessionState state;

  @override
  Widget build(BuildContext context) {
    final (_TrackingTone tone, String title, String detail) =
        _statusContent(state);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(tone.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(detail),
                  if (state.message != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(state.message!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (
    _TrackingTone,
    String,
    String,
  ) _statusContent(RideLocationSessionState state) {
    return switch (state.phase) {
      RideLocationSessionPhase.inactive => (
          _TrackingTone.inactive,
          'Tracking belum aktif',
          'Aktifkan saat Anda siap berbagi posisi untuk Ride ini.',
        ),
      RideLocationSessionPhase.permissionRequired => (
          _TrackingTone.waiting,
          'Menunggu izin lokasi',
          'CommRide hanya meminta izin untuk sesi Active Ride.',
        ),
      RideLocationSessionPhase.starting => (
          _TrackingTone.waiting,
          'Memulai tracking',
          'Menghubungkan lokasi perangkat ke ruang Ride.',
        ),
      RideLocationSessionPhase.active => (
          _TrackingTone.active,
          'Tracking aktif',
          'Posisi terbaru dikirim ke ruang Ride yang terautentikasi.',
        ),
      RideLocationSessionPhase.degraded => (
          _TrackingTone.warning,
          'Tracking terganggu',
          'Posisi terakhir tetap diberi timestamp dan tidak dianggap live.',
        ),
      RideLocationSessionPhase.stopping => (
          _TrackingTone.waiting,
          'Menghentikan tracking',
          'Menutup lokasi perangkat dan koneksi realtime.',
        ),
      RideLocationSessionPhase.stoppedByRideEnd => (
          _TrackingTone.inactive,
          'Tracking berhenti',
          'Ride telah selesai dan sesi lokasi ditutup.',
        ),
      RideLocationSessionPhase.denied => (
          _TrackingTone.warning,
          'Izin lokasi belum diberikan',
          'Anda tetap dapat memakai bagian CommRide yang tidak membutuhkan '
              'lokasi.',
        ),
      RideLocationSessionPhase.error => (
          _TrackingTone.warning,
          'Tracking belum tersedia',
          'Periksa status Ride, izin lokasi, dan koneksi.',
        ),
    };
  }
}

enum _TrackingTone {
  inactive(Icons.location_off_outlined),
  waiting(Icons.hourglass_top_outlined),
  active(Icons.my_location),
  warning(Icons.warning_amber_rounded);

  const _TrackingTone(this.icon);

  final IconData icon;
}

String _formatObservation(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
