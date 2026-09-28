import 'package:flutter/material.dart';

import '../../api/club_ride_api.dart';
import '../../models/club_ride.dart';
import '../../theme/commride_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.clubRideApi,
    required this.onOpenRide,
    required this.onOpenClub,
    super.key,
  });

  final ClubRideApi clubRideApi;
  final ValueChanged<RideListItem> onOpenRide;
  final ValueChanged<ClubListItem> onOpenClub;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final List<ClubListItem> clubs = await widget.clubRideApi.listClubs();
    final List<ClubListItem> activeClubs = clubs
        .where(
          (ClubListItem item) =>
              item.membership.status == ClubMembershipStatus.active,
        )
        .toList(growable: false);

    final List<_RideWithClub> rides = <_RideWithClub>[];
    for (final ClubListItem club in activeClubs) {
      final List<RideListItem> clubRides = await widget.clubRideApi.listRides(
        club.club.id,
      );
      rides.addAll(
        clubRides.map(
          (RideListItem ride) => _RideWithClub(club: club, rideItem: ride),
        ),
      );
    }

    final List<_RideWithClub> active = rides
        .where(
          (_RideWithClub item) =>
              item.rideItem.ride.status == RideStatus.active,
        )
        .toList(growable: false);
    final List<_RideWithClub> upcoming =
        rides
            .where(
              (_RideWithClub item) =>
                  item.rideItem.ride.status == RideStatus.published,
            )
            .toList()
          ..sort((_RideWithClub a, _RideWithClub b) {
            final DateTime? left = a.rideItem.ride.scheduledStartAt;
            final DateTime? right = b.rideItem.ride.scheduledStartAt;
            if (left == null && right == null) return 0;
            if (left == null) return 1;
            if (right == null) return -1;
            return left.compareTo(right);
          });

    final List<ClubListItem> clubInvites = clubs
        .where(
          (ClubListItem item) =>
              item.membership.status == ClubMembershipStatus.invited,
        )
        .toList(growable: false);
    final List<_RideWithClub> rideInvites = rides
        .where(
          (_RideWithClub item) =>
              item.rideItem.membership?.status == RideMembershipStatus.invited,
        )
        .toList(growable: false);

    final List<_RideWithClub> activity = rides
        .where(
          (_RideWithClub item) =>
              item.rideItem.ride.status == RideStatus.completed ||
              item.rideItem.ride.status == RideStatus.published,
        )
        .take(6)
        .toList(growable: false);

    return _HomeData(
      active: active,
      upcoming: upcoming,
      clubInvites: clubInvites,
      rideInvites: rideInvites,
      activity: activity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(_reload);
        await _future;
      },
      child: FutureBuilder<_HomeData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_HomeData> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ListView(
              physics: AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator()),
              ],
            );
          }

          if (snapshot.hasError || snapshot.data == null) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(CommRideSpacing.lg),
              children: <Widget>[
                const SizedBox(height: 80),
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: CommRideSpacing.sm),
                const Text(
                  'Home belum dapat dimuat. Data Ride Anda tetap aman.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: CommRideSpacing.sm),
                FilledButton(
                  onPressed: () => setState(_reload),
                  child: const Text('Coba lagi'),
                ),
              ],
            );
          }

          return _HomeContent(
            data: snapshot.data!,
            onOpenRide: widget.onOpenRide,
            onOpenClub: widget.onOpenClub,
          );
        },
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.data,
    required this.onOpenRide,
    required this.onOpenClub,
  });

  final _HomeData data;
  final ValueChanged<RideListItem> onOpenRide;
  final ValueChanged<ClubListItem> onOpenClub;

  @override
  Widget build(BuildContext context) {
    final _RideWithClub? active = data.active.isEmpty
        ? null
        : data.active.first;
    final _RideWithClub? upcoming = data.upcoming.isEmpty
        ? null
        : data.upcoming.first;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        CommRideSpacing.md,
        CommRideSpacing.md,
        CommRideSpacing.md,
        CommRideSpacing.xl,
      ),
      children: <Widget>[
        Text('Home', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: CommRideSpacing.md),
        if (active != null) ...<Widget>[
          _PriorityRideCard(
            title: 'Active Ride',
            item: active,
            icon: Icons.navigation,
            emphasized: true,
            onTap: () => onOpenRide(active.rideItem),
          ),
          const SizedBox(height: CommRideSpacing.md),
        ],
        if (upcoming != null) ...<Widget>[
          _PriorityRideCard(
            title: 'Ride berikutnya',
            item: upcoming,
            icon: Icons.event_outlined,
            onTap: () => onOpenRide(upcoming.rideItem),
          ),
          const SizedBox(height: CommRideSpacing.md),
        ],
        Text(
          'Undangan & perhatian',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: CommRideSpacing.xs),
        if (data.clubInvites.isEmpty && data.rideInvites.isEmpty)
          const _QuietCard(
            icon: Icons.check_circle_outline,
            text: 'Tidak ada undangan yang menunggu.',
          )
        else ...<Widget>[
          ...data.clubInvites.map(
            (ClubListItem item) => Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text('Undangan Club · ${item.club.name}'),
                subtitle: const Text(
                  'Buka Club untuk melihat detail undangan.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenClub(item),
              ),
            ),
          ),
          ...data.rideInvites.map(
            (_RideWithClub item) => Card(
              child: ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text('Undangan Ride · ${item.rideItem.ride.title}'),
                subtitle: Text(item.club.club.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenRide(item.rideItem),
              ),
            ),
          ),
        ],
        const SizedBox(height: CommRideSpacing.lg),
        Text('Aktivitas Club', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: CommRideSpacing.xs),
        if (data.activity.isEmpty)
          const _QuietCard(
            icon: Icons.dynamic_feed_outlined,
            text: 'Belum ada aktivitas Ride terbaru dari Club Anda.',
          )
        else
          ...data.activity.map(
            (_RideWithClub item) => Card(
              child: ListTile(
                leading: Icon(
                  item.rideItem.ride.status == RideStatus.completed
                      ? Icons.flag_outlined
                      : Icons.event_available_outlined,
                ),
                title: Text(item.rideItem.ride.title),
                subtitle: Text(
                  '${item.club.club.name} · ${item.rideItem.ride.status.label}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenRide(item.rideItem),
              ),
            ),
          ),
      ],
    );
  }
}

