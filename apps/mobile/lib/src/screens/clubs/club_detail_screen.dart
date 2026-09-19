import 'package:flutter/material.dart';

import '../../api/checkpoint_api.dart';
import '../../api/club_ride_api.dart';
import '../../api/ride_briefing_api.dart';
import '../../api/ride_comms_api.dart';
import '../../api/ride_sos_api.dart';
import '../../api/route_planner_api.dart';
import '../../models/club_ride.dart';
import '../ride/create_ride_screen.dart';
import '../ride/ride_detail_screen.dart';

class ClubDetailScreen extends StatefulWidget {
  const ClubDetailScreen({
    required this.item,
    required this.clubRideApi,
    required this.checkpointApi,
    required this.routePlannerApi,
    required this.rideBriefingApi,
    required this.rideCommsApi,
    required this.rideSosApi,
    required this.onChanged,
    super.key,
  });

  final ClubListItem item;
  final ClubRideApi clubRideApi;
  final CheckpointApi checkpointApi;
  final RoutePlannerApi routePlannerApi;
  final RideBriefingApi rideBriefingApi;
  final RideCommsApi rideCommsApi;
  final RideSosApi rideSosApi;
  final VoidCallback onChanged;

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  late ClubListItem _item;
  Future<List<RideListItem>>? _ridesFuture;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _reloadRidesIfActive();
  }

  @override
  Widget build(BuildContext context) {
    final Club club = _item.club;
    final ClubMembership membership = _item.membership;
    final bool canManage =
        membership.status == ClubMembershipStatus.active &&
        (membership.role == ClubRole.owner ||
            membership.role == ClubRole.admin);

    return Scaffold(
      appBar: AppBar(title: Text(club.name)),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _openCreateRide,
              icon: const Icon(Icons.add_road_outlined),
              label: const Text('Buat Ride'),
            )
          : null,
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: ListView(
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text(membership.role.label)),
                Chip(label: Text(club.visibility.label)),
              ],
            ),
            if (club.homeArea != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                club.homeArea!,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
            if (membership.status == ClubMembershipStatus.invited) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _working ? null : _joinClub,
                child: const Text('Gabung Club'),
              ),
              const SizedBox(height: 8),
              Text(
                'Anda baru dapat melihat Ride Club setelah undangan diterima.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (membership.status == ClubMembershipStatus.active) ...<Widget>[
              const SizedBox(height: 28),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Rides',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Muat ulang',
                    onPressed: _reloadRides,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildRides(),
              if (canManage) ...<Widget>[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _working ? null : _inviteMember,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Undang anggota Club'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRides() {
    final Future<List<RideListItem>>? future = _ridesFuture;
    if (future == null) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<RideListItem>>(
      future: future,
      builder:
          (BuildContext context, AsyncSnapshot<List<RideListItem>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return _LoadError(onRetry: _reloadRides);
            }

            final List<RideListItem> rides =
                snapshot.data ?? const <RideListItem>[];
            if (rides.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    'Belum ada Ride di Club ini.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              );
            }

            return Column(
              children: rides
                  .map((RideListItem item) {
                    return Card(
                      child: ListTile(
                        title: Text(item.ride.title),
                        subtitle: Text(_rideSubtitle(item)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openRide(item),
                      ),
                    );
                  })
                  .toList(growable: false),
            );
          },
    );
  }

  String _rideSubtitle(RideListItem item) {
    final List<String> parts = <String>[
      item.ride.status.label,
      if (item.membership != null) item.membership!.role.label,
    ];
    return parts.join(' · ');
  }

  void _reloadRidesIfActive() {
    if (_item.membership.status == ClubMembershipStatus.active) {
      _ridesFuture = widget.clubRideApi.listRides(_item.club.id);
    }
  }

  void _reloadRides() {
    setState(() {
      _ridesFuture = widget.clubRideApi.listRides(_item.club.id);
    });
  }

  Future<void> _joinClub() async {
    setState(() {
      _working = true;
    });

    try {
      await widget.clubRideApi.joinClub(_item.club.id);
      if (!mounted) {
        return;
      }

      _item = ClubListItem(
        club: _item.club,
        membership: ClubMembership(
          clubId: _item.membership.clubId,
          riderId: _item.membership.riderId,
          role: _item.membership.role,
          status: ClubMembershipStatus.active,
        ),
      );
      widget.onChanged();
      _reloadRides();
    } catch (_) {
      if (mounted) {
        _showError('Undangan Club belum dapat diterima.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  Future<void> _openCreateRide() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CreateRideScreen(
          clubId: _item.club.id,
          clubRideApi: widget.clubRideApi,
          onCreated: (_) {
            widget.onChanged();
            _reloadRides();
          },
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
          onChanged: () {
            widget.onChanged();
            _reloadRides();
          },
        ),
      ),
    );
  }

  Future<void> _inviteMember() async {
    final _ClubInviteInput? input = await showDialog<_ClubInviteInput>(
      context: context,
      builder: (BuildContext context) => const _ClubInviteDialog(),
    );

    if (input == null) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await widget.clubRideApi.inviteClubMember(
        clubId: _item.club.id,
        riderId: input.riderId,
        role: input.role,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Undangan Club dikirim.')));
      }
    } catch (_) {
      if (mounted) {
        _showError('Undangan belum dapat dikirim.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            const Text('Ride Club belum dapat dimuat.'),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }
}

class _ClubInviteInput {
  const _ClubInviteInput(this.riderId, this.role);

  final String riderId;
  final ClubRole role;
}

class _ClubInviteDialog extends StatefulWidget {
  const _ClubInviteDialog();

  @override
  State<_ClubInviteDialog> createState() => _ClubInviteDialogState();
}

class _ClubInviteDialogState extends State<_ClubInviteDialog> {
  final TextEditingController _riderIdController = TextEditingController();
  ClubRole _role = ClubRole.member;

  @override
  void dispose() {
    _riderIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const List<ClubRole> roles = <ClubRole>[ClubRole.member, ClubRole.admin];

    return AlertDialog(
      title: const Text('Undang anggota Club'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _riderIdController,
            decoration: const InputDecoration(
              labelText: 'Rider ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ClubRole>(
            initialValue: _role,
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(),
            ),
            items: roles
                .map(
                  (ClubRole role) => DropdownMenuItem<ClubRole>(
                    value: role,
                    child: Text(role.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (ClubRole? value) {
              if (value != null) {
                setState(() {
                  _role = value;
                });
              }
            },
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final String riderId = _riderIdController.text.trim();
            if (riderId.isNotEmpty) {
              Navigator.of(context).pop(_ClubInviteInput(riderId, _role));
            }
          },
          child: const Text('Undang'),
        ),
      ],
    );
  }
}
