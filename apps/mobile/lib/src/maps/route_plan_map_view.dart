import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../config/app_config.dart';
import '../models/route_planner.dart';
import 'map_style_scope.dart';

class RoutePlanMapView extends StatelessWidget {
  const RoutePlanMapView({
    required this.routes,
    required this.selectedRoute,
    required this.onSelect,
    super.key,
  });

  final List<RouteOption> routes;
  final RouteOption? selectedRoute;
  final ValueChanged<RouteOption>? onSelect;

  @override
  Widget build(BuildContext context) {
    final String? styleUrl = AppConfig.validateMapStyleUrl(
      MapStyleScope.of(context),
    );
    final List<_RouteGeometry> geometries = routes
        .map(_RouteGeometry.tryCreate)
        .whereType<_RouteGeometry>()
        .toList(growable: false);

    if (styleUrl == null || geometries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.map_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  styleUrl == null
                      ? 'Peta RoutePlan belum dikonfigurasi pada build ini. '
                            'Pilihan rute tetap tersedia sebagai daftar.'
                      : 'Geometry rute belum dapat ditampilkan pada peta. '
                            'Pilihan daftar tetap tersedia.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _NativeRoutePlanMap(
      styleUrl: styleUrl,
      geometries: geometries,
      selectedRouteIndex: selectedRoute?.routeIndex,
      onSelect: onSelect,
    );
  }
}

class _RouteGeometry {
  const _RouteGeometry({required this.route, required this.points});

  final RouteOption route;
  final List<GeoPoint> points;

  static _RouteGeometry? tryCreate(RouteOption route) {
    try {
      final List<GeoPoint> points = decodeRoutePolyline(route.encodedPolyline);
      if (points.length < 2) {
        return null;
      }
      return _RouteGeometry(route: route, points: points);
    } catch (_) {
      return null;
    }
  }
}

class _NativeRoutePlanMap extends StatefulWidget {
  const _NativeRoutePlanMap({
    required this.styleUrl,
    required this.geometries,
    required this.selectedRouteIndex,
    required this.onSelect,
  });

  final String styleUrl;
  final List<_RouteGeometry> geometries;
  final int? selectedRouteIndex;
  final ValueChanged<RouteOption>? onSelect;

  @override
  State<_NativeRoutePlanMap> createState() => _NativeRoutePlanMapState();
}

class _NativeRoutePlanMapState extends State<_NativeRoutePlanMap> {
  static const String _routeSource = 'commride-route-planner-lines';
  static const String _routeLayer = 'commride-route-planner-lines-layer';
  static const String _pointSource = 'commride-route-planner-points';
  static const String _pointLayer = 'commride-route-planner-points-layer';
  static const Duration _timeout = Duration(seconds: 10);

