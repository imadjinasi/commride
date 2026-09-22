import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../active_ride/commride_navigation_engine.dart';
import '../active_ride/live_group_models.dart';
import '../config/app_config.dart';
import '../models/route_planner.dart';
import 'map_style_scope.dart';

class CommRideNavigationMapView extends StatefulWidget {
  const CommRideNavigationMapView({
    required this.routePoints,
    required this.routeRevision,
    required this.recoveryRoutePoints,
    required this.snapshot,
    required this.presences,
    required this.incidents,
    required this.now,
    super.key,
  });

  final List<GeoPoint> routePoints;
  final int routeRevision;
  final List<GeoPoint> recoveryRoutePoints;
  final CommRideNavigationSnapshot? snapshot;
  final List<LiveRiderPresence> presences;
  final List<TrafficIncident> incidents;
  final DateTime now;

  @override
  State<CommRideNavigationMapView> createState() =>
      _CommRideNavigationMapViewState();
}

class _CommRideNavigationMapViewState extends State<CommRideNavigationMapView> {
  static const String _routeSource = 'commride-navigation-route';
  static const String _routeLayer = 'commride-navigation-route-line';
  static const String _recoverySource = 'commride-navigation-recovery';
  static const String _recoveryLayer = 'commride-navigation-recovery-line';
  static const String _ridersSource = 'commride-navigation-riders';
  static const String _ridersLayer = 'commride-navigation-rider-circles';
  static const String _ridersLabels = 'commride-navigation-rider-labels';
  static const String _positionSource = 'commride-navigation-position';
  static const String _positionLayer = 'commride-navigation-position-circle';
  static const String _rejoinSource = 'commride-navigation-rejoin';
  static const String _rejoinLayer = 'commride-navigation-rejoin-circle';
  static const String _trafficSource = 'commride-navigation-traffic';
  static const String _trafficLayer = 'commride-navigation-traffic-circles';
  static const String _trafficLabels = 'commride-navigation-traffic-labels';
  static const Duration _timeout = Duration(seconds: 10);

