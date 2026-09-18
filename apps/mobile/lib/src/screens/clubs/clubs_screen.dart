import 'package:flutter/material.dart';

import '../../api/checkpoint_api.dart';
import '../../api/club_ride_api.dart';
import '../../api/ride_briefing_api.dart';
import '../../api/route_planner_api.dart';
import '../../models/club_ride.dart';
import 'club_detail_screen.dart';
import 'create_club_screen.dart';

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({
    required this.clubRideApi,
    required this.checkpointApi,
    required this.routePlannerApi,
    required this.rideBriefingApi,
    super.key,
  });

  final ClubRideApi clubRideApi;
  final CheckpointApi checkpointApi;
  final RoutePlannerApi routePlannerApi;
  final RideBriefingApi rideBriefingApi;

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  late Future<List<ClubListItem>> _clubsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateClub,
        icon: const Icon(Icons.add),
        label: const Text('Buat Club'),
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar.large(
            title: const Text('Clubs'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Muat ulang',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
            sliver: SliverToBoxAdapter(
              child: FutureBuilder<List<ClubListItem>>(
                future: _clubsFuture,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<ClubListItem>> snapshot,
                    ) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (snapshot.hasError) {
                        return _LoadError(onRetry: _refresh);
                      }

                      final List<ClubListItem> clubs =
                          snapshot.data ?? const <ClubListItem>[];
                      if (clubs.isEmpty) {
                        return const _EmptyClubs();
                      }

                      return Column(
                        children: clubs
                            .map((ClubListItem item) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.groups_outlined),
                                    ),
                                    title: Text(item.club.name),
                                    subtitle: Text(_subtitle(item)),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openClub(item),
                                  ),
                                ),
                              );
                            })
                            .toList(growable: false),
                      );
                    },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(ClubListItem item) {
    final List<String> parts = <String>[
      item.membership.role.label,
      if (item.membership.status == ClubMembershipStatus.invited) 'Undangan',
      if (item.club.homeArea != null) item.club.homeArea!,
    ];

    return parts.join(' · ');
  }

  void _reload() {
    _clubsFuture = widget.clubRideApi.listClubs();
  }

  void _refresh() {
    setState(_reload);
  }

  Future<void> _openCreateClub() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CreateClubScreen(
          clubRideApi: widget.clubRideApi,
          onCreated: (_) => _refresh(),
        ),
      ),
    );
  }

  Future<void> _openClub(ClubListItem item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ClubDetailScreen(
          item: item,
          clubRideApi: widget.clubRideApi,
          checkpointApi: widget.checkpointApi,
          routePlannerApi: widget.routePlannerApi,
          rideBriefingApi: widget.rideBriefingApi,
          onChanged: _refresh,
        ),
      ),
    );
  }
}

class _EmptyClubs extends StatelessWidget {
  const _EmptyClubs();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            const Icon(Icons.groups_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              'Belum ada Club',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Buat Club untuk mulai mengorganisasi Ride. Undangan dari Club '
              'lain juga akan muncul di sini.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            const Text('Daftar Club belum dapat dimuat.'),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}
