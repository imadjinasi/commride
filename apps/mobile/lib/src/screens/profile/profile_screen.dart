import 'package:flutter/material.dart';

import '../../api/vehicle_api.dart';
import '../../auth/auth_gateway.dart';
import '../../models/rider_profile.dart';
import '../../models/vehicle_profile.dart';
import '../../push/ride_push_controller.dart';
import '../../push/ride_push_messaging.dart';
import 'vehicle_editor_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.riderProfile,
    required this.vehicleApi,
    required this.authGateway,
    this.ridePushController,
    super.key,
  });

  final RiderProfile riderProfile;
  final VehicleApi vehicleApi;
  final AuthGateway authGateway;
  final RidePushController? ridePushController;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<List<VehicleProfile>> _vehiclesFuture;

  @override
  void initState() {
    super.initState();
    _reloadVehicles();
  }

  @override
  Widget build(BuildContext context) {
    final RiderProfile profile = widget.riderProfile;

    return CustomScrollView(
      slivers: <Widget>[
        const SliverAppBar.large(title: Text('Profile')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverList.list(
            children: <Widget>[
              Text(
                profile.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (profile.callsign != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  profile.callsign!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              if (profile.homeArea != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  profile.homeArea!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Kendaraan',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openAddVehicle,
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<VehicleProfile>>(
                future: _vehiclesFuture,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<VehicleProfile>> snapshot,
                    ) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return _VehicleLoadError(onRetry: _refreshVehicles);
                      }

                      final List<VehicleProfile> vehicles =
                          snapshot.data ?? const <VehicleProfile>[];

                      if (vehicles.isEmpty) {
                        return const _EmptyVehicles();
                      }

                      return Column(
                        children: vehicles
                            .map((VehicleProfile vehicle) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _VehicleCard(
                                  vehicle: vehicle,
                                  onEdit: () => _openEditVehicle(vehicle),
                                  onDelete: () => _deleteVehicle(vehicle),
                                ),
                              );
                            })
                            .toList(growable: false),
                      );
                    },
              ),
              const SizedBox(height: 24),
              if (widget.ridePushController != null) ...<Widget>[
                _RideNotificationCard(controller: widget.ridePushController!),
                const SizedBox(height: 24),
              ],
              const Divider(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Keluar'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _signOut() async {
    await widget.ridePushController?.unregisterBestEffort();
    await widget.authGateway.signOut();
  }

  void _reloadVehicles() {
    _vehiclesFuture = widget.vehicleApi.listVehicles();
  }

  void _refreshVehicles() {
    setState(_reloadVehicles);
  }

  Future<void> _openAddVehicle() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return VehicleEditorScreen(
            vehicleApi: widget.vehicleApi,
            onSaved: (_) => _refreshVehicles(),
          );
        },
      ),
    );
  }

  Future<void> _openEditVehicle(VehicleProfile vehicle) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) {
          return VehicleEditorScreen(
            vehicleApi: widget.vehicleApi,
            vehicle: vehicle,
            onSaved: (_) => _refreshVehicles(),
          );
        },
      ),
    );
  }

  Future<void> _deleteVehicle(VehicleProfile vehicle) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Hapus kendaraan?'),
          content: Text(
            '${vehicle.displayName} akan dihapus dari profil Rider Anda.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.vehicleApi.deleteVehicle(vehicle.id);
      if (mounted) {
        _refreshVehicles();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendaraan belum dapat dihapus.')),
      );
    }
  }
}

class _RideNotificationCard extends StatelessWidget {
  const _RideNotificationCard({required this.controller});

  final RidePushController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final RidePushState state = controller.state;
        final String status = switch (state.permission) {
          RidePushPermission.authorized || RidePushPermission.provisional
              when state.registered =>
            'Aktif untuk alert Ride penting.',
          RidePushPermission.authorized || RidePushPermission.provisional =>
            'Izin aktif, tetapi perangkat belum terdaftar.',
          RidePushPermission.denied =>
            'Izin notifikasi ditolak pada perangkat ini.',
          RidePushPermission.notDetermined =>
            'Belum diaktifkan. CommRide tidak meminta izin otomatis.',
        };

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.notifications_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Notifikasi Ride',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(status),
                if (state.latestError != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    state.latestError!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (!state.registered) ...<Widget>[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: state.working ? null : controller.enable,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(
                      state.working
                          ? 'Mengaktifkan…'
                          : 'Aktifkan notifikasi Ride',
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.onEdit,
    required this.onDelete,
  });

  final VehicleProfile vehicle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final List<String> details = <String>[
      vehicle.kind.label,
      if (vehicle.fuelType != null) vehicle.fuelType!,
      if (vehicle.safeRangeKm != null) 'Safe range ${vehicle.safeRangeKm} km',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          children: <Widget>[
            const Icon(Icons.two_wheeler_outlined),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    vehicle.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    details.join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit kendaraan',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Hapus kendaraan',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyVehicles extends StatelessWidget {
  const _EmptyVehicles();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          'Belum ada kendaraan. Tambahkan kendaraan agar Ride nanti dapat '
          'menggunakan informasi jenis kendaraan dan safe range BBM.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _VehicleLoadError extends StatelessWidget {
  const _VehicleLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Daftar kendaraan belum dapat dimuat.'),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}