  MapLibreMapController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _syncing = false;
  bool _syncPending = false;
  Timer? _styleTimer;
  String? _styleUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? next = AppConfig.validateMapStyleUrl(
      MapStyleScope.of(context),
    );
    if (next != _styleUrl) {
      _styleUrl = next;
      _ready = false;
      _failed = false;
    }
  }

  @override
  void didUpdateWidget(covariant CommRideNavigationMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready) {
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    _styleTimer?.cancel();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? styleUrl = _styleUrl;
    if (styleUrl == null || widget.routePoints.length < 2 || _failed) {
      return _MapFallback(
        message: styleUrl == null
            ? 'Peta belum dikonfigurasi. Panduan rute tetap tersedia.'
            : 'Peta belum dapat dimuat. Panduan rute tetap tersedia.',
        snapshot: widget.snapshot,
      );
    }

    final GeoPoint center =
        widget.snapshot?.position ?? widget.routePoints.first;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        MapLibreMap(
          key: ValueKey<String>('$styleUrl:${widget.routeRevision}'),
          styleString: styleUrl,
          initialCameraPosition: CameraPosition(
            target: LatLng(center.latitude, center.longitude),
            zoom: widget.snapshot == null ? 12 : 16,
            tilt: widget.snapshot == null ? 0 : 45,
            bearing: widget.snapshot?.routeBearingDegrees ?? 0,
          ),
          myLocationEnabled: false,
          compassEnabled: true,
          onMapCreated: (MapLibreMapController controller) {
            _controller = controller;
          },
          onStyleLoadedCallback: () => unawaited(_initializeStyle()),
        ),
        Positioned(
          right: 8,
          bottom: 6,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _credit('Geoapify', 'https://www.geoapify.com/'),
                  const Text('·'),
                  _credit(
                    'OpenStreetMap',
                    'https://www.openstreetmap.org/copyright',
                  ),
                  if (widget.incidents.isNotEmpty) ...<Widget>[
                    const Text('·'),
                    _credit(
                      'Traffic © TomTom',
                      'https://www.tomtom.com/legal/en_gb/product-attributions/',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!_ready) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Future<void> _initializeStyle() async {
    final MapLibreMapController? controller = _controller;
    if (controller == null || _failed) return;

    _styleTimer?.cancel();
    _styleTimer = Timer(const Duration(seconds: 20), _fail);

    try {
      await controller
          .addGeoJsonSource(_routeSource, _routeGeoJson(widget.routePoints))
          .timeout(_timeout);
      await controller
          .addLineLayer(
            _routeSource,
            _routeLayer,
            const LineLayerProperties(
              lineColor: '#1565C0',
              lineWidth: 6,
              lineOpacity: 0.9,
            ),
          )
          .timeout(_timeout);

      await controller
          .addGeoJsonSource(
            _recoverySource,
            _recoveryGeoJson(widget.recoveryRoutePoints),
          )
          .timeout(_timeout);
      await controller
          .addLineLayer(
            _recoverySource,
            _recoveryLayer,
            const LineLayerProperties(
              lineColor: '#F57C00',
              lineWidth: 5,
              lineOpacity: 0.9,
            ),
          )
          .timeout(_timeout);

      await controller
          .addGeoJsonSource(
            _ridersSource,
            _ridersGeoJson(widget.presences, widget.now),
          )
          .timeout(_timeout);
      await controller
          .addCircleLayer(
            _ridersSource,
            _ridersLayer,
            const CircleLayerProperties(
              circleColor: <String>['get', 'color'],
              circleRadius: 8,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 2,
            ),
          )
          .timeout(_timeout);
      await controller
          .addSymbolLayer(
            _ridersSource,
            _ridersLabels,
            const SymbolLayerProperties(
              textField: <String>['get', 'label'],
              textSize: 11,
              textOffset: <double>[0, 1.4],
              textAnchor: 'top',
              textColor: '#202020',
              textHaloColor: '#FFFFFF',
              textHaloWidth: 2,
            ),
          )
          .timeout(_timeout);

      await controller
          .addGeoJsonSource(_positionSource, _positionGeoJson(widget.snapshot))
          .timeout(_timeout);
      await controller
          .addCircleLayer(
            _positionSource,
            _positionLayer,
            const CircleLayerProperties(
              circleColor: '#0D47A1',
              circleRadius: 10,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 3,
            ),
          )
          .timeout(_timeout);

      await controller
          .addGeoJsonSource(_rejoinSource, _rejoinGeoJson(widget.snapshot))
          .timeout(_timeout);
      await controller
          .addCircleLayer(
            _rejoinSource,
            _rejoinLayer,
            const CircleLayerProperties(
              circleColor: '#F57C00',
              circleRadius: 9,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 2,
            ),
          )
          .timeout(_timeout);

      await controller
          .addGeoJsonSource(_trafficSource, _trafficGeoJson(widget.incidents))
          .timeout(_timeout);
      await controller
          .addCircleLayer(
            _trafficSource,
            _trafficLayer,
            const CircleLayerProperties(
              circleColor: '#C62828',
              circleRadius: 7,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 2,
            ),
          )
          .timeout(_timeout);
      await controller
          .addSymbolLayer(
            _trafficSource,
            _trafficLabels,
            const SymbolLayerProperties(
              textField: <String>['get', 'label'],
              textSize: 10,
              textOffset: <double>[0, 1.3],
              textAnchor: 'top',
              textColor: '#202020',
              textHaloColor: '#FFFFFF',
              textHaloWidth: 2,
            ),
          )
          .timeout(_timeout);

      if (!mounted) return;
      _styleTimer?.cancel();
      setState(() {
        _ready = true;
      });
      _scheduleSync();
    } catch (_) {
      _fail();
    }
  }

  void _scheduleSync() {
    if (!_ready || _failed || _controller == null) return;
    if (_syncing) {
      _syncPending = true;
      return;
    }
    unawaited(_sync());
  }

  Future<void> _sync() async {
    final MapLibreMapController? controller = _controller;
    if (controller == null || _syncing || !_ready || _failed) return;

    _syncing = true;
    try {
      do {
        _syncPending = false;
        await controller
            .setGeoJsonSource(_routeSource, _routeGeoJson(widget.routePoints))
            .timeout(_timeout);
        await controller
            .setGeoJsonSource(
              _recoverySource,
              _recoveryGeoJson(widget.recoveryRoutePoints),
            )
            .timeout(_timeout);
        await controller
            .setGeoJsonSource(
              _ridersSource,
              _ridersGeoJson(widget.presences, widget.now),
            )
            .timeout(_timeout);
        await controller
            .setGeoJsonSource(
              _positionSource,
              _positionGeoJson(widget.snapshot),
            )
            .timeout(_timeout);
        await controller
            .setGeoJsonSource(_rejoinSource, _rejoinGeoJson(widget.snapshot))
            .timeout(_timeout);
        await controller
            .setGeoJsonSource(_trafficSource, _trafficGeoJson(widget.incidents))
            .timeout(_timeout);

        final CommRideNavigationSnapshot? snapshot = widget.snapshot;
        if (snapshot != null) {
          await controller
              .animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: LatLng(
                      snapshot.position.latitude,
                      snapshot.position.longitude,
                    ),
                    zoom: 16,
                    tilt: 45,
                    bearing: snapshot.routeBearingDegrees,
                  ),
                ),
              )
              .timeout(_timeout);
        }
      } while (_syncPending);
    } catch (_) {
      _fail();
    } finally {
      _syncing = false;
    }
  }

  void _fail() {
    if (!mounted || _failed) return;
    _styleTimer?.cancel();
    setState(() {
      _failed = true;
      _ready = false;
    });
  }

  Widget _credit(String label, String url) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 28),
      ),
      onPressed: () async {
        try {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (_) {
          // Attribution remains visible even if no external browser is present.
        }
      },
      child: Text(label, style: const TextStyle(fontSize: 10)),
    );
  }
}

