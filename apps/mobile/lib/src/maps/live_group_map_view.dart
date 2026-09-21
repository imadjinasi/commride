import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../active_ride/live_group_map_models.dart';
import '../active_ride/live_group_models.dart';
import '../config/app_config.dart';
import '../models/club_ride.dart';
import 'latest_map_update.dart';
import 'map_style_scope.dart';

/// Map failure must not take away the operational Rider list.
class LiveGroupMapView extends StatelessWidget {
  const LiveGroupMapView({
    required this.presentation,
    required this.now,
    required this.fallback,
    super.key,
  });

  final LiveGroupMapPresentation presentation;
  final DateTime now;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final String? styleUrl = AppConfig.validateMapStyleUrl(
      MapStyleScope.of(context),
    );
    if (styleUrl == null || presentation.bounds == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Peta belum dikonfigurasi. Daftar Rider tetap tersedia.',
              ),
            ),
          ),
          fallback,
        ],
      );
    }
    return _NativeLiveGroupMap(
      styleUrl: styleUrl,
      presentation: presentation,
      now: now,
      fallback: fallback,
    );
  }
}

Map<String, dynamic> riderMapGeoJson(
  LiveGroupMapPresentation presentation,
  DateTime now,
) {
  return <String, dynamic>{
    'type': 'FeatureCollection',
    'features': presentation.markers.map((LiveGroupMapMarker marker) {
      final String color;
      if (marker.attention == LiveGroupMapAttention.separated) {
        color = '#C2185B';
      } else if (marker.attention == LiveGroupMapAttention.inspect) {
        color = '#EF6C00';
      } else {
        color = switch (marker.freshness) {
          LivePresenceFreshness.live => '#2E7D32',
          LivePresenceFreshness.stale => '#F9A825',
          LivePresenceFreshness.offline => '#6A1B9A',
        };
      }
      return <String, dynamic>{
        'type': 'Feature',
        'id': marker.riderId,
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[marker.longitude, marker.latitude],
        },
        'properties': <String, dynamic>{
          'color': color,
          'radius': marker.attention == LiveGroupMapAttention.normal ? 9 : 11,
          'label': riderMapLabel(marker, now),
        },
      };
    }).toList(growable: false),
  };
}

String riderMapLabel(LiveGroupMapMarker marker, DateTime now) {
  final Duration age = now.difference(marker.observedAt);
  final int seconds = age.isNegative ? 0 : age.inSeconds;
  final String elapsed = seconds < 60
      ? '$seconds dtk'
      : seconds < 3600
      ? '${seconds ~/ 60} mnt'
      : '${seconds ~/ 3600} jam';
  return '${marker.displayName} · ${marker.role.label}\n'
      '${marker.freshness.label}'
      '${marker.isLastKnown ? ' · posisi terakhir' : ''}'
      ' · observasi $elapsed lalu';
}

class _NativeLiveGroupMap extends StatefulWidget {
  const _NativeLiveGroupMap({
    required this.styleUrl,
    required this.presentation,
    required this.now,
    required this.fallback,
  });

  final String styleUrl;
  final LiveGroupMapPresentation presentation;
  final DateTime now;
  final Widget fallback;

  @override
  State<_NativeLiveGroupMap> createState() => _NativeLiveGroupMapState();
}