class _PriorityRideCard extends StatelessWidget {
  const _PriorityRideCard({
    required this.title,
    required this.item,
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  final String title;
  final _RideWithClub item;
  final IconData icon;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final Color background = emphasized
        ? Theme.of(context).colorScheme.primary
        : Colors.white;
    final Color foreground = emphasized
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    return Card(
      color: background,
      child: InkWell(
        borderRadius: BorderRadius.circular(CommRideRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(CommRideSpacing.md),
          child: Row(
            children: <Widget>[
              Icon(icon, color: foreground, size: 32),
              const SizedBox(width: CommRideSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: CommRideSpacing.xxs),
                    Text(
                      item.rideItem.ride.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: foreground),
                    ),
                    const SizedBox(height: CommRideSpacing.xxs),
                    Text(
                      _rideMeta(item),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }

  String _rideMeta(_RideWithClub item) {
    final DateTime? start = item.rideItem.ride.scheduledStartAt?.toLocal();
    final List<String> parts = <String>[
      item.club.club.name,
      if (item.rideItem.membership != null)
        item.rideItem.membership!.role.label,
      if (start != null) _formatDateTime(start),
    ];
    return parts.join(' · ');
  }
}

class _QuietCard extends StatelessWidget {
  const _QuietCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(CommRideSpacing.md),
        child: Row(
          children: <Widget>[
            Icon(icon),
            const SizedBox(width: CommRideSpacing.sm),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.active,
    required this.upcoming,
    required this.clubInvites,
    required this.rideInvites,
    required this.activity,
  });

  final List<_RideWithClub> active;
  final List<_RideWithClub> upcoming;
  final List<ClubListItem> clubInvites;
  final List<_RideWithClub> rideInvites;
  final List<_RideWithClub> activity;
}

class _RideWithClub {
  const _RideWithClub({required this.club, required this.rideItem});

  final ClubListItem club;
  final RideListItem rideItem;
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)} · '
      '${two(value.hour)}:${two(value.minute)}';
}
