import 'package:flutter/material.dart';

import '../../active_ride/active_ride_runtime.dart';
import '../../models/club_ride.dart';
import 'active_ride_tracking_screen.dart';
import 'live_group_screen.dart';

class ActiveRideCommandCenterScreen extends StatefulWidget {
  const ActiveRideCommandCenterScreen({
    required this.ride,
    required this.runtimeManager,
    required this.mapsEnabled,
    super.key,
  });

  final Ride ride;
  final ActiveRideRuntimeManager runtimeManager;
  final bool mapsEnabled;

  @override
  State<ActiveRideCommandCenterScreen> createState() =>
      _ActiveRideCommandCenterScreenState();
}

class _ActiveRideCommandCenterScreenState
    extends State<ActiveRideCommandCenterScreen> {
  late final Future<ActiveRideRuntime> _runtimeFuture;

  @override
  void initState() {
    super.initState();
    _runtimeFuture = widget.runtimeManager.open(widget.ride);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ActiveRideRuntime>(
      future: _runtimeFuture,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<ActiveRideRuntime> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError || snapshot.data == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Active Ride')),
                body: const SafeArea(
                  minimum: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Ruang Active Ride belum dapat dihubungkan. '
                      'Periksa koneksi lalu coba lagi.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            final ActiveRideRuntime runtime = snapshot.data!;
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
                    const SizedBox(height: 8),
                    const Text(
                      'Satu ruang realtime dipakai bersama untuk tracking, '
                      'Live Group, Quick Actions, Comms, dan SOS.',
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _openTracking(runtime),
                      icon: const Icon(Icons.location_searching),
                      label: const Text('Tracking Saya'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: () => _openLiveGroup(runtime),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        widget.mapsEnabled ? 'Live Group · Map' : 'Live Group',
                      ),
                    ),
                    const SizedBox(height: 18),
                    ListenableBuilder(
                      listenable: runtime.locationSession,
                      builder: (BuildContext context, Widget? child) {
                        final state = runtime.locationSession.state;
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              state.isTracking
                                  ? Icons.my_location
                                  : Icons.location_off_outlined,
                            ),
                            title: Text(
                              state.isTracking
                                  ? 'Tracking aktif'
                                  : 'Tracking belum aktif',
                            ),
                            subtitle: Text(
                              state.isTracking
                                  ? 'Lokasi dibagikan hanya untuk Ride ini.'
                                  : 'Aktifkan secara eksplisit saat siap.',
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
    );
  }

  Future<void> _openTracking(ActiveRideRuntime runtime) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ActiveRideTrackingScreen(
          ride: widget.ride,
          controller: runtime.locationSession,
        ),
      ),
    );
  }

  Future<void> _openLiveGroup(ActiveRideRuntime runtime) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => LiveGroupScreen(
          ride: widget.ride,
          controller: runtime.groupController,
          mapsEnabled: widget.mapsEnabled,
        ),
      ),
    );
  }
}
