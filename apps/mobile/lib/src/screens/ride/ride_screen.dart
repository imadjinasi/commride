import 'package:flutter/material.dart';

import '../../active_ride/active_ride_runtime.dart';

import '../../api/checkpoint_api.dart';
import '../../api/club_ride_api.dart';
import '../../api/ride_briefing_api.dart';
import '../../api/ride_comms_api.dart';
import '../../api/ride_recap_api.dart';
import '../../api/ride_sos_api.dart';
import '../../api/route_planner_api.dart';
import '../../models/club_ride.dart';
import 'create_ride_screen.dart';
import 'ride_detail_screen.dart';

class RideScreen extends StatefulWidget {
  const RideScreen({
    required this.clubRideApi,
    required this.checkpointApi,
    required this.routePlannerApi,
    required this.rideBriefingApi,
    required this.rideCommsApi,
    required this.rideSosApi,
    this.rideRecapApi,
    this.activeRideRuntimeManager,
    this.mapsEnabled = false,
    this.navigationEnabled = false,
    this.voiceIntercomEnabled = false,
    super.key,
  });

  final ClubRideApi clubRideApi;
  final CheckpointApi checkpointApi;
  final RoutePlannerApi routePlannerApi;
  final RideBriefingApi rideBriefingApi;
  final RideCommsApi rideCommsApi;
  final RideSosApi rideSosApi;
  final RideRecapApi? rideRecapApi;
  final ActiveRideRuntimeManager? activeRideRuntimeManager;
  final bool mapsEnabled;
  final bool navigationEnabled;
  final bool voiceIntercomEnabled;

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  late Future<_RideOverview> _overviewFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar.large(
            title: const Text('Ride'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Muat ulang',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            sliver: SliverToBoxAdapter(
              child: FutureBuilder<_RideOverview>(
                future: _overviewFuture,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<_RideOverview> snapshot,
                    ) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return _RideLoadError(onRetry: _refresh);
                      }

                      final _RideOverview overview =
                          snapshot.data ?? const _RideOverview.empty();

                      return _RideOverviewContent(
                        overview: overview,
                        onCreateRide: _openCreateRide,
                        onOpenRide: _openRide,
                      );
                    },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _reload() {
    _overviewFuture = _loadOverview();
  }

  void _refresh() {
    setState(_reload);
  }

  Future<_RideOverview> _loadOverview() async {
    final List<ClubListItem> clubs = await widget.clubRideApi.listClubs();
    final List<ClubListItem> activeClubs = clubs
        .where(
          (ClubListItem item) =>
              item.membership.status == ClubMembershipStatus.active,
        )
        .toList(growable: false);

    final List<_ClubRides> groups = await Future.wait(
      activeClubs.map((ClubListItem clubItem) async {
        final List<RideListItem> rides = await widget.clubRideApi.listRides(
          clubItem.club.id,
        );
        return _ClubRides(clubItem: clubItem, rides: rides);
      }),
    );

    return _RideOverview(groups);
  }

  Future<void> _openCreateRide(ClubListItem clubItem) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CreateRideScreen(
          clubId: clubItem.club.id,
          clubRideApi: widget.clubRideApi,
          onCreated: (_) => _refresh(),
        ),
      ),
    );
  }

  Future<void> _openRide(RideListItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RideDetailScreen(
          item: item,
          clubRideApi: widget.clubRideApi,
          checkpointApi: widget.checkpointApi,
          routePlannerApi: widget.routePlannerApi,
          rideBriefingApi: widget.rideBriefingApi,
          rideCommsApi: widget.rideCommsApi,
          rideSosApi: widget.rideSosApi,
          rideRecapApi: widget.rideRecapApi,
          activeRideRuntimeManager: widget.activeRideRuntimeManager,
          mapsEnabled: widget.mapsEnabled,
          navigationEnabled: widget.navigationEnabled,
          voiceIntercomEnabled: widget.voiceIntercomEnabled,
          onChanged: _refresh,
        ),
      ),
    );
  }
}

class _RideOverviewContent extends StatelessWidget {
  const _RideOverviewContent({
    required this.overview,
    required this.onCreateRide,
    required this.onOpenRide,
  });

  final _RideOverview overview;
  final ValueChanged<ClubListItem> onCreateRide;
  final ValueChanged<RideListItem> onOpenRide;

