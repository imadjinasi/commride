import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/route_planner_api.dart';
import '../../models/route_planner.dart';

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({
    required this.rideId,
    required this.routePlannerApi,
    required this.canEdit,
    super.key,
  });

  final String rideId;
  final RoutePlannerApi routePlannerApi;
  final bool canEdit;

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  RouteTravelMode _travelMode = RouteTravelMode.drive;
  ResolvedPlace? _origin;
  ResolvedPlace? _destination;
  List<RouteOption> _routeOptions = <RouteOption>[];
  RouteOption? _selectedRoute;
  List<PlanningStop> _stops = <PlanningStop>[];
  bool _loading = true;
  bool _working = false;
  int? _savedRevision;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSavedPlan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route Planner')),
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loadSavedPlan,
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }

    if (!widget.canEdit && _selectedRoute == null) {
      return const Center(
        child: Text(
          'Leader belum menyimpan RoutePlan untuk Ride ini.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView(
      children: <Widget>[
        if (_savedRevision != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'RoutePlan revision ${_savedRevision!}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        if (widget.canEdit) ...<Widget>[
          DropdownButtonFormField<RouteTravelMode>(
            initialValue: _travelMode,
            decoration: const InputDecoration(
              labelText: 'Mode perjalanan',
              border: OutlineInputBorder(),
            ),
            items: RouteTravelMode.values
                .map(
                  (RouteTravelMode mode) => DropdownMenuItem<RouteTravelMode>(
                    value: mode,
                    child: Text(mode.label),
                  ),
                )
                .toList(growable: false),
            onChanged: _working || _selectedRoute != null
                ? null
                : (RouteTravelMode? value) {
                    if (value != null) {
                      setState(() {
                        _travelMode = value;
                      });
                    }
                  },
          ),
          const SizedBox(height: 16),
        ],
        if (_travelMode == RouteTravelMode.twoWheeler) ...<Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Rute motor dari penyedia navigasi dapat belum '
                      'mencakup semua jalan atau pembatasan. Tetap ikuti '
                      'rambu, aturan setempat, dan kondisi jalan aktual.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _PlaceTile(
          title: 'Titik awal',
          value: _origin?.formattedAddress,
          enabled: widget.canEdit && !_working && _selectedRoute == null,
          onTap: () => _chooseEndpoint(isOrigin: true),
        ),
        const SizedBox(height: 10),
        _PlaceTile(
          title: 'Tujuan',
          value: _destination?.formattedAddress,
          enabled: widget.canEdit && !_working && _selectedRoute == null,
          onTap: () => _chooseEndpoint(isOrigin: false),
        ),
        if (widget.canEdit &&
            _origin != null &&
            _destination != null &&
            _selectedRoute == null) ...<Widget>[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _working ? null : _computeInitialRoutes,
            icon: const Icon(Icons.route_outlined),
            label: Text(_working ? 'Menghitung…' : 'Cari rute'),
          ),
        ],
        if (_routeOptions.isNotEmpty && _selectedRoute == null) ...<Widget>[
          const SizedBox(height: 28),
          Text('Pilih rute', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ..._routeOptions.map(
            (RouteOption route) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text(_formatDistance(route.distanceMeters)),
                  subtitle: Text(
                    '${_formatDuration(route.durationSeconds)}'
                    '${route.labels.isEmpty ? '' : ' · ${route.labels.join(', ')}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    setState(() {
                      _selectedRoute = route;
                    });
                  },
                ),
              ),
            ),
          ),
        ],
        if (_selectedRoute != null) ...<Widget>[
          const SizedBox(height: 28),
          _RouteSummaryCard(route: _selectedRoute!, travelMode: _travelMode),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _working ? null : _navigateExternally,
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Buka Navigasi'),
          ),
          const SizedBox(height: 10),
          if (widget.canEdit) _buildPlanningActions(),
          if (_stops.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text(
              'Stops & Checkpoints',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _buildStops(),
          ],
          if (widget.canEdit) ...<Widget>[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _working ? null : _savePlan,
              icon: const Icon(Icons.save_outlined),
              label: Text(_working ? 'Menyimpan…' : 'Simpan RoutePlan'),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPlanningActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: _working || _stops.length >= 10 ? null : _addStop,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Tambah Stop'),
        ),
        OutlinedButton.icon(
          onPressed: _working || _stops.length >= 10 ? null : _searchAlongRoute,
          icon: const Icon(Icons.manage_search),
          label: const Text('Cari di Sepanjang Rute'),
        ),
      ],
    );
  }

  Widget _buildStops() {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _stops.length,
      onReorderItem: _working ? (_, _) {} : _reorderStops,
      itemBuilder: (BuildContext context, int index) {
        final PlanningStop stop = _stops[index];
        return Card(
          key: ValueKey<String>(
            '${stop.label}-${stop.location.latitude}-${stop.location.longitude}',
          ),
          child: ListTile(
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text(stop.label),
            subtitle: Text(_stopSubtitle(stop)),
            onTap: widget.canEdit && !_working
                ? () => _editCheckpoint(index)
                : null,
            trailing: widget.canEdit
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Hapus Stop',
                        onPressed: _working ? null : () => _removeStop(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  Future<void> _loadSavedPlan() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final SavedRoutePlan? saved = await widget.routePlannerApi.fetchRoutePlan(
        widget.rideId,
      );

      if (!mounted) {
        return;
      }

      if (saved != null) {
        setState(() {
          _savedRevision = saved.revision;
          _travelMode = saved.travelMode;
          _origin = ResolvedPlace(
            reference: 'saved-origin',
            formattedAddress: saved.originLabel,
            location: saved.origin,
          );
          _destination = ResolvedPlace(
            reference: 'saved-destination',
            formattedAddress: saved.destinationLabel,
            location: saved.destination,
          );
          _selectedRoute = saved.route;
          _routeOptions = <RouteOption>[saved.route];
          _stops = List<PlanningStop>.of(saved.stops);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadError = 'RoutePlan belum dapat dimuat.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _chooseEndpoint({required bool isOrigin}) async {
    final ResolvedPlace? place = await showDialog<ResolvedPlace>(
      context: context,
      builder: (BuildContext context) => _PlaceSearchDialog(
        routePlannerApi: widget.routePlannerApi,
        title: isOrigin ? 'Cari titik awal' : 'Cari tujuan',
      ),
    );

    if (place == null || !mounted) {
      return;
    }

    setState(() {
      if (isOrigin) {
        _origin = place;
      } else {
        _destination = place;
      }
      _routeOptions = <RouteOption>[];
      _selectedRoute = null;
      _stops = <PlanningStop>[];
      _savedRevision = null;
    });
  }

  Future<void> _computeInitialRoutes() async {
    final ResolvedPlace? origin = _origin;
    final ResolvedPlace? destination = _destination;
    if (origin == null || destination == null) {
      return;
    }

    await _runWorking(() async {
      final List<RouteOption> routes = await widget.routePlannerApi
          .computeRoutes(
            origin: origin,
            destination: destination,
            stops: const <PlanningStop>[],
            travelMode: _travelMode,
            computeAlternatives: true,
          );

      if (!mounted) {
        return;
      }

      if (routes.isEmpty) {
        _showMessage('Tidak ada rute yang ditemukan.');
        return;
      }

      setState(() {
        _routeOptions = routes;
        _selectedRoute = null;
        _stops = <PlanningStop>[];
      });
    });
  }

  Future<void> _navigateExternally() async {
    final ResolvedPlace? destination = _destination;
    if (destination == null) {
      return;
    }

    final GeoPoint target = _stops.isEmpty
        ? destination.location
        : _stops.first.location;
    final Uri url = Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'destination': '${target.latitude},${target.longitude}',
      'travelmode': _travelMode == RouteTravelMode.twoWheeler
          ? 'two-wheeler'
          : 'driving',
      'dir_action': 'navigate',
    });

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        _showMessage('Aplikasi navigasi belum dapat dibuka.');
      }
    }
  }

  Future<void> _addStop() async {
    final ResolvedPlace? place = await showDialog<ResolvedPlace>(
      context: context,
      builder: (BuildContext context) => _PlaceSearchDialog(
        routePlannerApi: widget.routePlannerApi,
        title: 'Tambah Stop',
      ),
    );

    if (place == null) {
      return;
    }

    final PlanningStop stop = PlanningStop(
      label: place.formattedAddress ?? 'Stop',
      formattedAddress: place.formattedAddress,
      location: place.location,
      stopType: StopType.generic,
      checkpointType: null,
      plannedDurationMinutes: null,
    );
    await _recomputeCandidate(<PlanningStop>[..._stops, stop]);
  }

  Future<void> _searchAlongRoute() async {
    final RouteOption? route = _selectedRoute;
    if (route == null) {
      return;
    }

    final _AlongRouteQuery? query = await showDialog<_AlongRouteQuery>(
      context: context,
      builder: (BuildContext context) => const _AlongRouteQueryDialog(),
    );

    if (query == null) {
      return;
    }

    List<AlongRoutePlace>? results;
    await _runWorking(() async {
      try {
        results = await widget.routePlannerApi.searchAlongRoute(
          textQuery: query.query,
          route: route,
          travelMode: _travelMode,
        );
      } on RoutePlannerApiException catch (error) {
        if (error.code == 'search_along_route_mode_not_supported') {
          _showMessage(
            'Search Along Route untuk mode motor belum didukung provider. '
            'Gunakan Tambah Stop dengan pencarian tempat.',
          );
          return;
        }
        rethrow;
      }
    });

    if (!mounted || results == null) {
      return;
    }

    final AlongRoutePlace? selected = await showDialog<AlongRoutePlace>(
      context: context,
      builder: (BuildContext context) =>
          _AlongRouteResultsDialog(results: results!, currentRoute: route),
    );

    if (selected?.location == null) {
      return;
    }

    final PlanningStop stop = PlanningStop(
      label: selected!.displayName,
      formattedAddress: selected.formattedAddress,
      location: selected.location!,
      stopType: query.stopType,
      checkpointType: null,
      plannedDurationMinutes: null,
    );

    await _recomputeCandidate(<PlanningStop>[..._stops, stop]);
  }

  Future<void> _reorderStops(int oldIndex, int newIndex) async {
    final List<PlanningStop> candidate = List<PlanningStop>.of(_stops);
    final PlanningStop moved = candidate.removeAt(oldIndex);
    candidate.insert(newIndex, moved);
    await _recomputeCandidate(candidate);
  }

  Future<void> _removeStop(int index) async {
    final List<PlanningStop> candidate = List<PlanningStop>.of(_stops)
      ..removeAt(index);
    await _recomputeCandidate(candidate);
  }

  Future<void> _recomputeCandidate(List<PlanningStop> candidateStops) async {
    final ResolvedPlace? origin = _origin;
    final ResolvedPlace? destination = _destination;
    if (origin == null || destination == null) {
      return;
    }

    await _runWorking(() async {
      final List<RouteOption> routes = await widget.routePlannerApi
          .computeRoutes(
            origin: origin,
            destination: destination,
            stops: candidateStops,
            travelMode: _travelMode,
            computeAlternatives: false,
          );

      if (!mounted) {
        return;
      }

      if (routes.isEmpty) {
        _showMessage(
          'Rute baru tidak tersedia. RoutePlan terakhir tetap dipakai.',
        );
        return;
      }

      setState(() {
        _stops = candidateStops;
        _selectedRoute = routes.first;
        _routeOptions = <RouteOption>[routes.first];
        _savedRevision = null;
      });
    });
  }

  Future<void> _editCheckpoint(int index) async {
    final PlanningStop? updated = await showDialog<PlanningStop>(
      context: context,
      builder: (BuildContext context) => _CheckpointDialog(stop: _stops[index]),
    );

    if (updated == null || !mounted) {
      return;
    }

    setState(() {
      _stops = List<PlanningStop>.of(_stops)..[index] = updated;
      _savedRevision = null;
    });
  }

  Future<void> _savePlan() async {
    final ResolvedPlace? origin = _origin;
    final ResolvedPlace? destination = _destination;
    final RouteOption? route = _selectedRoute;
    if (origin == null || destination == null || route == null) {
      return;
    }

    await _runWorking(() async {
      final SavedRoutePlan saved = await widget.routePlannerApi.saveRoutePlan(
        rideId: widget.rideId,
        origin: origin,
        destination: destination,
        route: route,
        travelMode: _travelMode,
        stops: _stops,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _savedRevision = saved.revision;
      });
      if (saved.activeRideBroadcast == false) {
        _showMessage(
          'RoutePlan revision ${saved.revision} tersimpan, tetapi update '
          'realtime ke Rider lain belum terkirim. Pastikan rombongan '
          'memuat ulang RoutePlan sebelum mengikuti rute baru.',
        );
      } else {
        _showMessage('RoutePlan revision ${saved.revision} tersimpan.');
      }
    });
  }

  Future<void> _runWorking(Future<void> Function() operation) async {
    if (_working) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await operation();
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Permintaan belum dapat diselesaikan. Route terakhir tetap dipakai.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _stopSubtitle(PlanningStop stop) {
    final List<String> parts = <String>[
      if (stop.formattedAddress != null) stop.formattedAddress!,
      if (stop.checkpointType != null)
        'Checkpoint: ${stop.checkpointType!.label}',
      if (stop.plannedDurationMinutes != null)
        '${stop.plannedDurationMinutes} menit',
    ];
    return parts.isEmpty ? 'Stop' : parts.join(' · ');
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.place_outlined),
        title: Text(title),
        subtitle: Text(value ?? 'Belum dipilih'),
        trailing: enabled ? const Icon(Icons.search) : null,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({required this.route, required this.travelMode});

  final RouteOption route;
  final RouteTravelMode travelMode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Route terpilih',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${_formatDistance(route.distanceMeters)} · '
              '${_formatDuration(route.durationSeconds)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text('Mode: ${travelMode.label}'),
          ],
        ),
      ),
    );
  }
}

