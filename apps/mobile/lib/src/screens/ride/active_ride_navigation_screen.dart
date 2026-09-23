import 'dart:async';

import 'package:flutter/material.dart';

import '../../active_ride/active_ride_runtime.dart';
import '../../active_ride/commride_navigation_engine.dart';
import '../../active_ride/location_provider.dart';
import '../../active_ride/realtime_client.dart';
import '../../api/route_planner_api.dart';
import '../../maps/commride_navigation_map_view.dart';
import '../../models/club_ride.dart';
import '../../models/route_planner.dart';
import 'ride_quick_actions_sheet.dart';
import 'route_planner_screen.dart';

class ActiveRideNavigationScreen extends StatefulWidget {
  const ActiveRideNavigationScreen({
    required this.ride,
    required this.membership,
    required this.runtime,
    required this.routePlannerApi,
    required this.voiceIntercomEnabled,
    required this.onOpenLiveGroup,
    required this.onOpenTracking,
    required this.onOpenComms,
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
  final Future<void> Function() onOpenComms;
  final Future<void> Function() onOpenSos;

  @override
  State<ActiveRideNavigationScreen> createState() =>
      _ActiveRideNavigationScreenState();
}

class _ActiveRideNavigationScreenState
    extends State<ActiveRideNavigationScreen> {
  _PreparedNavigation? _prepared;
  CommRideNavigationSnapshot? _snapshot;
  RouteOption? _recoveryRoute;
  CommRideNavigationEngine? _recoveryEngine;
  CommRideNavigationSnapshot? _recoverySnapshot;
  List<TrafficIncident> _trafficIncidents = const <TrafficIncident>[];
  bool _preparing = false;
  bool _recoveryRouteLoading = false;
  bool _routeRevisionRefreshing = false;
  bool _rerouteSearching = false;
  bool _trafficUnavailable = false;
  bool _trafficRefreshDegraded = false;
  DateTime? _trafficUpdatedAt;
  Timer? _trafficRefreshTimer;
  DateTime? _lastObservedAt;
  DateTime? _lastRecoveryRequestAt;
  GeoPoint? _lastRecoveryOrigin;
  GeoPoint? _lastRecoveryTarget;
  int _recoveryRequestGeneration = 0;
  StreamSubscription<ActiveRideRealtimeEvent>? _realtimeSubscription;
  String? _error;
  String? _guidanceNotice;

  bool get _canManageRoute =>
      widget.membership.role == RideRole.leader ||
      widget.membership.role == RideRole.navigator;

  @override
  void initState() {
    super.initState();
    widget.runtime.groupController.addListener(_onGroupChanged);
    widget.runtime.locationSession.addListener(_onLocationChanged);
    _realtimeSubscription = widget.runtime.realtimeClient.events.listen(
      _onRealtimeEvent,
    );
  }

  @override
  void dispose() {
    widget.runtime.groupController.removeListener(_onGroupChanged);
    widget.runtime.locationSession.removeListener(_onLocationChanged);
    _trafficRefreshTimer?.cancel();
    unawaited(_realtimeSubscription?.cancel());
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
          if (_canManageRoute)
            IconButton(
              tooltip: 'Rute',
              onPressed:
                  _preparing || _routeRevisionRefreshing || _rerouteSearching
                  ? null
                  : _showRouteActions,
              icon: const Icon(Icons.alt_route),
            ),
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
                  : _buildNavigationSurface(),
            ),
            _CommunicationDock(
              voiceIntercomEnabled: widget.voiceIntercomEnabled,
              onOpenTracking: widget.onOpenTracking,
              onOpenComms: widget.onOpenComms,
              onOpenQuickActions: _openQuickActions,
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
                    'CommRide memakai RoutePlan yang sudah disepakati. '
                    'Jika Anda menyimpang, rute tidak akan diganti diam-diam: '
                    'CommRide akan membantu kembali ke rute utama.',
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

  Widget _buildNavigationSurface() {
    final _PreparedNavigation prepared = _prepared!;
    final groupState = widget.runtime.groupController.state;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CommRideNavigationMapView(
          routePoints: prepared.engine.routePoints,
          routeRevision: prepared.plan.revision,
          recoveryRoutePoints: _recoveryRoute == null
              ? const <GeoPoint>[]
              : decodeRoutePolyline(_recoveryRoute!.encodedPolyline),
          snapshot: _snapshot,
          presences: groupState.presences,
          incidents: _trafficIncidents,
          now: DateTime.now(),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: _NavigationBanner(
            snapshot: _snapshot,
            recoverySnapshot: _recoverySnapshot,
            recoveryRouteLoading: _recoveryRouteLoading,
            trafficCount: _trafficIncidents.length,
            trafficUpdatedAt: _trafficUpdatedAt,
            trafficRefreshDegraded: _trafficRefreshDegraded,
            guidanceNotice: _guidanceNotice,
            rerouteBusy: _rerouteSearching,
            onFindNewRoute: _snapshot?.shouldOfferReroute == true
                ? _findNewRoute
                : null,
          ),
        ),
        if (_routeRevisionRefreshing ||
            _rerouteSearching ||
            _recoveryRouteLoading)
          const Positioned(
            left: 12,
            right: 12,
            top: 4,
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

  Future<void> _openQuickActions() {
    return showRideQuickActionsSheet(
      context,
      onSend: widget.runtime.groupController.raiseQuickAction,
    );
  }

  Future<void> _prepareNavigation() async {
    if (_preparing) return;

    setState(() {
      _preparing = true;
      _error = null;
    });

    try {
      final SavedRoutePlan? plan = await widget.routePlannerApi.fetchRoutePlan(
        widget.ride.id,
      );
      if (plan == null) {
        throw const _NavigationPreparationException(
          'RoutePlan belum tersedia. Susun dan simpan rute sebelum '
          'memulai Ride.',
        );
      }

      final CommRideNavigationEngine engine = CommRideNavigationEngine(plan);

      if (!widget.runtime.locationSession.state.isTracking) {
        await widget.runtime.locationSession.startTracking(widget.ride);
      }

      if (!mounted) return;
      _resetRecoveryRouteState();
      setState(() {
        _prepared = _PreparedNavigation(plan: plan, engine: engine);
        _preparing = false;
        _guidanceNotice = plan.route.maneuvers.isEmpty
            ? 'RoutePlan lama belum memiliki instruksi belok. '
                  'Simpan ulang rute untuk turn-by-turn lengkap.'
            : null;
      });

      _consumeLatestLocation();
      _startTrafficRefresh();
      unawaited(_refreshTraffic(plan.route));
    } on _NavigationPreparationException catch (error) {
      _setPreparationError(error.message);
    } on FormatException {
      _setPreparationError(
        'Geometry RoutePlan tidak valid. Review dan simpan ulang rute.',
      );
    } catch (_) {
      _setPreparationError(
        'Navigasi belum dapat disiapkan. RoutePlan lama tetap tidak diubah.',
      );
    }
  }

  Future<void> _showRouteActions() async {
    if (!_canManageRoute) return;

    final RoutePlannerInitialAction? action =
        await showModalBottomSheet<RoutePlannerInitialAction>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const ListTile(
                  title: Text('Rute saat riding'),
                  subtitle: Text(
                    'Perubahan rute baru berlaku setelah RoutePlan baru '
                    'disimpan. GPS tidak pernah menggantinya otomatis.',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add_location_alt_outlined),
                  title: const Text('Tambah Stop'),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(RoutePlannerInitialAction.addStop),
                ),
                ListTile(
                  leading: const Icon(Icons.search),
                  title: const Text('Cari sepanjang rute'),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(RoutePlannerInitialAction.searchAlongRoute),
                ),
                ListTile(
                  leading: const Icon(Icons.route_outlined),
                  title: const Text('Kelola RoutePlan lengkap'),
                  onTap: () =>
                      Navigator.of(context).pop(RoutePlannerInitialAction.none),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );

    if (action == null || !mounted) return;
    await _openRoutePlanner(initialAction: action);
  }

  Future<void> _openRoutePlanner({
    RoutePlannerInitialAction initialAction = RoutePlannerInitialAction.none,
  }) async {
    if (!_canManageRoute) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoutePlannerScreen(
          rideId: widget.ride.id,
          routePlannerApi: widget.routePlannerApi,
          canEdit: true,
          initialAction: initialAction,
        ),
      ),
    );

    if (mounted && _prepared != null) {
      await _refreshRouteRevision();
    }
  }

  void _onRealtimeEvent(ActiveRideRealtimeEvent event) {
    final _PreparedNavigation? prepared = _prepared;
    if (event is! ActiveRideRoutePlanUpdated ||
        event.rideId != widget.ride.id ||
        prepared == null ||
        event.revision <= prepared.plan.revision) {
      return;
    }

    unawaited(_refreshRouteRevision(expectedRevision: event.revision));
  }

  Future<void> _refreshRouteRevision({int? expectedRevision}) async {
    final _PreparedNavigation? current = _prepared;
    if (_routeRevisionRefreshing || _preparing || current == null) {
      return;
    }
    if (expectedRevision != null && expectedRevision <= current.plan.revision) {
      return;
    }

    _routeRevisionRefreshing = true;
    if (mounted) setState(() {});

    try {
      final SavedRoutePlan? plan = await widget.routePlannerApi.fetchRoutePlan(
        widget.ride.id,
      );
      if (plan == null || plan.revision <= current.plan.revision) {
        return;
      }

      final CommRideNavigationEngine engine = CommRideNavigationEngine(plan);
      if (!mounted) return;

      _resetRecoveryRouteState();
      setState(() {
        _prepared = _PreparedNavigation(plan: plan, engine: engine);
        _snapshot = null;
        _guidanceNotice = plan.route.maneuvers.isEmpty
            ? 'RoutePlan terbaru belum memiliki instruksi belok.'
            : null;
        _error = null;
      });
      _lastObservedAt = null;
      _consumeLatestLocation();
      unawaited(_refreshTraffic(plan.route));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('RoutePlan revision ${plan.revision} diterapkan.'),
          ),
        );
      }
    } on FormatException {
      if (mounted) {
        setState(() {
          _error =
              'RoutePlan terbaru tidak valid. Rute sebelumnya tidak '
              'diganti di layar navigasi.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'RoutePlan terbaru belum dapat diterapkan. Navigasi tetap '
              'mempertahankan rute terakhir yang valid.';
        });
      }
    } finally {
      _routeRevisionRefreshing = false;
      if (mounted) setState(() {});
    }
  }