class _MapFallback extends StatelessWidget {
  const _MapFallback({required this.message, required this.snapshot});

  final String message;
  final CommRideNavigationSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final RouteManeuver? maneuver = snapshot?.nextManeuver;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.map_outlined, size: 42),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                if (maneuver != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    maneuver.instruction,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _routeGeoJson(List<GeoPoint> route) {
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <Object>[
      <String, dynamic>{
        'type': 'Feature',
        'geometry': <String, dynamic>{
          'type': 'LineString',
          'coordinates': route
              .map(
                (GeoPoint point) => <double>[point.longitude, point.latitude],
              )
              .toList(growable: false),
        },
        'properties': <String, dynamic>{},
      },
    ],
  };
}

Map<String, dynamic> _recoveryGeoJson(List<GeoPoint> route) {
  if (route.length < 2) return _emptyCollection();

  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <Object>[
      <String, dynamic>{
        'type': 'Feature',
        'geometry': <String, dynamic>{
          'type': 'LineString',
          'coordinates': route
              .map(
                (GeoPoint point) => <double>[point.longitude, point.latitude],
              )
              .toList(growable: false),
        },
        'properties': <String, dynamic>{},
      },
    ],
  };
}

Map<String, dynamic> _positionGeoJson(CommRideNavigationSnapshot? snapshot) {
  if (snapshot == null) return _emptyCollection();
  return _pointCollection(snapshot.position, <String, dynamic>{
    'label': 'Anda',
  });
}

Map<String, dynamic> _rejoinGeoJson(CommRideNavigationSnapshot? snapshot) {
  final GeoPoint? target = snapshot?.rejoinTarget;
  if (target == null) return _emptyCollection();
  return _pointCollection(target, <String, dynamic>{
    'label': 'Kembali ke rute',
  });
}

Map<String, dynamic> _ridersGeoJson(
  List<LiveRiderPresence> presences,
  DateTime now,
) {
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': presences
        .map((LiveRiderPresence presence) {
          final LivePresenceFreshness freshness = presence.effectiveFreshness(
            now,
          );
          final String color = switch (freshness) {
            LivePresenceFreshness.live => '#2E7D32',
            LivePresenceFreshness.stale => '#F9A825',
            LivePresenceFreshness.offline => '#6A1B9A',
          };
          return <String, dynamic>{
            'type': 'Feature',
            'id': presence.riderId,
            'geometry': <String, dynamic>{
              'type': 'Point',
              'coordinates': <double>[presence.longitude, presence.latitude],
            },
            'properties': <String, dynamic>{
              'color': color,
              'label':
                  '${presence.displayName} · ${presence.role.label}\n'
                  '${freshness.label}',
            },
          };
        })
        .toList(growable: false),
  };
}

Map<String, dynamic> _trafficGeoJson(List<TrafficIncident> incidents) {
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': incidents
        .where((TrafficIncident incident) => incident.points.isNotEmpty)
        .map((TrafficIncident incident) {
          final GeoPoint point = incident.points.first;
          return <String, dynamic>{
            'type': 'Feature',
            'id': incident.id,
            'geometry': <String, dynamic>{
              'type': 'Point',
              'coordinates': <double>[point.longitude, point.latitude],
            },
            'properties': <String, dynamic>{'label': _trafficLabel(incident)},
          };
        })
        .toList(growable: false),
  };
}

String _trafficLabel(TrafficIncident incident) {
  final String category = switch (incident.category) {
    'accident' => 'Kecelakaan',
    'jam' => 'Macet',
    'roadWorks' => 'Perbaikan jalan',
    'roadClosed' => 'Jalan ditutup',
    'laneClosed' => 'Lajur ditutup',
    'flooding' => 'Banjir',
    'brokenDownVehicle' => 'Kendaraan mogok',
    _ => incident.category,
  };
  return incident.description == null
      ? category
      : '$category · ${incident.description}';
}

Map<String, dynamic> _pointCollection(
  GeoPoint point,
  Map<String, dynamic> properties,
) {
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <Object>[
      <String, dynamic>{
        'type': 'Feature',
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[point.longitude, point.latitude],
        },
        'properties': properties,
      },
    ],
  };
}

Map<String, dynamic> _emptyCollection() {
  return <String, dynamic>{'type': 'FeatureCollection', 'features': <Object>[]};
}