class _PlaceSearchDialog extends StatefulWidget {
  const _PlaceSearchDialog({
    required this.routePlannerApi,
    required this.title,
  });

  final RoutePlannerApi routePlannerApi;
  final String title;

  @override
  State<_PlaceSearchDialog> createState() => _PlaceSearchDialogState();
}

class _PlaceSearchDialogState extends State<_PlaceSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  final String _sessionToken = _newSessionToken();
  List<PlaceSuggestion> _suggestions = <PlaceSuggestion>[];
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(
                labelText: 'Cari kota, alamat, atau tempat',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _working ? null : _search,
                child: Text(_working ? 'Mencari…' : 'Cari'),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_suggestions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _suggestions
                      .map(
                        (PlaceSuggestion suggestion) => ListTile(
                          title: Text(suggestion.text),
                          onTap: _working ? null : () => _select(suggestion),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
      ],
    );
  }

  Future<void> _search() async {
    final String query = _controller.text.trim();
    if (query.length < 2) {
      setState(() {
        _error = 'Masukkan minimal 2 karakter.';
      });
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final List<PlaceSuggestion> suggestions = await widget.routePlannerApi
          .autocomplete(input: query, sessionToken: _sessionToken);
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Pencarian tempat belum dapat diselesaikan.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _select(PlaceSuggestion suggestion) async {
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final ResolvedPlace place = await widget.routePlannerApi.resolvePlace(
        reference: suggestion.reference,
        sessionToken: _sessionToken,
      );

      if (mounted) {
        Navigator.of(context).pop(place);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Detail tempat belum dapat dimuat.';
          _working = false;
        });
      }
    }
  }
}