  MapLibreMapController? _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void didUpdateWidget(covariant _NativeRoutePlanMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && !_failed) {
      unawaited(_sync());
    }
  }

  @override
  void dispose() {
    _controller?.onFeatureTapped.remove(_onFeatureTapped);
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.map_outlined),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Peta belum dapat dimuat. Pilihan rute tetap tersedia.',
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _failed = false;
                    _ready = false;
                  });
                },
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final _Bounds bounds = _Bounds.fromGeometries(widget.geometries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 300,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                MapLibreMap(
                  key: ValueKey<String>(
                    '${widget.styleUrl}:${widget.geometries.length}',
                  ),
                  styleString: widget.styleUrl,
                  initialCameraPosition: CameraPosition(
                    target: LatLng(bounds.centerLat, bounds.centerLng),
                    zoom: 10,
                  ),
                  myLocationEnabled: false,
                  compassEnabled: true,
                  onMapCreated: (MapLibreMapController controller) {
                    _controller = controller;
                    controller.onFeatureTapped.add(_onFeatureTapped);
                  },
                  onStyleLoadedCallback: () => unawaited(_initialize()),
                ),
                if (!_ready) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Peta: Route terpilih ditampilkan lebih tebal. '
          'Ketuk garis rute atau pilih dari daftar.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        const Text(
          'Geoapify / © OpenStreetMap contributors · MapLibre',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _initialize() async {
    final MapLibreMapController? controller = _controller;
    if (controller == null || _failed) {
      return;
    }

    try {
      await controller
          .addGeoJsonSource(_routeSource, _routeGeoJson())
          .timeout(_timeout);
      await controller
          .addLineLayer(
            _routeSource,
            _routeLayer,
            const LineLayerProperties(
              lineColor: <String>['get', 'color'],
              lineWidth: <String>['get', 'width'],
              lineOpacity: <String>['get', 'opacity'],
            ),
          )
          .timeout(_timeout);
      await controller
          .addGeoJsonSource(_pointSource, _pointGeoJson())
          .timeout(_timeout);
      await controller
          .addCircleLayer(
            _pointSource,
            _pointLayer,
            const CircleLayerProperties(
              circleColor: '#161616',
              circleRadius: 6,
              circleStrokeColor: '#FFFFFF',
              circleStrokeWidth: 2,
            ),
          )
          .timeout(_timeout);

      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
      });
      await _fit();
    } catch (_) {
      _fail();
    }
  }

  Future<void> _sync() async {
    final MapLibreMapController? controller = _controller;
    if (controller == null || !_ready || _failed) {
      return;
    }
    try {
      await controller
          .setGeoJsonSource(_routeSource, _routeGeoJson())
          .timeout(_timeout);
      await controller
          .setGeoJsonSource(_pointSource, _pointGeoJson())
          .timeout(_timeout);
    } catch (_) {
      _fail();
    }
  }

  Future<void> _fit() async {
    final MapLibreMapController? controller = _controller;
    if (controller == null || !_ready || _failed) {
      return;
    }

    final _Bounds bounds = _Bounds.fromGeometries(widget.geometries);
    try {
      await controller
          .animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(bounds.south, bounds.west),
                northeast: LatLng(bounds.north, bounds.east),
              ),
              left: 34,
              top: 34,
              right: 34,
              bottom: 34,
            ),
          )
          .timeout(_timeout);
    } catch (_) {
      _fail();
    }
  }

  void _onFeatureTapped(
    Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    if (layerId != _routeLayer || widget.onSelect == null) {
      return;
    }
    final int? routeIndex = int.tryParse(id.replaceFirst('route-', ''));
    if (routeIndex == null) {
      return;
    }
    for (final _RouteGeometry geometry in widget.geometries) {
      if (geometry.route.routeIndex == routeIndex) {
        widget.onSelect!(geometry.route);
        return;
      }
    }
  }

  Map<String, dynamic> _routeGeoJson() {
    return <String, dynamic>{
      'type': 'FeatureCollection',
      'features': widget.geometries
          .map((_RouteGeometry geometry) {
            final bool selected =
                geometry.route.routeIndex == widget.selectedRouteIndex;
            return <String, dynamic>{
              'type': 'Feature',
              'id': 'route-${geometry.route.routeIndex}',
              'geometry': <String, dynamic>{
                'type': 'LineString',
                'coordinates': geometry.points
                    .map(
                      (GeoPoint point) => <double>[
                        point.longitude,
                        point.latitude,
                      ],
                    )
                    .toList(growable: false),
              },
              'properties': <String, dynamic>{
                'color': selected ? '#161616' : '#FF6A1A',
                'width': selected ? 7 : 4,
                'opacity': selected ? 0.95 : 0.58,
              },
            };
          })
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _pointGeoJson() {
    final _RouteGeometry first = widget.geometries.first;
    return <String, dynamic>{
      'type': 'FeatureCollection',
      'features': <Object>[
        _pointFeature('start', first.points.first),
        _pointFeature('finish', first.points.last),
      ],
    };
  }

  Map<String, dynamic> _pointFeature(String id, GeoPoint point) {
    return <String, dynamic>{
      'type': 'Feature',
      'id': id,
      'geometry': <String, dynamic>{
        'type': 'Point',
        'coordinates': <double>[point.longitude, point.latitude],
      },
      'properties': <String, dynamic>{},
    };
  }

  void _fail() {
    if (!mounted) {
      return;
    }
    setState(() {
      _failed = true;
      _ready = false;
    });
  }
}

class _Bounds {
  const _Bounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south;
  final double west;
  final double north;
  final double east;

  double get centerLat => (south + north) / 2;
  double get centerLng => (west + east) / 2;

  factory _Bounds.fromGeometries(List<_RouteGeometry> geometries) {
    double south = 90;
    double north = -90;
    double west = 180;
    double east = -180;
    for (final _RouteGeometry geometry in geometries) {
      for (final GeoPoint point in geometry.points) {
        if (point.latitude < south) south = point.latitude;
        if (point.latitude > north) north = point.latitude;
        if (point.longitude < west) west = point.longitude;
        if (point.longitude > east) east = point.longitude;
      }
    }

    if (south == north) {
      south -= 0.005;
      north += 0.005;
    }
    if (west == east) {
      west -= 0.005;
      east += 0.005;
    }

    return _Bounds(south: south, west: west, north: north, east: east);
  }
}
