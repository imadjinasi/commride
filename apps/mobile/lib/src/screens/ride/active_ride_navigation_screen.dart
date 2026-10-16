import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../active_ride/active_ride_runtime.dart';
import '../../active_ride/commride_navigation_engine.dart';
import '../../active_ride/convoy_separation.dart';
import '../../active_ride/live_group_controller.dart';
import '../../active_ride/live_group_models.dart';
import '../../active_ride/ride_sos_controller.dart';
import '../../active_ride/location_provider.dart';
import '../../active_ride/realtime_client.dart';
import '../../api/ride_sos_api.dart';
import '../../api/route_planner_api.dart';
import '../../maps/commride_navigation_map_view.dart';
import '../../models/club_ride.dart';
import '../../models/ride_sos.dart';
import '../../platform/media_keys.dart';
import '../../models/route_planner.dart';
import '../../theme/commride_theme.dart';
import '../../widgets/active_ride_quick_actions.dart';
import '../../widgets/sos_hold_button.dart';
import '../../widgets/location_disclosure_dialog.dart';
import 'route_planner_screen.dart';

class ActiveRideNavigationScreen extends StatefulWidget {
  const ActiveRideNavigationScreen({
    required this.ride,
    required this.membership,
    required this.runtime,
    required this.routePlannerApi,
    required this.rideSosApi,
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
  final RideSosApi rideSosApi;
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
  bool _sendingQuickAction = false;
  bool _showGroup = false;
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
  late final RideSosController _sosController;

  bool get _canManageRoute =>
      widget.membership.role == RideRole.leader ||
      widget.membership.role == RideRole.navigator;

  @override
  void initState() {
    super.initState();
    _sosController = RideSosController(
      rideId: widget.ride.id,
      api: widget.rideSosApi,
      realtimeClient: widget.runtime.realtimeClient,
    );
    _sosController.addListener(_onSosChanged);
    _sosController.start();
    unawaited(_sosController.load());
    widget.runtime.groupController.addListener(_onGroupChanged);
    widget.runtime.locationSession.addListener(_onLocationChanged);
    _realtimeSubscription = widget.runtime.realtimeClient.events.listen(
      _onRealtimeEvent,
    );
  }

  @override
  void dispose() {
    _sosController.removeListener(_onSosChanged);
    _sosController.dispose();
    widget.runtime.groupController.removeListener(_onGroupChanged);
    widget.runtime.locationSession.removeListener(_onLocationChanged);
    _trafficRefreshTimer?.cancel();
    unawaited(_realtimeSubscription?.cancel());
    _keepScreenOn(false);
    super.dispose();
  }

  void _keepScreenOn(bool enabled) {
    unawaited(
      WakelockPlus.toggle(enable: enabled).catchError((Object _) {
        // Best effort: the ride continues if the platform refuses.
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupState = widget.runtime.groupController.state;
    final DateTime now = DateTime.now();
    final counts = groupState.counts(now);
    final RideSosViewState sosState = _sosController.state;
    final bool connected = groupState.connectionState.name == 'connected';

    // Riding layout: the map fills the screen, compact overlays sit on top and
    // every in-ride action is one tap (or a 3-second hold for SOS) on the
    // bottom dock. Nothing important needs scrolling or a second screen.
    return Scaffold(
      body: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (_prepared == null)
                  ColoredBox(color: Theme.of(context).colorScheme.surface)
                else
                  _buildMap(),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CommRideSpacing.xs,
                      CommRideSpacing.xs,
                      CommRideSpacing.xs,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_prepared != null &&
                            MediaKeys.supported) ...<Widget>[
                          const _MusicBar(),
                          const SizedBox(height: CommRideSpacing.xs),
                        ],
                        _RidingTopBar(
                          title: widget.ride.title,
                          live: counts.live,
                          stale: counts.stale,
                          offline: counts.offline,
                          connected: connected,
                          started: _prepared != null,
                          onOpenGroup: widget.onOpenLiveGroup,
                          menu: _buildMenu(),
                        ),
                        if (_prepared != null) ...<Widget>[
                          const SizedBox(height: CommRideSpacing.xs),
                          _IntercomBar(
                            voiceIntercomEnabled: widget.voiceIntercomEnabled,
                          ),
                        ],
                        if (_attention(groupState, sosState, now, connected)
                            case final _Attention attention) ...<Widget>[
                          const SizedBox(height: CommRideSpacing.xs),
                          _AttentionStrip(attention: attention),
                        ],
                        if (_prepared != null) ...<Widget>[
                          const SizedBox(height: CommRideSpacing.xs),
                          _NavigationBanner(
                            snapshot: _snapshot,
                            recoverySnapshot: _recoverySnapshot,
                            recoveryRouteLoading: _recoveryRouteLoading,
                            remaining: _remaining(),
                            trafficCount: _trafficIncidents.length,
                            trafficUpdatedAt: _trafficUpdatedAt,
                            trafficRefreshDegraded: _trafficRefreshDegraded,
                            guidanceNotice: _guidanceNotice,
                            rerouteBusy: _rerouteSearching,
                            onFindNewRoute:
                                _snapshot?.shouldOfferReroute == true
                                ? _findNewRoute
                                : null,
                          ),
                        ],
                        if (_prepared == null)
                          Expanded(child: _buildPreparation(context)),
                      ],
                    ),
                  ),
                ),
                if (_prepared != null)
                  Positioned(
                    right: 12,
                    bottom: _error == null ? 12 : 84,
                    child: _RoundSurface(
                      child: IconButton(
                        tooltip: _showGroup
                            ? 'Ikuti posisi saya'
                            : 'Lihat rombongan',
                        iconSize: 28,
                        padding: const EdgeInsets.all(12),
                        onPressed: () =>
                            setState(() => _showGroup = !_showGroup),
                        icon: Icon(
                          _showGroup ? Icons.navigation : Icons.groups,
                        ),
                      ),
                    ),
                  ),
                if (_routeRevisionRefreshing ||
                    _rerouteSearching ||
                    _recoveryRouteLoading)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(),
                  ),
                if (_prepared != null && _error != null)
                  Positioned(
                    left: 12,
                    right: 76,
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
            ),
          ),
          _RidingDock(
            voiceIntercomEnabled: widget.voiceIntercomEnabled,
            sosState: sosState,
            hasOwnActiveSos: sosState.activeItems.any(
              (item) => item.riderId == widget.membership.riderId,
            ),
            sendingQuickAction: _sendingQuickAction,
            onQuickAction: _sendQuickAction,
            onQuickActionWithReason: _showQuickActions,
            onRaiseSos: _raiseSos,
            onRetrySos: _retrySos,
          ),
        ],
      ),
    );
  }

  Widget _buildMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Menu Ride',
      icon: const Icon(Icons.more_vert),
      onSelected: (String value) {
        switch (value) {
          case 'route':
            unawaited(_showRouteActions());
          case 'status':
            unawaited(_showQuickActions());
          case 'comms':
            unawaited(widget.onOpenComms());
          case 'tracking':
            unawaited(widget.onOpenTracking());
          case 'sos-detail':
            unawaited(widget.onOpenSos());
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        if (_canManageRoute)
          PopupMenuItem<String>(
            value: 'route',
            enabled:
                !_preparing && !_routeRevisionRefreshing && !_rerouteSearching,
            child: const ListTile(
              leading: Icon(Icons.alt_route),
              title: Text('Kelola rute'),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'status',
          child: ListTile(
            leading: Icon(Icons.edit_note),
            title: Text('Status + keterangan'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'comms',
          child: ListTile(
            leading: Icon(Icons.forum_outlined),
            title: Text('Comms'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'tracking',
          child: ListTile(
            leading: Icon(Icons.my_location),
            title: Text('Pengaturan tracking'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'sos-detail',
          child: ListTile(
            leading: Icon(Icons.sos_outlined),
            title: Text('Detail SOS'),
          ),
        ),
      ],
    );
  }

  /// The single most urgent thing about other Riders, shown on the map so
  /// Leader and Sweeper see it without opening another screen.
  _Attention? _attention(
    ActiveRideGroupState groupState,
    RideSosViewState sosState,
    DateTime now,
    bool connected,
  ) {
    final String me = widget.membership.riderId;
    for (final RideSos sos in sosState.activeItems) {
      if (sos.riderId != me) {
        return _Attention(
          critical: true,
          icon: Icons.sos,
          message: 'SOS dari ${sos.riderDisplayName}',
          onTap: widget.onOpenSos,
        );
      }
    }

    final List<LiveQuickAction> recent = groupState.quickActions
        .where(
          (LiveQuickAction action) =>
              action.riderId != me &&
              now.difference(action.raisedAt) < const Duration(minutes: 10),
        )
        .toList(growable: false);
    if (recent.isNotEmpty) {
      final LiveQuickAction latest = recent.reduce(
        (LiveQuickAction a, LiveQuickAction b) =>
            a.raisedAt.isAfter(b.raisedAt) ? a : b,
      );
      return _Attention(
        critical: latest.kind == LiveQuickActionKind.needHelp,
        icon: _quickActionIcon(latest.kind),
        message:
            '${latest.displayName}: ${latest.kind.label} · '
            '${_formatAge(now.difference(latest.raisedAt))}',
        onTap: widget.onOpenLiveGroup,
      );
    }

    if (groupState.separation?.phase ==
        ConvoySeparationPhase.separatedAttention) {
      return _Attention(
        critical: false,
        icon: Icons.call_split,
        message: 'Rombongan terpisah · cek posisi',
        onTap: widget.onOpenLiveGroup,
      );
    }

    if (!connected && _prepared != null) {
      return _Attention(
        critical: false,
        icon: Icons.link_off,
        message: 'Koneksi terputus · posisi teman mungkin lama',
        onTap: widget.onOpenLiveGroup,
      );
    }
    return null;
  }

  ({double meters, int seconds})? _remaining() {
    final _PreparedNavigation? prepared = _prepared;
    final CommRideNavigationSnapshot? snapshot = _snapshot;
    if (prepared == null || snapshot == null) {
      return null;
    }
    final RouteOption route = prepared.plan.route;
    final double total = route.distanceMeters.toDouble();
    if (total <= 0) {
      return null;
    }
    final double meters = (total - snapshot.routeProgressMeters).clamp(
      0,
      total,
    );
    final int seconds = (route.durationSeconds * meters / total).round();
    return (meters: meters, seconds: seconds);
  }

  Future<void> _sendQuickAction(LiveQuickActionKind kind) async {
    if (_sendingQuickAction) {
      return;
    }
    setState(() => _sendingQuickAction = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await widget.runtime.groupController.raiseQuickAction(kind);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${kind.label} terkirim ke rombongan.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Status belum terkirim. Periksa koneksi lalu coba lagi.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingQuickAction = false);
      }
    }
  }

  Widget _buildPreparation(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CommRideSpacing.xs,
        CommRideSpacing.md,
        CommRideSpacing.xs,
        CommRideSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Spacer(),
          const Icon(Icons.navigation_outlined, size: 48),
          const SizedBox(height: CommRideSpacing.sm),
          Text(
            'Siap berangkat?',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CommRideSpacing.xs),
          const Text(
            'Rute yang sudah disepakati dipakai untuk navigasi. Kalau Anda '
            'keluar jalur, CommRide membantu kembali ke rute tanpa '
            'menggantinya diam-diam.',
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: CommRideSpacing.sm),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(CommRideTargets.activeRide),
            ),
            onPressed: _preparing ? null : _prepareNavigation,
            icon: const Icon(Icons.navigation),
            label: Text(
              _preparing ? 'Menyiapkan navigasi…' : 'Mulai navigasi & tracking',
            ),
          ),
          const SizedBox(height: CommRideSpacing.xs),
          TextButton(
            onPressed: () => unawaited(widget.onOpenLiveGroup()),
            child: const Text('Lihat rombongan tanpa navigasi'),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final _PreparedNavigation prepared = _prepared!;
    final groupState = widget.runtime.groupController.state;

    return CommRideNavigationMapView(
      routePoints: prepared.engine.routePoints,
      routeRevision: prepared.plan.revision,
      recoveryRoutePoints: _recoveryRoute == null
          ? const <GeoPoint>[]
          : decodeRoutePolyline(_recoveryRoute!.encodedPolyline),
      snapshot: _snapshot,
      presences: groupState.presences,
      incidents: _trafficIncidents,
      now: DateTime.now(),
      selfRiderId: widget.membership.riderId,
      showGroup: _showGroup,
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
        await widget.runtime.locationSession.startTracking(
          widget.ride,
          beforePermissionRequest: () => showLocationDisclosure(context),
        );
      }

      if (!mounted) return;
      _resetRecoveryRouteState();
      setState(() {
        _prepared = _PreparedNavigation(plan: plan, engine: engine);
        // A mounted phone must not dim mid-ride while navigation is shown.
        _keepScreenOn(true);
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
        // A mounted phone must not dim mid-ride while navigation is shown.
        _keepScreenOn(true);
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

  void _onSosChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showQuickActions() async {
    await showActiveRideQuickActions(
      context: context,
      controller: widget.runtime.groupController,
    );
  }

  Future<void> _raiseSos() async {
    try {
      await _sosController.raise(null);
    } catch (_) {
      // Controller retains the same idempotency key for an explicit retry.
    }
  }

  Future<void> _retrySos() async {
    try {
      await _sosController.retryFailedRaise();
    } catch (_) {
      // Visible retry state remains until the request succeeds.
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
    required this.remaining,
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
  final ({double meters, int seconds})? remaining;
  final int trafficCount;
  final DateTime? trafficUpdatedAt;
  final bool trafficRefreshDegraded;
  final String? guidanceNotice;
  final bool rerouteBusy;
  final Future<void> Function()? onFindNewRoute;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _BannerCopy copy = _copy(snapshot, recoverySnapshot);
    final bool offRoute =
        snapshot?.phase == CommRideNavigationPhase.confirmedOffRoute ||
        snapshot?.phase == CommRideNavigationPhase.recovery;
    final ({double meters, int seconds})? left = remaining;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(CommRideRadii.lg),
      color: offRoute ? CommRideColors.signalOrange : CommRideColors.commBlack,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: offRoute ? CommRideColors.commBlack : Colors.white,
        ),
        child: IconTheme.merge(
          data: IconThemeData(
            color: offRoute ? CommRideColors.commBlack : Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(copy.icon, size: 44),
                    const SizedBox(width: CommRideSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (copy.lead != null)
                            Text(
                              copy.lead!,
                              style: const TextStyle(
                                fontSize: 30,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          Text(
                            copy.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        copy.subtitle ??
                            (left == null
                                ? ''
                                : 'Sisa ${_formatDistance(left.meters)} · '
                                      '±${_formatDuration(left.seconds)}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (trafficCount > 0 || trafficRefreshDegraded) ...<Widget>[
                      Icon(
                        trafficRefreshDegraded
                            ? Icons.sync_problem_outlined
                            : Icons.traffic,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        trafficCount == 0
                            ? 'terganggu'
                            : trafficUpdatedAt == null
                            ? '$trafficCount'
                            : '$trafficCount · '
                                  '${_formatTrafficAge(trafficUpdatedAt!)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
                if (guidanceNotice != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    guidanceNotice!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: offRoute
                          ? CommRideColors.commBlack
                          : Colors.white70,
                    ),
                  ),
                ],
                if (onFindNewRoute != null) ...<Widget>[
                  const SizedBox(height: CommRideSpacing.xs),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        CommRideTargets.minimum,
                      ),
                      backgroundColor: CommRideColors.commBlack,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: rerouteBusy
                        ? null
                        : () => unawaited(onFindNewRoute!()),
                    icon: const Icon(Icons.alt_route),
                    label: const Text('Cari rute baru'),
                  ),
                ],
              ],
            ),
          ),
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
        subtitle: 'Rute tetap siap di peta.',
      );
    }

    switch (state.phase) {
      case CommRideNavigationPhase.suspectedOffRoute:
        return _BannerCopy(
          icon: Icons.gps_not_fixed,
          title: 'Memeriksa posisi terhadap rute',
          subtitle:
              '${_formatDistance(state.distanceFromRouteMeters)} dari jalur',
        );
      case CommRideNavigationPhase.confirmedOffRoute:
      case CommRideNavigationPhase.recovery:
        final RouteManeuver? recoveryManeuver = recovery?.nextManeuver;
        return _BannerCopy(
          icon: recoveryManeuver == null
              ? Icons.u_turn_left
              : _maneuverIcon(recoveryManeuver.type),
          lead: state.distanceToRejoinMeters == null
              ? null
              : _formatDistance(state.distanceToRejoinMeters!),
          title:
              recoveryManeuver?.instruction ??
              (recoveryRouteLoading
                  ? 'Menyiapkan jalan kembali…'
                  : 'Kembali ke rute utama'),
          subtitle: 'Keluar rute · rute rombongan tidak berubah',
        );
      case CommRideNavigationPhase.rejoined:
        return const _BannerCopy(
          icon: Icons.check_circle_outline,
          title: 'Kembali di rute utama',
        );
      case CommRideNavigationPhase.onRoute:
        final RouteManeuver? maneuver = state.nextManeuver;
        if (maneuver == null) {
          return const _BannerCopy(icon: Icons.navigation, title: 'Ikuti rute');
        }
        return _BannerCopy(
          icon: _maneuverIcon(maneuver.type),
          lead: state.distanceToNextManeuverMeters == null
              ? null
              : _formatDistance(state.distanceToNextManeuverMeters!),
          title: maneuver.instruction,
        );
    }
  }
}

class _BannerCopy {
  const _BannerCopy({
    required this.icon,
    required this.title,
    this.lead,
    this.subtitle,
  });

  final IconData icon;
  final String? lead;
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

IconData _quickActionIcon(LiveQuickActionKind kind) {
  return switch (kind) {
    LiveQuickActionKind.stopping => Icons.pan_tool_outlined,
    LiveQuickActionKind.leftBehind => Icons.person_pin_circle_outlined,
    LiveQuickActionKind.needHelp => Icons.support_outlined,
  };
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

String _formatAge(Duration age) {
  if (age.inMinutes < 1) return 'baru saja';
  return '${age.inMinutes} mnt lalu';
}

String _formatDuration(int seconds) {
  final int minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes mnt';
  final int hours = minutes ~/ 60;
  final int remainder = minutes % 60;
  return remainder == 0 ? '$hours jam' : '$hours jam $remainder mnt';
}

/// Back, a tappable group summary and the Ride menu in one compact row
/// floating over the map.
class _RidingTopBar extends StatelessWidget {
  const _RidingTopBar({
    required this.title,
    required this.live,
    required this.stale,
    required this.offline,
    required this.connected,
    required this.started,
    required this.onOpenGroup,
    required this.menu,
  });

  final String title;
  final bool started;
  final int live;
  final int stale;
  final int offline;
  final bool connected;
  final Future<void> Function() onOpenGroup;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool attention = stale > 0 || offline > 0 || (started && !connected);
    final int total = live + stale + offline;

    return Row(
      children: <Widget>[
        _RoundSurface(
          child: IconButton(
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        const SizedBox(width: CommRideSpacing.xs),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Buka rombongan',
            child: Material(
              elevation: 3,
              color: colors.surface,
              borderRadius: BorderRadius.circular(CommRideRadii.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(CommRideRadii.lg),
                onTap: () => unawaited(onOpenGroup()),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: CommRideTargets.minimum - 8,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          connected || !started ? Icons.groups : Icons.link_off,
                          size: 22,
                          color: attention ? colors.error : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              Text(
                                _summary(total),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: attention ? colors.error : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: CommRideSpacing.xs),
        _RoundSurface(child: menu),
      ],
    );
  }

  String _summary(int total) {
    if (!started && !connected) return 'Lihat rombongan';
    if (!connected) return 'Koneksi terputus';
    final List<String> parts = <String>['$live/$total Live'];
    if (stale > 0) parts.add('$stale lama');
    if (offline > 0) parts.add('$offline offline');
    return parts.join(' · ');
  }
}

class _RoundSurface extends StatelessWidget {
  const _RoundSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: Theme.of(context).colorScheme.surface,
      child: child,
    );
  }
}

class _Attention {
  const _Attention({
    required this.critical,
    required this.icon,
    required this.message,
    required this.onTap,
  });

  final bool critical;
  final IconData icon;
  final String message;
  final Future<void> Function() onTap;
}

class _AttentionStrip extends StatelessWidget {
  const _AttentionStrip({required this.attention});

  final _Attention attention;

  @override
  Widget build(BuildContext context) {
    final Color background = attention.critical
        ? CommRideColors.criticalRed
        : CommRideColors.signalOrange;
    final Color foreground = attention.critical
        ? Colors.white
        : CommRideColors.commBlack;

    return Semantics(
      liveRegion: true,
      button: true,
      label: attention.message,
      child: Material(
        elevation: 3,
        color: background,
        borderRadius: BorderRadius.circular(CommRideRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(CommRideRadii.md),
          onTap: () => unawaited(attention.onTap()),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: CommRideTargets.minimum - 8,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: <Widget>[
                  Icon(attention.icon, color: foreground, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      attention.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: foreground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every in-ride action within thumb reach: three one-tap statuses and the
/// 3-second-hold SOS. Long-press a status to add a note.
class _RidingDock extends StatelessWidget {
  const _RidingDock({
    required this.voiceIntercomEnabled,
    required this.sosState,
    required this.hasOwnActiveSos,
    required this.sendingQuickAction,
    required this.onQuickAction,
    required this.onQuickActionWithReason,
    required this.onRaiseSos,
    required this.onRetrySos,
  });

  static const double height = 84;

  final bool voiceIntercomEnabled;
  final RideSosViewState sosState;
  final bool hasOwnActiveSos;
  final bool sendingQuickAction;
  final Future<void> Function(LiveQuickActionKind kind) onQuickAction;
  final Future<void> Function() onQuickActionWithReason;
  final Future<void> Function() onRaiseSos;
  final Future<void> Function() onRetrySos;

  @override
  Widget build(BuildContext context) {
    final bool failed = sosState.failedRaise != null;

    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          CommRideSpacing.xs,
          CommRideSpacing.xs,
          CommRideSpacing.xs,
          CommRideSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (failed)
              Padding(
                padding: const EdgeInsets.only(bottom: CommRideSpacing.xs),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'SOS gagal dikirim',
                        key: const ValueKey<String>('active-ride-sos-status'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: sosState.working
                          ? null
                          : () => unawaited(onRetrySos()),
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final LiveQuickActionKind kind
                      in LiveQuickActionKind.values) ...<Widget>[
                    Expanded(
                      child: _QuickStatusButton(
                        kind: kind,
                        enabled: !sendingQuickAction,
                        onTap: () => unawaited(onQuickAction(kind)),
                        onLongPress: () => unawaited(onQuickActionWithReason()),
                      ),
                    ),
                    const SizedBox(width: CommRideSpacing.xxs),
                  ],
                  Expanded(
                    child: SosHoldButton(
                      active: hasOwnActiveSos,
                      working: sosState.working,
                      enabled: !sosState.rideEnded,
                      compact: true,
                      onCompleted: onRaiseSos,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStatusButton extends StatelessWidget {
  const _QuickStatusButton({
    required this.kind,
    required this.enabled,
    required this.onTap,
    required this.onLongPress,
  });

  final LiveQuickActionKind kind;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final String label = switch (kind) {
      LiveQuickActionKind.stopping => 'Berhenti',
      LiveQuickActionKind.leftBehind => 'Tertinggal',
      LiveQuickActionKind.needHelp => 'Bantuan',
    };

    return Semantics(
      button: true,
      label: '${kind.label}. Tahan untuk menambah keterangan.',
      excludeSemantics: true,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(CommRideRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(CommRideRadii.md),
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(_quickActionIcon(kind), size: 30),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Music controls on their own row at the very top. The play button follows
/// whether any app is playing, checked every few seconds and after a tap.
class _MusicBar extends StatefulWidget {
  const _MusicBar();

  @override
  State<_MusicBar> createState() => _MusicBarState();
}

class _MusicBarState extends State<_MusicBar> {
  Timer? _poll;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final bool playing = await MediaKeys.isMusicActive();
    if (mounted && playing != _playing) {
      setState(() => _playing = playing);
    }
  }

  Future<void> _press(MediaKey key) async {
    if (key == MediaKey.playPause) {
      // Show the expected state at once; the next check corrects it.
      setState(() => _playing = !_playing);
    }
    await MediaKeys.send(key);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(CommRideRadii.lg),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 14),
          const Icon(Icons.music_note_outlined, size: 20),
          const Spacer(),
          IconButton(
            tooltip: 'Lagu sebelumnya',
            iconSize: 28,
            constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
            onPressed: () => unawaited(_press(MediaKey.previous)),
            icon: const Icon(Icons.skip_previous),
          ),
          IconButton(
            tooltip: _playing ? 'Jeda musik' : 'Putar musik',
            iconSize: 32,
            constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
            onPressed: () => unawaited(_press(MediaKey.playPause)),
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'Lagu berikutnya',
            iconSize: 28,
            constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
            onPressed: () => unawaited(_press(MediaKey.next)),
            icon: const Icon(Icons.skip_next),
          ),
          const Spacer(),
          const SizedBox(width: 34),
        ],
      ),
    );
  }
}

/// Interkom on its own row below the group summary. It shows its real
/// state: until a voice provider is verified it is visibly unavailable.
class _IntercomBar extends StatelessWidget {
  const _IntercomBar({required this.voiceIntercomEnabled});

  final bool voiceIntercomEnabled;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color? tone = voiceIntercomEnabled ? null : colors.outline;

    return Material(
      elevation: 3,
      color: colors.surface,
      borderRadius: BorderRadius.circular(CommRideRadii.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Icon(Icons.headset_mic_outlined, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  voiceIntercomEnabled
                      ? 'Interkom belum terhubung'
                      : 'Interkom segera tersedia',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: tone),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