class _AlongRouteQuery {
  const _AlongRouteQuery({required this.query, required this.stopType});

  final String query;
  final StopType stopType;
}

class _AlongRouteQueryDialog extends StatelessWidget {
  const _AlongRouteQueryDialog();

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Cari di Sepanjang Rute'),
      children: <Widget>[
        _queryTile(context, 'Fuel', 'fuel station', StopType.fuel),
        _queryTile(context, 'Food', 'restaurant', StopType.meal),
        _queryTile(context, 'Rest', 'rest area', StopType.rest),
        _queryTile(context, 'Hotel', 'hotel', StopType.hotel),
        SimpleDialogOption(
          onPressed: () async {
            final String? query = await _customQuery(context);
            if (query != null && context.mounted) {
              Navigator.of(
                context,
              ).pop(_AlongRouteQuery(query: query, stopType: StopType.custom));
            }
          },
          child: const Text('Custom search'),
        ),
      ],
    );
  }

  Widget _queryTile(
    BuildContext context,
    String label,
    String query,
    StopType stopType,
  ) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(
        context,
      ).pop(_AlongRouteQuery(query: query, stopType: stopType)),
      child: Text(label),
    );
  }

  Future<String?> _customQuery(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Custom search'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Apa yang dicari?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final String value = controller.text.trim();
              if (value.length >= 2) {
                Navigator.of(context).pop(value);
              }
            },
            child: const Text('Cari'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}

