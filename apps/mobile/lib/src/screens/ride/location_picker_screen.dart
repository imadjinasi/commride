import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../api/route_planner_api.dart';
import '../../config/app_config.dart';
import '../../maps/map_style_scope.dart';
import '../../models/route_planner.dart';
import '../../theme/commride_theme.dart';

/// Returns the device position, asking for permission only when [ask] is
/// true. Null when location is unavailable or refused.
typedef CurrentLocationLookup = Future<GeoPoint?> Function({required bool ask});

/// Picks a Ride point the way map apps do: a full-screen map with a fixed
/// center pin, search that favours the area on screen, and "Lokasi saya".
/// Places missing from the map data can still be chosen by moving the pin.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    required this.routePlannerApi,
    required this.title,
    this.initialCenter,
    this.currentLocation = deviceLocation,
    super.key,
  });

  final RoutePlannerApi routePlannerApi;
  final String title;
  final GeoPoint? initialCenter;
  final CurrentLocationLookup currentLocation;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

/// Used only to center the picker; the position is not stored or shared.
Future<GeoPoint?> deviceLocation({required bool ask}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && ask) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return GeoPoint(latitude: position.latitude, longitude: position.longitude);
  } catch (_) {
    return null;
  }
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Central Java/West Java pilot area when nothing better is known.
  static const GeoPoint _fallbackCenter = GeoPoint(
    latitude: -6.73,
    longitude: 108.55,
  );

  final TextEditingController _query = TextEditingController();
  final String _sessionToken = _newSessionToken();
  MapLibreMapController? _map;
  String? _styleUrl;

  GeoPoint _center = _fallbackCenter;
  List<PlaceSuggestion> _suggestions = <PlaceSuggestion>[];
  bool _searching = false;
  bool _searchAreaOnly = false;
  String? _searchError;

  /// The place for the current pin position, once known.
  ResolvedPlace? _place;
  bool _describing = false;
  int _describeToken = 0;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final GeoPoint? initial = widget.initialCenter;
    if (initial != null) {
      _center = initial;
    } else {
      unawaited(_centerOnDevice(ask: false));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _styleUrl = AppConfig.validateMapStyleUrl(MapStyleScope.of(context));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _hasMap => _styleUrl != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: <Widget>[
          if (_hasMap) ...<Widget>[
            Positioned.fill(
              child: MapLibreMap(
                styleString: _styleUrl!,
                initialCameraPosition: CameraPosition(
                  target: LatLng(_center.latitude, _center.longitude),
                  zoom: 15,
                ),
                trackCameraPosition: true,
                myLocationEnabled: false,
                compassEnabled: false,
                onMapCreated: (MapLibreMapController controller) {
                  _map = controller;
                },
                onCameraIdle: _onCameraIdle,
              ),
            ),
            // The pin tip marks the map center.
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 44),
                    child: Icon(
                      Icons.location_on,
                      size: 48,
                      color: CommRideColors.criticalRed,
                    ),
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _buildSearch(context),
          ),
          if (_hasMap)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(top: false, child: _buildSelection(context)),
            ),
        ],
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(CommRideRadii.lg),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.search),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Cari tempat, alamat, atau kota',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_query.text.isNotEmpty || _suggestions.isNotEmpty)
                  IconButton(
                    tooltip: 'Hapus pencarian',
                    onPressed: () => setState(() {
                      _query.clear();
                      _suggestions = <PlaceSuggestion>[];
                      _searchError = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                FilledButton(
                  onPressed: _searching ? null : _search,
                  child: Text(_searching ? '…' : 'Cari'),
                ),
              ],
            ),
            if (_hasMap)
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Cari di area ini'),
                  selected: _searchAreaOnly,
                  onSelected: (bool value) =>
                      setState(() => _searchAreaOnly = value),
                ),
              ),
            if (_searchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Text(
                  _searchError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_suggestions.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final PlaceSuggestion suggestion in _suggestions)
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(suggestion.text),
                        onTap: () => _chooseSuggestion(suggestion),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelection(BuildContext context) {
    final ResolvedPlace? place = _place;
    final String address = _describing
        ? 'Memuat alamat…'
        : place?.formattedAddress ?? 'Titik di peta';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Material(
          elevation: 3,
          shape: const CircleBorder(),
          color: Theme.of(context).colorScheme.surface,
          child: IconButton(
            tooltip: 'Lokasi saya',
            iconSize: 28,
            padding: const EdgeInsets.all(12),
            onPressed: _locating ? null : () => _centerOnDevice(ask: true),
            icon: _locating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
        const SizedBox(height: 10),
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(CommRideRadii.lg),
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Geser peta sampai pin tepat di lokasi.',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${_center.latitude.toStringAsFixed(5)}, '
                  '${_center.longitude.toStringAsFixed(5)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(CommRideTargets.minimum),
                  ),
                  onPressed: _confirm,
                  icon: const Icon(Icons.check),
                  label: const Text('Pilih titik ini'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _search() async {
    final String query = _query.text.trim();
    if (query.length < 2) {
      setState(() => _searchError = 'Masukkan minimal 2 karakter.');
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      PlaceSearchArea? area;
      if (_searchAreaOnly && _map != null) {
        final LatLngBounds bounds = await _map!.getVisibleRegion();
        area = PlaceSearchArea(
          south: bounds.southwest.latitude,
          west: bounds.southwest.longitude,
          north: bounds.northeast.latitude,
          east: bounds.northeast.longitude,
        );
      }
      final List<PlaceSuggestion> results = await widget.routePlannerApi
          .autocomplete(
            input: query,
            sessionToken: _sessionToken,
            near: _center,
            area: area,
          );
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        if (results.isEmpty) {
          _searchError = _hasMap
              ? 'Tidak ditemukan. Geser peta lalu pilih titiknya langsung.'
              : 'Tidak ditemukan.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _searchError = 'Pencarian belum dapat diselesaikan.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _chooseSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _searching = true);
    try {
      final ResolvedPlace place = await widget.routePlannerApi.resolvePlace(
        reference: suggestion.reference,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      if (!_hasMap) {
        Navigator.of(context).pop(place);
        return;
      }
      FocusScope.of(context).unfocus();
      setState(() {
        _suggestions = <PlaceSuggestion>[];
        _center = place.location;
        _place = place;
        // Moving the camera below must not replace the searched place.
        _describeToken += 1;
      });
      await _map?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(place.location.latitude, place.location.longitude),
          17,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _searchError = 'Detail tempat belum dapat dimuat.');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onCameraIdle() {
    final LatLng? target = _map?.cameraPosition?.target;
    if (target == null) return;
    final GeoPoint center = GeoPoint(
      latitude: target.latitude,
      longitude: target.longitude,
    );
    final ResolvedPlace? place = _place;
    // The searched place keeps its name while the pin stays on it.
    if (place != null && _closeTo(place.location, center)) {
      return;
    }
    setState(() {
      _center = center;
      _place = null;
    });
    unawaited(_describe(center));
  }

  Future<void> _describe(GeoPoint center) async {
    final int token = ++_describeToken;
    setState(() => _describing = true);
    ResolvedPlace? place;
    try {
      place = await widget.routePlannerApi.reverseGeocode(center);
    } catch (_) {
      place = null;
    }
    if (!mounted || token != _describeToken) return;
    setState(() {
      _describing = false;
      _place = place;
    });
  }

  Future<void> _centerOnDevice({required bool ask}) async {
    setState(() => _locating = true);
    final GeoPoint? here = await widget.currentLocation(ask: ask);
    if (!mounted) return;
    setState(() => _locating = false);
    if (here == null) {
      if (ask) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lokasi belum tersedia. Aktifkan GPS dan izin lokasi, atau '
              'geser peta secara manual.',
            ),
          ),
        );
      }
      return;
    }
    setState(() => _center = here);
    await _map?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(here.latitude, here.longitude), 17),
    );
  }

  void _confirm() {
    final ResolvedPlace place =
        _place ??
        ResolvedPlace(
          reference:
              'point:${_center.latitude.toStringAsFixed(6)},'
              '${_center.longitude.toStringAsFixed(6)}',
          formattedAddress: null,
          location: _center,
        );
    Navigator.of(context).pop(place);
  }

  static bool _closeTo(GeoPoint a, GeoPoint b) =>
      (a.latitude - b.latitude).abs() < 0.00005 &&
      (a.longitude - b.longitude).abs() < 0.00005;
}

String _newSessionToken() {
  final Random random = Random.secure();
  return List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
