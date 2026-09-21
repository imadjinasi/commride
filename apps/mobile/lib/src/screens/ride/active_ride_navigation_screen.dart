import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../../active_ride/active_ride_runtime.dart';
import '../../active_ride/live_group_models.dart';
import '../../api/route_planner_api.dart';
import '../../models/club_ride.dart';
import '../../models/route_planner.dart';

class ActiveRideNavigationScreen extends StatefulWidget {
  const ActiveRideNavigationScreen({
    required this.ride,
    required this.membership,
    required this.runtime,
    required this.routePlannerApi,
    required this.voiceIntercomEnabled,
    required this.onOpenLiveGroup,
    required this.onOpenTracking,
    required this.onOpenSos,
    super.key,
  });

  final Ride ride;
  final RideMembership membership;
  final ActiveRideRuntime runtime;
  final RoutePlannerApi routePlannerApi;
  final bool voiceIntercomEnabled;
  final Future<void> Function() onOpenLiveGroup;
  final Future<void> Function() onOpenTracking;
  final Future<void> Function() onOpenSos;

  @override
  State<ActiveRideNavigationScreen> createState() =>
      _ActiveRideNavigationScreenState();
}

class _ActiveRideNavigationScreenState
    extends State<ActiveRideNavigationScreen> {
  GoogleNavigationViewController? _viewController;
  _PreparedNavigation? _prepared;
  bool _preparing = false;
  bool _guidanceStarting = false;
  bool _guidanceRunning = false;
  bool _markerSyncRunning = false;
  bool _markerSyncPending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.runtime.groupController.addListener(_onGroupChanged);
  }

  @override
  void dispose() {
    widget.runtime.groupController.removeListener(_onGroupChanged);
    if (_guidanceRunning) {
      unawaited(GoogleMapsNavigator.stopGuidance());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupState = widget.runtime.groupController.state;
    final counts = groupState.counts(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ride.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Live Group',
            onPressed: () => unawaited(widget.onOpenLiveGroup()),
            icon: const Icon(Icons.groups_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _GroupStatusBar(
              role: widget.membership.role,
              live: counts.live,
              stale: counts.stale,
              offline: counts.offline,
              connected: groupState.connectionState.name == 'connected',
            ),
            Expanded(
              child: _prepared == null
                  ? _buildPreparation(context)
                  : _buildNavigationMap(),
            ),
            _CommunicationDock(
              voiceIntercomEnabled: widget.voiceIntercomEnabled,
              onOpenLiveGroup: widget.onOpenLiveGroup,
              onOpenTracking: widget.onOpenTracking,
              onOpenSos: widget.onOpenSos,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreparation(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.navigation_outlined, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    'Navigasi Active Ride',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mulai navigasi dan tracking secara eksplisit. CommRide '
                    'akan menampilkan posisi rombongan di atas peta navigasi.',
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _preparing ? null : _prepareNavigation,
                    icon: const Icon(Icons.navigation),
                    label: Text(
                      _preparing
                          ? 'Menyiapkan navigasi...'
                          : 'Mulai navigasi & tracking',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => unawaited(widget.onOpenLiveGroup()),
                    child: const Text('Buka Live Group tanpa navigasi'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationMap() {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GoogleMapsNavigationView(
          onViewCreated: _onViewCreated,
          initialNavigationUIEnabledPreference:
              NavigationUIEnabledPreference.automatic,
          initialMapToolbarEnabled: false,
          initialZoomControlsEnabled: false,
        ),
        if (_guidanceStarting)
          const Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _prepareNavigation() async {
    if (_preparing) return;

    setState(() {
      _preparing = true;
      _error = null;
    });

    try {
      bool termsAccepted = await GoogleMapsNavigator.areTermsAccepted();
      if (!termsAccepted) {
        termsAccepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
          'Navigasi CommRide',
          'CommRide',
        );
      }
      if (!termsAccepted) {
        throw const _NavigationPreparationException(
          'Syarat Google Navigation belum disetujui.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _NavigationPreparationException(
          'Izin lokasi diperlukan untuk navigasi Active Ride.',
        );
      }

      if (!await GoogleMapsNavigator.isInitialized()) {
        await GoogleMapsNavigator.initializeNavigationSession(
          notificationOptions: const NavigationNotificationOptions(
            resumeAppOnTap: true,
          ),
        );
      }

      final SavedRoutePlan? plan = await widget.routePlannerApi.fetchRoutePlan(
        widget.ride.id,
      );
      if (plan == null) {
        throw const _NavigationPreparationException(
          'RoutePlan belum tersedia. Susun dan simpan rute sebelum memulai Ride.',
        );
      }

      final List<RouteOption> refreshed = await widget.routePlannerApi
          .computeRoutes(
            origin: ResolvedPlace(
              reference: 'commride-route-origin',
              formattedAddress: plan.originLabel,
              location: plan.origin,
            ),
            destination: ResolvedPlace(
              reference: 'commride-route-destination',
              formattedAddress: plan.destinationLabel,
              location: plan.destination,
            ),
            stops: plan.stops,
            travelMode: plan.travelMode,
            computeAlternatives: false,
          );
      if (refreshed.isEmpty || refreshed.first.routeToken == null) {
        throw const _NavigationPreparationException(
          'Route Google untuk navigasi belum tersedia. Aktifkan provider '
          'Google lalu hitung ulang RoutePlan ini.',
        );
      }

      if (!widget.runtime.locationSession.state.isTracking) {
        await widget.runtime.locationSession.startTracking(widget.ride);
      }

      if (!mounted) return;
      setState(() {
        _prepared = _PreparedNavigation(plan: plan, route: refreshed.first);
        _preparing = false;
      });
    } on _NavigationPreparationException catch (error) {
      _setPreparationError(error.message);
    } catch (_) {
      _setPreparationError(
        'Navigasi belum dapat disiapkan. Periksa konfigurasi Google Maps '
        'Platform dan koneksi lalu coba lagi.',
      );
    }
  }

  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    _viewController = controller;
    try {
      await controller.setMyLocationEnabled(true);
      await _startGuidanceIfReady();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Peta navigasi belum siap. Coba buka kembali Active Ride.';
        });
      }
    }
  }

  Future<void> _startGuidanceIfReady() async {
    final GoogleNavigationViewController? controller = _viewController;
    final _PreparedNavigation? prepared = _prepared;
    if (controller == null ||
        prepared == null ||
        _guidanceStarting ||
        _guidanceRunning) {
      return;
    }

    final String? routeToken = prepared.route.routeToken;
    if (routeToken == null) return;

    setState(() {
      _guidanceStarting = true;
      _error = null;
    });

    try {
      final List<NavigationWaypoint> waypoints = <NavigationWaypoint>[
        ...prepared.plan.stops.map(
          (PlanningStop stop) => NavigationWaypoint.withLatLngTarget(
            title: stop.label,
            target: LatLng(
              latitude: stop.location.latitude,
              longitude: stop.location.longitude,
            ),
          ),
        ),
        NavigationWaypoint.withLatLngTarget(
          title: prepared.plan.destinationLabel ?? 'Tujuan',
          target: LatLng(
            latitude: prepared.plan.destination.latitude,
            longitude: prepared.plan.destination.longitude,
          ),
        ),
      ];

      final NavigationRouteStatus status =
          await GoogleMapsNavigator.setDestinations(
            Destinations(
              waypoints: waypoints,
              displayOptions: NavigationDisplayOptions(
                showDestinationMarkers: false,
              ),
              routeTokenOptions: RouteTokenOptions(
                routeToken: routeToken,
                travelMode:
                    prepared.plan.travelMode == RouteTravelMode.twoWheeler
                    ? NavigationTravelMode.twoWheeler
                    : NavigationTravelMode.driving,
              ),
            ),
          );

      if (status != NavigationRouteStatus.statusOk) {
        final String statusName = status.name;
        throw _NavigationPreparationException(
          'Google Navigation menolak rute ($statusName).',
        );
      }

      await controller.setNavigationUIEnabled(true);
      await GoogleMapsNavigator.setAudioGuidance(
        NavigationAudioGuidanceSettings(
          isBluetoothAudioEnabled: true,
          guidanceType: NavigationAudioGuidanceType.alertsAndGuidance,
        ),
      );
      await GoogleMapsNavigator.startGuidance();

      if (!mounted) return;
      setState(() {
        _guidanceStarting = false;
        _guidanceRunning = true;
      });
      _scheduleMarkerSync();
    } on _NavigationPreparationException catch (error) {
      if (mounted) {
        setState(() {
          _guidanceStarting = false;
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _guidanceStarting = false;
          _error =
              'Panduan navigasi belum dapat dimulai. Periksa API key, '
              'billing, dan Navigation SDK.';
        });
      }
    }
  }

  void _onGroupChanged() {
    if (mounted) {
      setState(() {});
    }
    _scheduleMarkerSync();
  }

  void _scheduleMarkerSync() {
    if (_viewController == null || !_guidanceRunning) return;
    if (_markerSyncRunning) {
      _markerSyncPending = true;
      return;
    }
    unawaited(_syncMarkers());
  }

  Future<void> _syncMarkers() async {
    final GoogleNavigationViewController? controller = _viewController;
    if (controller == null || _markerSyncRunning) return;

    _markerSyncRunning = true;
    try {
      do {
        _markerSyncPending = false;
        final DateTime now = DateTime.now();
        final List<LiveRiderPresence> presences =
            widget.runtime.groupController.state.presences;

        await controller.clearMarkers();
        if (presences.isNotEmpty) {
          await controller.addMarkers(
            presences
                .map((LiveRiderPresence presence) {
                  final LivePresenceFreshness freshness = presence
                      .effectiveFreshness(now);
                  final double alpha = switch (freshness) {
                    LivePresenceFreshness.live => 1,
                    LivePresenceFreshness.stale => 0.65,
                    LivePresenceFreshness.offline => 0.4,
                  };
                  final String roleLabel = presence.role.label;
                  final String riderName = presence.displayName;
                  final String freshnessLabel = freshness.label;
                  final String movementLabel = presence.movement.name;
                  return MarkerOptions(
                    position: LatLng(
                      latitude: presence.latitude,
                      longitude: presence.longitude,
                    ),
                    alpha: alpha,
                    zIndex:
                        presence.role == RideRole.leader ||
                            presence.role == RideRole.sweeper
                        ? 2
                        : 1,
                    infoWindow: InfoWindow(
                      title: '$roleLabel · $riderName',
                      snippet: '$freshnessLabel · $movementLabel',
                    ),
                  );
                })
                .toList(growable: false),
          );
        }
      } while (_markerSyncPending);
    } catch (_) {
      // Navigation remains authoritative even if a convoy overlay update fails.
    } finally {
      _markerSyncRunning = false;
    }
  }

  void _setPreparationError(String message) {
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _error = message;
    });
  }
}

class _PreparedNavigation {
  const _PreparedNavigation({required this.plan, required this.route});

  final SavedRoutePlan plan;
  final RouteOption route;
}

class _NavigationPreparationException implements Exception {
  const _NavigationPreparationException(this.message);

  final String message;
}

class _GroupStatusBar extends StatelessWidget {
  const _GroupStatusBar({
    required this.role,
    required this.live,
    required this.stale,
    required this.offline,
    required this.connected,
  });

  final RideRole role;
  final int live;
  final int stale;
  final int offline;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final int total = live + stale + offline;
    final String roleLabel = role.label;
    final String staleLabel = stale > 0 ? ' · $stale Stale' : '';
    final String offlineLabel = offline > 0 ? ' · $offline Offline' : '';
    return Material(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Row(
          children: <Widget>[
            Icon(connected ? Icons.wifi : Icons.wifi_off, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$roleLabel · $total Rider · $live Live$staleLabel$offlineLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunicationDock extends StatelessWidget {
  const _CommunicationDock({
    required this.voiceIntercomEnabled,
    required this.onOpenLiveGroup,
    required this.onOpenTracking,
    required this.onOpenSos,
  });

  final bool voiceIntercomEnabled;
  final Future<void> Function() onOpenLiveGroup;
  final Future<void> Function() onOpenTracking;
  final Future<void> Function() onOpenSos;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.headset_mic_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    voiceIntercomEnabled
                        ? 'Group Intercom · media belum terhubung'
                        : 'Group Intercom · belum diaktifkan',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: _DockButton(
                    icon: Icons.mic_off_outlined,
                    label: 'Mic',
                    onPressed: null,
                  ),
                ),
                Expanded(
                  child: _DockButton(
                    icon: Icons.groups_outlined,
                    label: 'Riders',
                    onPressed: () => unawaited(onOpenLiveGroup()),
                  ),
                ),
                Expanded(
                  child: _DockButton(
                    icon: Icons.my_location,
                    label: 'Tracking',
                    onPressed: () => unawaited(onOpenTracking()),
                  ),
                ),
                Expanded(
                  child: _DockButton(
                    icon: Icons.sos,
                    label: 'SOS',
                    critical: true,
                    onPressed: () => unawaited(onOpenSos()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.critical = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final Color? foreground = critical
        ? Theme.of(context).colorScheme.error
        : null;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: foreground),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[Icon(icon), const SizedBox(height: 2), Text(label)],
      ),
    );
  }
}