class _AlongRouteResultsDialog extends StatelessWidget {
  const _AlongRouteResultsDialog({
    required this.results,
    required this.currentRoute,
  });

  final List<AlongRoutePlace> results;
  final RouteOption currentRoute;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hasil di sepanjang rute'),
      content: SizedBox(
        width: 520,
        child: results.isEmpty
            ? const Text('Tidak ada hasil yang cocok.')
            : ListView(
                shrinkWrap: true,
                children: results
                    .map(
                      (AlongRoutePlace place) => ListTile(
                        title: Text(place.displayName),
                        subtitle: Text(_impact(place)),
                        enabled: place.location != null,
                        onTap: place.location == null
                            ? null
                            : () => Navigator.of(context).pop(place),
                      ),
                    )
                    .toList(growable: false),
              ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
      ],
    );
  }

  String _impact(AlongRoutePlace place) {
    final int? distance = place.viaPlaceDistanceMeters;
    final int? duration = place.viaPlaceDurationSeconds;
    if (distance == null || duration == null) {
      return place.formattedAddress ?? 'Dampak rute belum tersedia';
    }

    final int extraDistance = max(0, distance - currentRoute.distanceMeters);
    final int extraDuration = max(0, duration - currentRoute.durationSeconds);

    return '+${_formatDistance(extraDistance)} · '
        '+${_formatDuration(extraDuration)}'
        '${place.formattedAddress == null ? '' : ' · ${place.formattedAddress}'}';
  }
}