  @override
  Widget build(BuildContext context) {
    if (overview.groups.isEmpty) {
      return const _EmptyRides(
        message:
            'Gabung atau buat Club dulu. Ride yang dapat Anda akses akan '
            'muncul di sini.',
      );
    }

    final List<_RideWithClub> all = overview.groups
        .expand(
          (_ClubRides group) => group.rides.map(
            (RideListItem item) =>
                _RideWithClub(clubItem: group.clubItem, rideItem: item),
          ),
        )
        .toList(growable: false);

    final List<ClubListItem> manageableClubs = overview.groups
        .map((_ClubRides group) => group.clubItem)
        .where(
          (ClubListItem item) =>
              item.membership.role == ClubRole.owner ||
              item.membership.role == ClubRole.admin,
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (manageableClubs.isNotEmpty)
          _CreateRideCard(clubs: manageableClubs, onCreateRide: onCreateRide),
        if (manageableClubs.isNotEmpty) const SizedBox(height: 20),
        if (all.isEmpty)
          const _EmptyRides(
            message:
                'Belum ada Ride di Club Anda. Buat Ride baru atau tunggu '
                'undangan dari Leader.',
          )
        else
          ..._buildSections(context, all),
      ],
    );
  }

  List<Widget> _buildSections(BuildContext context, List<_RideWithClub> all) {
    const List<RideStatus> order = <RideStatus>[
      RideStatus.active,
      RideStatus.published,
      RideStatus.draft,
      RideStatus.completed,
      RideStatus.cancelled,
    ];

    final List<Widget> widgets = <Widget>[];
    for (final RideStatus status in order) {
      final List<_RideWithClub> rides = all
          .where((_RideWithClub item) => item.rideItem.ride.status == status)
          .toList(growable: false);
      if (rides.isEmpty) {
        continue;
      }

      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: widgets.isEmpty ? 0 : 24, bottom: 8),
          child: Text(
            _sectionTitle(status),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      );
      widgets.addAll(
        rides.map(
          (_RideWithClub item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                title: Text(item.rideItem.ride.title),
                subtitle: Text(_subtitle(item)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenRide(item.rideItem),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  String _subtitle(_RideWithClub item) {
    final List<String> parts = <String>[
      item.clubItem.club.name,
      if (item.rideItem.membership != null)
        item.rideItem.membership!.role.label,
    ];
    return parts.join(' · ');
  }

  String _sectionTitle(RideStatus status) {
    return switch (status) {
      RideStatus.active => 'Active Ride',
      RideStatus.published => 'Upcoming',
      RideStatus.draft => 'Drafts',
      RideStatus.completed => 'History',
      RideStatus.cancelled => 'Cancelled',
    };
  }
}

class _CreateRideCard extends StatelessWidget {
  const _CreateRideCard({required this.clubs, required this.onCreateRide});

  final List<ClubListItem> clubs;
  final ValueChanged<ClubListItem> onCreateRide;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Plan a Ride', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Buat Ride lalu susun rute, Stop, dan Checkpoint dari '
              'Route Planner.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            if (clubs.length == 1)
              FilledButton.icon(
                onPressed: () => onCreateRide(clubs.single),
                icon: const Icon(Icons.add_road_outlined),
                label: const Text('Buat Ride'),
              )
            else
              PopupMenuButton<ClubListItem>(
                onSelected: onCreateRide,
                itemBuilder: (BuildContext context) => clubs
                    .map(
                      (ClubListItem item) => PopupMenuItem<ClubListItem>(
                        value: item,
                        child: Text(item.club.name),
                      ),
                    )
                    .toList(growable: false),
                child: const FilledButtonIconLike(
                  icon: Icons.add_road_outlined,
                  label: 'Buat Ride',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FilledButtonIconLike extends StatelessWidget {
  const FilledButtonIconLike({
    required this.icon,
    required this.label,
    super.key,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: Theme.of(context).colorScheme.onPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRides extends StatelessWidget {
  const _EmptyRides({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _RideLoadError extends StatelessWidget {
  const _RideLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            const Text('Daftar Ride belum dapat dimuat.'),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class _RideOverview {
  const _RideOverview(this.groups);

  const _RideOverview.empty() : groups = const <_ClubRides>[];

  final List<_ClubRides> groups;
}

class _ClubRides {
  const _ClubRides({required this.clubItem, required this.rides});

  final ClubListItem clubItem;
  final List<RideListItem> rides;
}

class _RideWithClub {
  const _RideWithClub({required this.clubItem, required this.rideItem});

  final ClubListItem clubItem;
  final RideListItem rideItem;
}