  void _onLocationChanged() {
    _consumeLatestLocation();
  }

  void _consumeLatestLocation() {
    final _PreparedNavigation? prepared = _prepared;
    final RideLocationSample? sample =
        widget.runtime.locationSession.state.lastSample;
    if (prepared == null ||
        sample == null ||
        sample.observedAt == _lastObservedAt) {
      return;
    }

    _lastObservedAt = sample.observedAt;
    final GeoPoint currentLocation = GeoPoint(
      latitude: sample.latitude,
      longitude: sample.longitude,
    );
    final CommRideNavigationSnapshot next = prepared.engine.update(
      currentLocation,
      sample.observedAt,
    );

    CommRideNavigationSnapshot? recoverySnapshot;
    if (next.isRecovering && _recoveryEngine != null) {
      recoverySnapshot = _recoveryEngine!.update(
        currentLocation,
        sample.observedAt,
      );
    } else if (!next.isRecovering) {
      _resetRecoveryRouteState();
    }

    if (!mounted) return;
    setState(() {
      _snapshot = next;
      _recoverySnapshot = recoverySnapshot;
    });

    if (next.isRecovering) {
      unawaited(
        _ensureRecoveryRoute(
          snapshot: next,
          currentLocation: currentLocation,
          observedAt: sample.observedAt,
        ),
      );
    }
  }