class _CheckpointDialog extends StatefulWidget {
  const _CheckpointDialog({required this.stop});

  final PlanningStop stop;

  @override
  State<_CheckpointDialog> createState() => _CheckpointDialogState();
}

class _CheckpointDialogState extends State<_CheckpointDialog> {
  late bool _enabled;
  CheckpointType _type = CheckpointType.stop;
  late final TextEditingController _durationController;

  @override
  void initState() {
    super.initState();
    _enabled = widget.stop.checkpointType != null;
    _type = widget.stop.checkpointType ?? CheckpointType.stop;
    _durationController = TextEditingController(
      text: widget.stop.plannedDurationMinutes?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.stop.label),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Jadikan Checkpoint'),
            value: _enabled,
            onChanged: (bool value) {
              setState(() {
                _enabled = value;
              });
            },
          ),
          if (_enabled) ...<Widget>[
            DropdownButtonFormField<CheckpointType>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Jenis Checkpoint',
                border: OutlineInputBorder(),
              ),
              items: CheckpointType.values
                  .map(
                    (CheckpointType type) => DropdownMenuItem<CheckpointType>(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (CheckpointType? value) {
                if (value != null) {
                  setState(() {
                    _type = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Durasi rencana (menit)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_type == CheckpointType.mandatoryRegroup) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                'Mandatory Regroup berarti Leader akan mengontrol release '
                'grup saat Active Ride.',
              ),
            ],
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }

  void _save() {
    final String rawDuration = _durationController.text.trim();
    final int? duration = rawDuration.isEmpty
        ? null
        : int.tryParse(rawDuration);
    if (duration != null && (duration < 0 || duration > 1440)) {
      return;
    }

    Navigator.of(context).pop(
      widget.stop.copyWith(
        checkpointType: _enabled ? _type : null,
        clearCheckpoint: !_enabled,
        plannedDurationMinutes: _enabled ? duration : null,
        clearDuration: !_enabled || duration == null,
      ),
    );
  }
}

String _newSessionToken() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes
      .map((int value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _formatDistance(int meters) {
  if (meters < 1000) {
    return '$meters m';
  }

  final double km = meters / 1000;
  return '${km.toStringAsFixed(km >= 100 ? 0 : 1)} km';
}

String _formatDuration(int seconds) {
  final int minutes = (seconds / 60).round();
  final int hours = minutes ~/ 60;
  final int remainder = minutes % 60;

  if (hours == 0) {
    return '$minutes mnt';
  }
  if (remainder == 0) {
    return '$hours jam';
  }
  return '$hours j $remainder mnt';
}