class _NativeLiveGroupMapState extends State<_NativeLiveGroupMap> {
  static const String _source = 'commride-riders';
  static const String _circles = 'commride-rider-circles';
  static const String _labels = 'commride-rider-labels';
  static const Duration _timeout = Duration(seconds: 10);
  MapLibreMapController? _controller;
  late LatestMapUpdate<Map<String, dynamic>> _updates;
  Timer? _loadTimer;
  bool _ready = false;
  bool _initializing = false;
  bool _failed = false;
  int _generation = 0;
  String? _selectedRiderId;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _ready = false;
    _initializing = false;
    _failed = false;
    _generation += 1;
    _updates = LatestMapUpdate<Map<String, dynamic>>(
      apply: (Map<String, dynamic> data) async {
        final MapLibreMapController? controller = _controller;
        if (controller != null && mounted && _ready && !_failed) {
          await controller.setGeoJsonSource(_source, data).timeout(_timeout);
        }
      },
      onError: _fail,
    );
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 20), _fail);
  }

  @override
  void didUpdateWidget(covariant _NativeLiveGroupMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.styleUrl != widget.styleUrl) {
      _detach();
      _reset();
    } else if (_ready) {
      _updates.submit(riderMapGeoJson(widget.presentation, widget.now));
    }
  }

  void _detach() {
    _loadTimer?.cancel();
    _updates.dispose();
    _controller?.onFeatureTapped.remove(_onFeatureTapped);
    // MapLibreMap owns controller disposal when its platform view is removed.
    _controller = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _fail() {
    if (!mounted || _failed) {
      return;
    }
    _detach();
    setState(() {
      _failed = true;
      _ready = false;
    });
  }

  bool _alive(MapLibreMapController controller, int generation) {
    return mounted &&
        !_failed &&
        generation == _generation &&
        identical(controller, _controller);
  }

  Future<void> _onStyleLoaded(int generation) async {
    final MapLibreMapController? controller = _controller;
    if (controller == null ||
        !_alive(controller, generation) ||
        _ready ||
        _initializing) {
      return;
    }
    _initializing = true;
    try {
      await controller.addGeoJsonSource(_source, <String, dynamic>{
        'type': 'FeatureCollection',
        'features': <Object>[],
      }).timeout(_timeout);
      if (!_alive(controller, generation)) {
        return;
      }
      await controller.addCircleLayer(
        _source,
        _circles,
        const CircleLayerProperties(
          circleColor: <String>['get', 'color'],
          circleRadius: <String>['get', 'radius'],
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ),
      ).timeout(_timeout);
      if (!_alive(controller, generation)) {
        return;
      }
      await controller.addSymbolLayer(
        _source,
        _labels,
        const SymbolLayerProperties(
          textField: <String>['get', 'label'],
          textSize: 12,
          textOffset: <double>[0, 1.5],
          textAnchor: 'top',
          textColor: '#202020',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 2,
        ),
      ).timeout(_timeout);
      if (!_alive(controller, generation)) {
        return;
      }
      _loadTimer?.cancel();
      setState(() {
        _ready = true;
        _initializing = false;
      });
      _updates.submit(riderMapGeoJson(widget.presentation, widget.now));
    } catch (_) {
      if (generation == _generation) {
        _fail();
      }
    }
  }

  void _onFeatureTapped(
    Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    if (mounted && (layerId == _circles || layerId == _labels)) {
      setState(() {
        _selectedRiderId = id;
      });
    }
  }

  Future<void> _fit() async {
    final MapLibreMapController? controller = _controller;
    final LiveGroupMapBounds? bounds = widget.presentation.bounds;
    if (!_ready || controller == null || bounds == null) {
      return;
    }
    try {
      final CameraUpdate update;
      if (bounds.south == bounds.north && bounds.west == bounds.east) {
        update = CameraUpdate.newLatLngZoom(
          LatLng(bounds.centerLatitude, bounds.centerLongitude),
          16,
        );
      } else {
        update = CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(bounds.south, bounds.west),
            northeast: LatLng(bounds.north, bounds.east),
          ),
          left: 56,
          top: 56,
          right: 56,
          bottom: 56,
        );
      }
      await controller.animateCamera(update).timeout(_timeout);
    } catch (_) {
      _fail();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('Peta belum dapat dimuat. Gunakan daftar Rider.'),
          TextButton(
            onPressed: () => setState(_reset),
            child: const Text('Coba muat peta lagi'),
          ),
          widget.fallback,
        ],
      );
    }
    final LiveGroupMapBounds bounds = widget.presentation.bounds!;
    final int generation = _generation;
    LiveGroupMapMarker? selected;
    for (final LiveGroupMapMarker marker in widget.presentation.markers) {
      if (marker.riderId == _selectedRiderId) {
        selected = marker;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 420,
            child: MapLibreMap(
              key: ValueKey<int>(generation),
              styleString: widget.styleUrl,
              initialCameraPosition: CameraPosition(
                target: LatLng(bounds.centerLatitude, bounds.centerLongitude),
                zoom: widget.presentation.markers.length == 1 ? 16 : 12,
              ),
              myLocationEnabled: false,
              compassEnabled: true,
              onMapCreated: (MapLibreMapController controller) {
                if (mounted && generation == _generation && !_failed) {
                  _controller = controller;
                  controller.onFeatureTapped.add(_onFeatureTapped);
                }
              },
              onStyleLoadedCallback: () => unawaited(
                _onStyleLoaded(generation),
              ),
            ),
          ),
        ),
        Wrap(
          children: <Widget>[
            _credit('Powered by Geoapify', 'https://www.geoapify.com/'),
            _credit(
              '© OpenStreetMap contributors',
              'https://www.openstreetmap.org/copyright',
            ),
            _credit('© OpenMapTiles', 'https://openmaptiles.org/'),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _ready ? _fit : null,
            icon: const Icon(Icons.center_focus_strong),
            label: const Text('Fit Group'),
          ),
        ),
        if (!_ready) const Text('Memuat peta… Daftar Rider tersedia di List.'),
        if (selected != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(riderMapLabel(selected, widget.now)),
            ),
          ),
        Text(
          'Map tidak mengikuti pergerakan otomatis. Gunakan Fit Group saat '
          'ingin membingkai ulang rombongan.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _credit(String label, String url) {
    return TextButton(
      onPressed: () async {
        try {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (_) {
          // Attribution stays visible even without an external browser.
        }
      },
      child: Text(label),
    );
  }
}