  Future<void> _ensureRecoveryRoute({
    required CommRideNavigationSnapshot snapshot,
    required GeoPoint currentLocation,
    required DateTime observedAt,
  }) async {
    final _PreparedNavigation? prepared = _prepared;
    final GeoPoint? target = snapshot.rejoinTarget;
    if (prepared == null ||
        target == null ||
        !snapshot.isRecovering ||
        _recoveryRouteLoading ||
        !shouldRefreshRecoveryRoute(
          origin: currentLocation,
          target: target,
          observedAt: observedAt,
          lastOrigin: _lastRecoveryOrigin,
          lastTarget: _lastRecoveryTarget,
          lastRequestedAt: _lastRecoveryRequestAt,
        )) {
      return;
    }

    final int generation = ++_recoveryRequestGeneration;
    _recoveryRouteLoading = true;
    _lastRecoveryRequestAt = observedAt;
    _lastRecoveryOrigin = currentLocation;
    _lastRecoveryTarget = target;
    if (mounted) setState(() {});

    try {
      final List<RouteOption> routes = await widget.routePlannerApi
          .computeRoutes(
            origin: ResolvedPlace(
              reference: 'commride-recovery-origin',
              formattedAddress: 'Posisi sekarang',
              location: currentLocation,
            ),
            destination: ResolvedPlace(
              reference: 'commride-rejoin-target',
              formattedAddress: 'Kembali ke rute utama',
              location: target,
            ),
            stops: const <PlanningStop>[],
            travelMode: prepared.plan.travelMode,
            computeAlternatives: false,
          );
      if (routes.isEmpty) return;

      final RouteOption recoveryRoute = routes.first;
      if (decodeRoutePolyline(recoveryRoute.encodedPolyline).length < 2) {
        return;
      }

      final SavedRoutePlan recoveryPlan = SavedRoutePlan(
        revision: prepared.plan.revision,
        travelMode: prepared.plan.travelMode,
        originLabel: 'Posisi sekarang',
        origin: currentLocation,
        destinationLabel: 'Kembali ke rute utama',
        destination: target,
        route: recoveryRoute,
        stops: const <PlanningStop>[],
      );
      final CommRideNavigationEngine recoveryEngine = CommRideNavigationEngine(
        recoveryPlan,
      );

      final RideLocationSample? latest =
          widget.runtime.locationSession.state.lastSample;
      final CommRideNavigationSnapshot? latestSnapshot = latest == null
          ? null
          : recoveryEngine.update(
              GeoPoint(latitude: latest.latitude, longitude: latest.longitude),
              latest.observedAt,
            );

      final GeoPoint? currentTarget = _snapshot?.rejoinTarget;
      if (!mounted ||
          generation != _recoveryRequestGeneration ||
          _prepared?.plan.revision != prepared.plan.revision ||
          _snapshot?.isRecovering != true ||
          currentTarget == null ||
          geoDistanceMeters(currentTarget, target) > 250) {
        return;
      }

      setState(() {
        _recoveryRoute = recoveryRoute;
        _recoveryEngine = recoveryEngine;
        _recoverySnapshot = latestSnapshot;
      });
    } catch (_) {
      // Recovery routing is advisory. Keep the accepted RoutePlan and the
      // explicit rejoin target; never draw a fake road path on provider error.
    } finally {
      if (generation == _recoveryRequestGeneration) {
        _recoveryRouteLoading = false;
        if (mounted) setState(() {});
      }
    }
  }

  void _resetRecoveryRouteState() {
    _recoveryRequestGeneration += 1;
    _recoveryRouteLoading = false;
    _recoveryRoute = null;
    _recoveryEngine = null;
    _recoverySnapshot = null;
    _lastRecoveryRequestAt = null;
    _lastRecoveryOrigin = null;
    _lastRecoveryTarget = null;
  }

  void _onGroupChanged() {
    if (mounted) setState(() {});
  }

  void _startTrafficRefresh() {
    _trafficRefreshTimer?.cancel();
    if (_trafficUnavailable) return;

    _trafficRefreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      final RouteOption? route = _prepared?.plan.route;
      if (route != null) {
        unawaited(_refreshTraffic(route));
      }
    });
  }

  Future<void> _refreshTraffic(RouteOption route) async {
    if (_trafficUnavailable) return;

    try {
      final List<TrafficIncident> incidents = await widget.routePlannerApi
          .fetchTrafficIncidents(route);
      if (!mounted ||
          _prepared?.plan.route.encodedPolyline != route.encodedPolyline) {
        return;
      }
      setState(() {
        _trafficIncidents = incidents;
        _trafficUpdatedAt = DateTime.now();
        _trafficRefreshDegraded = false;
      });
    } on RoutePlannerApiException catch (error) {
      if (error.code == 'traffic_not_configured') {
        _trafficUnavailable = true;
        _trafficRefreshTimer?.cancel();
        if (mounted) {
          setState(() {
            _trafficIncidents = const <TrafficIncident>[];
            _trafficUpdatedAt = null;
            _trafficRefreshDegraded = false;
          });
        }
        return;
      }
      _markTrafficRefreshDegraded();
    } catch (_) {
      _markTrafficRefreshDegraded();
    }
  }

  void _markTrafficRefreshDegraded() {
    if (!mounted) return;
    final DateTime now = DateTime.now();
    final DateTime? updatedAt = _trafficUpdatedAt;
    final bool tooOld =
        updatedAt == null ||
        now.difference(updatedAt) > const Duration(minutes: 30);

    setState(() {
      _trafficRefreshDegraded = true;
      if (tooOld) {
        _trafficIncidents = const <TrafficIncident>[];
      }
    });
  }

  Future<void> _findNewRoute() async {
    final _PreparedNavigation? prepared = _prepared;
    final CommRideNavigationSnapshot? snapshot = _snapshot;
    final RideLocationSample? sample =
        widget.runtime.locationSession.state.lastSample;
    if (prepared == null ||
        snapshot == null ||
        sample == null ||
        _rerouteSearching) {
      return;
    }

    if (!_canManageRoute) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Rute Ride tetap dipertahankan'),
          content: const Text(
            'Hanya Leader atau Navigator yang dapat mengganti shared '
            'RoutePlan. CommRide akan tetap membantu Anda kembali ke rute '
            'utama.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _rerouteSearching = true;
      _error = null;
    });

    try {
      final GeoPoint currentLocation = GeoPoint(
        latitude: sample.latitude,
        longitude: sample.longitude,
      );
      final List<PlanningStop> remainingStops = prepared.plan.stops
          .where(
            (PlanningStop stop) =>
                prepared.engine.closestShapeIndex(stop.location) >
                snapshot.routeProgressShapeIndex,
          )
          .toList(growable: false);

      final ResolvedPlace current = ResolvedPlace(
        reference: 'commride-current-location',
        formattedAddress: 'Posisi sekarang',
        location: currentLocation,
      );
      final ResolvedPlace destination = ResolvedPlace(
        reference: 'commride-route-destination',
        formattedAddress: prepared.plan.destinationLabel,
        location: prepared.plan.destination,
      );

      final List<RouteOption> candidates = await widget.routePlannerApi
          .computeRoutes(
            origin: current,
            destination: destination,
            stops: remainingStops,
            travelMode: prepared.plan.travelMode,
            computeAlternatives: remainingStops.isEmpty,
          );
      if (candidates.isEmpty) {
        throw const _NavigationPreparationException(
          'Belum ditemukan kandidat rute baru.',
        );
      }

      if (!mounted) return;
      final RouteOption? selected = await _selectCandidate(candidates);
      if (selected == null || !mounted) return;

      final bool confirm = await _confirmReplacement(
        selected,
        remainingStops.length,
      );
      if (!confirm || !mounted) return;

      final SavedRoutePlan saved = await widget.routePlannerApi.saveRoutePlan(
        rideId: widget.ride.id,
        origin: current,
        destination: destination,
        route: selected,
        travelMode: prepared.plan.travelMode,
        stops: remainingStops,
      );

      final CommRideNavigationEngine engine = CommRideNavigationEngine(saved);
      if (!mounted) return;
      _resetRecoveryRouteState();
      setState(() {
        _prepared = _PreparedNavigation(plan: saved, engine: engine);
        _snapshot = null;
        _guidanceNotice = saved.route.maneuvers.isEmpty
            ? 'Rute baru tersimpan tanpa instruksi belok lengkap.'
            : null;
      });
      _lastObservedAt = null;
      _consumeLatestLocation();
      unawaited(_refreshTraffic(saved.route));

      final bool broadcastOk = saved.activeRideBroadcast != false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            broadcastOk
                ? 'RoutePlan baru disimpan untuk Ride.'
                : 'RoutePlan baru tersimpan, tetapi broadcast realtime '
                      'sedang terganggu.',
          ),
        ),
      );
    } on _NavigationPreparationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on RoutePlannerApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Rute baru belum dapat dihitung. RoutePlan lama tetap '
              'dipertahankan.';
        });
      }
    } finally {
      _rerouteSearching = false;
      if (mounted) setState(() {});
    }
  }

  Future<RouteOption?> _selectCandidate(List<RouteOption> candidates) async {
    return showModalBottomSheet<RouteOption>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const ListTile(
              title: Text('Kandidat rute baru'),
              subtitle: Text(
                'RoutePlan Ride belum berubah. Pilih kandidat untuk '
                'ditinjau.',
              ),
            ),
            ...candidates.map(
              (RouteOption route) => ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(
                  '${_formatDistance(route.distanceMeters.toDouble())} · '
                  '${_formatDuration(route.durationSeconds)}',
                ),
                subtitle: Text(
                  route.labels.isEmpty
                      ? 'Kandidat rute'
                      : route.labels.join(' · '),
                ),
                onTap: () => Navigator.of(context).pop(route),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmReplacement(
    RouteOption route,
    int remainingStopCount,
  ) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Ganti RoutePlan Ride?'),
        content: Text(
          'Rute baru: ${_formatDistance(route.distanceMeters.toDouble())}, '
          '${_formatDuration(route.durationSeconds)}.'
          '${remainingStopCount > 0 ? ' $remainingStopCount Stop yang masih '
                    'di depan akan dipertahankan.' : ''}\n\n'
          'Rute lama baru diganti setelah Anda menekan Gunakan rute baru.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tetap rute lama'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gunakan rute baru'),
          ),
        ],
      ),
    );
    return result ?? false;
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
  const _PreparedNavigation({required this.plan, required this.engine});

  final SavedRoutePlan plan;
  final CommRideNavigationEngine engine;
}

class _NavigationPreparationException implements Exception {
  const _NavigationPreparationException(this.message);

  final String message;
}

class _NavigationBanner extends StatelessWidget {
  const _NavigationBanner({
    required this.snapshot,
    required this.recoverySnapshot,
    required this.recoveryRouteLoading,
    required this.trafficCount,
    required this.trafficUpdatedAt,
    required this.trafficRefreshDegraded,
    required this.guidanceNotice,
    required this.rerouteBusy,
    required this.onFindNewRoute,
  });

  final CommRideNavigationSnapshot? snapshot;
  final CommRideNavigationSnapshot? recoverySnapshot;
  final bool recoveryRouteLoading;
  final int trafficCount;
  final DateTime? trafficUpdatedAt;
  final bool trafficRefreshDegraded;
  final String? guidanceNotice;
  final bool rerouteBusy;
  final Future<void> Function()? onFindNewRoute;

  @override
  Widget build(BuildContext context) {
    final CommRideNavigationSnapshot? state = snapshot;
    final _BannerCopy copy = _copy(state, recoverySnapshot);

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(copy.icon, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        copy.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (copy.subtitle != null)
                        Text(
                          copy.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (trafficCount > 0)
                  Chip(
                    avatar: Icon(
                      trafficRefreshDegraded
                          ? Icons.sync_problem_outlined
                          : Icons.traffic,
                      size: 16,
                    ),
                    label: Text(
                      trafficUpdatedAt == null
                          ? '$trafficCount'
                          : '$trafficCount · '
                                '${_formatTrafficAge(trafficUpdatedAt!)}',
                    ),
                    visualDensity: VisualDensity.compact,
                  )
                else if (trafficRefreshDegraded)
                  const Chip(
                    avatar: Icon(Icons.sync_problem_outlined, size: 16),
                    label: Text('Traffic terganggu'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (guidanceNotice != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                guidanceNotice!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (onFindNewRoute != null) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: rerouteBusy
                      ? null
                      : () => unawaited(onFindNewRoute!()),
                  icon: const Icon(Icons.alt_route),
                  label: const Text('Cari rute baru'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _BannerCopy _copy(
    CommRideNavigationSnapshot? state,
    CommRideNavigationSnapshot? recovery,
  ) {
    if (state == null) {
      return const _BannerCopy(
        icon: Icons.gps_fixed,
        title: 'Menunggu posisi GPS…',
        subtitle: 'RoutePlan tetap siap di peta.',
      );
    }

    switch (state.phase) {
      case CommRideNavigationPhase.suspectedOffRoute:
        return _BannerCopy(
          icon: Icons.gps_not_fixed,
          title: 'Memeriksa posisi terhadap rute',
          subtitle:
              'RoutePlan belum berubah · '
              '${_formatDistance(state.distanceFromRouteMeters)} dari jalur',
        );
      case CommRideNavigationPhase.confirmedOffRoute:
      case CommRideNavigationPhase.recovery:
        final RouteManeuver? recoveryManeuver = recovery?.nextManeuver;
        final String recoveryDistance = state.distanceToRejoinMeters == null
            ? 'kembali ke rute utama'
            : '${_formatDistance(state.distanceToRejoinMeters!)} ke titik rejoin';
        return _BannerCopy(
          icon: recoveryManeuver == null
              ? Icons.u_turn_left
              : _maneuverIcon(recoveryManeuver.type),
          title:
              recoveryManeuver?.instruction ??
              (recoveryRouteLoading
                  ? 'Menyiapkan jalur kembali…'
                  : 'Kembali ke rute utama'),
          subtitle: 'Anda keluar dari rute · $recoveryDistance',
        );
      case CommRideNavigationPhase.rejoined:
        return const _BannerCopy(
          icon: Icons.check_circle_outline,
          title: 'Kembali ke rute utama',
          subtitle: 'RoutePlan yang sama tetap digunakan.',
        );
      case CommRideNavigationPhase.onRoute:
        final RouteManeuver? maneuver = state.nextManeuver;
        if (maneuver == null) {
          return const _BannerCopy(
            icon: Icons.navigation,
            title: 'Ikuti RoutePlan',
            subtitle: 'Tidak ada manuver berikutnya yang tersedia.',
          );
        }
        return _BannerCopy(
          icon: _maneuverIcon(maneuver.type),
          title: maneuver.instruction,
          subtitle: state.distanceToNextManeuverMeters == null
              ? null
              : _formatDistance(state.distanceToNextManeuverMeters!),
        );
    }
  }
}

class _BannerCopy {
  const _BannerCopy({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
}

IconData _maneuverIcon(String? type) {
  final String normalized = type?.toLowerCase() ?? '';
  if (normalized.contains('left')) return Icons.turn_left;
  if (normalized.contains('right')) return Icons.turn_right;
  if (normalized.contains('uturn') || normalized.contains('u_turn')) {
    return Icons.u_turn_left;
  }
  if (normalized.contains('roundabout')) return Icons.roundabout_left;
  return Icons.straight;
}

String _formatDistance(double meters) {
  if (meters < 1000) {
    return '${meters.round()} m';
  }
  return '${(meters / 1000).toStringAsFixed(meters >= 10000 ? 0 : 1)} km';
}

String _formatTrafficAge(DateTime updatedAt) {
  final Duration age = DateTime.now().difference(updatedAt);
  if (age.inMinutes < 1) return 'baru';
  if (age.inHours < 1) return '${age.inMinutes}m';
  return '${age.inHours}j';
}

String _formatDuration(int seconds) {
  final int minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes mnt';
  final int hours = minutes ~/ 60;
  final int remainder = minutes % 60;
  return remainder == 0 ? '$hours jam' : '$hours jam $remainder mnt';
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
    required this.onOpenTracking,
    required this.onOpenComms,
    required this.onOpenQuickActions,
    required this.onOpenSos,
  });

  final bool voiceIntercomEnabled;
  final Future<void> Function() onOpenTracking;
  final Future<void> Function() onOpenComms;
  final Future<void> Function() onOpenQuickActions;
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
                    icon: Icons.bolt_outlined,
                    label: 'Status',
                    onPressed: () => unawaited(onOpenQuickActions()),
                  ),
                ),
                Expanded(
                  child: _DockButton(
                    icon: Icons.forum_outlined,
                    label: 'Comms',
                    onPressed: () => unawaited(onOpenComms()),
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
