import 'package:flutter/material.dart';

import '../../api/checkpoint_api.dart';
import '../../api/club_ride_api.dart';
import '../../api/ride_briefing_api.dart';
import '../../api/ride_comms_api.dart';
import '../../api/route_planner_api.dart';
import '../../active_ride/ride_comms_controller.dart';
import '../../models/club_ride.dart';
import 'checkpoints_screen.dart';
import 'ride_briefing_screen.dart';
import 'ride_comms_screen.dart';
import 'route_planner_screen.dart';

class RideDetailScreen extends StatefulWidget {
  const RideDetailScreen({
    required this.item,
    required this.clubRideApi,
    required this.checkpointApi,
    required this.routePlannerApi,
    required this.rideBriefingApi,
    required this.rideCommsApi,
    required this.onChanged,
    super.key,
  });

  final RideListItem item;
  final ClubRideApi clubRideApi;
  final CheckpointApi checkpointApi;
  final RoutePlannerApi routePlannerApi;
  final RideBriefingApi rideBriefingApi;
  final RideCommsApi rideCommsApi;
  final VoidCallback onChanged;

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  late RideListItem _item;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  @override
  Widget build(BuildContext context) {
    final Ride ride = _item.ride;
    final RideMembership? membership = _item.membership;
    final bool isLeader = membership?.role == RideRole.leader;
    final bool canReadRoute =
        membership != null &&
        membership.status != RideMembershipStatus.invited &&
        membership.status != RideMembershipStatus.left;
    final bool canEditRoute =
        isLeader &&
        (ride.status == RideStatus.draft ||
            ride.status == RideStatus.published);
    final bool canPublishBriefing = canEditRoute;
    final bool canAcknowledgeBriefing =
        ride.status == RideStatus.draft || ride.status == RideStatus.published;

    return Scaffold(
      appBar: AppBar(title: Text(ride.title)),
      body: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: ListView(
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text(ride.status.label)),
                if (membership != null)
                  Chip(label: Text(membership.role.label)),
              ],
            ),
            if (ride.scheduledStartAt != null) ...<Widget>[
              const SizedBox(height: 18),
              Text('Berangkat', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(_formatDateTime(ride.scheduledStartAt!.toLocal())),
            ],
            if (ride.notes != null) ...<Widget>[
              const SizedBox(height: 18),
              Text('Catatan', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(ride.notes!),
            ],
            const SizedBox(height: 28),
            if (canReadRoute) ...<Widget>[
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _openRoutePlanner(canEdit: canEditRoute),
                icon: const Icon(Icons.map_outlined),
                label: Text(canEditRoute ? 'Plan Route' : 'Lihat RoutePlan'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _working
                    ? null
                    : () => _openBriefing(
                        canPublish: canPublishBriefing,
                        canAcknowledge: canAcknowledgeBriefing,
                      ),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Ride Briefing'),
              ),
              const SizedBox(height: 8),
              if (ride.status == RideStatus.active ||
                  ride.status == RideStatus.completed) ...<Widget>[
                OutlinedButton.icon(
                  onPressed: _working ? null : _openCheckpoints,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Checkpoints'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _working ? null : _openComms,
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Comms'),
                ),
                const SizedBox(height: 8),
              ],
            ],
            if (membership?.status == RideMembershipStatus.invited)
              FilledButton(
                onPressed: _working ? null : _joinRide,
                child: const Text('Gabung Ride'),
              ),
            if (isLeader) ...<Widget>[
              if (ride.status == RideStatus.draft)
                FilledButton(
                  onPressed: _working ? null : _publishRide,
                  child: const Text('Publish Ride'),
                ),
              if (ride.status == RideStatus.published)
                FilledButton(
                  onPressed: _working ? null : _startRide,
                  child: const Text('Start Ride'),
                ),
              if (ride.status == RideStatus.active)
                FilledButton(
                  onPressed: _working ? null : _endRide,
                  child: const Text('End Ride'),
                ),
              if (ride.status == RideStatus.draft ||
                  ride.status == RideStatus.published) ...<Widget>[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _working ? null : _confirmCancelRide,
                  child: const Text('Cancel Ride'),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _working ? null : _inviteRider,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Undang Rider'),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Live Ride map dan convoy visualization akan '
              'ditambahkan pada fase berikutnya.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openComms() async {
    final RideMembership? membership = _item.membership;
    if (membership == null ||
        membership.status == RideMembershipStatus.invited ||
        membership.status == RideMembershipStatus.left) {
      return;
    }

    final RideCommsController controller = RideCommsController(
      rideId: _item.ride.id,
      api: widget.rideCommsApi,
    );

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RideCommsScreen(
          ride: _item.ride,
          membership: membership,
          controller: controller,
        ),
      ),
    );
  }

  Future<void> _openCheckpoints() async {
    final RideMembership? membership = _item.membership;
    if (membership == null) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CheckpointsScreen(
          ride: _item.ride,
          membership: membership,
          checkpointApi: widget.checkpointApi,
        ),
      ),
    );
  }

  Future<void> _openRoutePlanner({required bool canEdit}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RoutePlannerScreen(
          rideId: _item.ride.id,
          routePlannerApi: widget.routePlannerApi,
          canEdit: canEdit,
        ),
      ),
    );
  }

  Future<void> _openBriefing({
    required bool canPublish,
    required bool canAcknowledge,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RideBriefingScreen(
          ride: _item.ride,
          rideBriefingApi: widget.rideBriefingApi,
          routePlannerApi: widget.routePlannerApi,
          canPublish: canPublish,
          canAcknowledge: canAcknowledge,
        ),
      ),
    );
  }

  Future<void> _joinRide() async {
    await _run(() async {
      await widget.clubRideApi.joinRide(_item.ride.id);
      final RideMembership? membership = _item.membership;
      if (membership != null) {
        _item = RideListItem(
          ride: _item.ride,
          membership: RideMembership(
            rideId: membership.rideId,
            riderId: membership.riderId,
            role: membership.role,
            status: RideMembershipStatus.joined,
          ),
        );
      }
    });
  }

  Future<void> _publishRide() {
    return _transition(widget.clubRideApi.publishRide);
  }

  Future<void> _startRide() {
    return _transition(widget.clubRideApi.startRide);
  }

  Future<void> _endRide() {
    return _transition(widget.clubRideApi.endRide);
  }

  Future<void> _confirmCancelRide() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cancel Ride?'),
          content: const Text(
            'Ride yang belum dimulai akan ditandai Cancelled. '
            'Ride yang sudah Active harus diakhiri dengan End Ride.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cancel Ride'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _transition(widget.clubRideApi.cancelRide);
    }
  }

  Future<void> _transition(Future<Ride> Function(String) action) async {
    await _run(() async {
      final Ride updated = await action(_item.ride.id);
      _item = RideListItem(ride: updated, membership: _item.membership);
    });
  }

  Future<void> _inviteRider() async {
    final _RideInviteInput? input = await showDialog<_RideInviteInput>(
      context: context,
      builder: (BuildContext context) => const _RideInviteDialog(),
    );

    if (input == null) {
      return;
    }

    await _run(() async {
      await widget.clubRideApi.inviteRideMember(
        rideId: _item.ride.id,
        riderId: input.riderId,
        role: input.role,
      );
    }, successMessage: 'Undangan Ride dikirim.');
  }

  Future<void> _run(
    Future<void> Function() operation, {
    String? successMessage,
  }) async {
    setState(() {
      _working = true;
    });

    try {
      await operation();
      if (!mounted) {
        return;
      }

      widget.onChanged();
      if (successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      setState(() {});
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aksi belum dapat diselesaikan.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
    }
  }
}

class _RideInviteInput {
  const _RideInviteInput(this.riderId, this.role);

  final String riderId;
  final RideRole role;
}

class _RideInviteDialog extends StatefulWidget {
  const _RideInviteDialog();

  @override
  State<_RideInviteDialog> createState() => _RideInviteDialogState();
}

class _RideInviteDialogState extends State<_RideInviteDialog> {
  final TextEditingController _riderIdController = TextEditingController();
  RideRole _role = RideRole.member;

  @override
  void dispose() {
    _riderIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const List<RideRole> roles = <RideRole>[
      RideRole.member,
      RideRole.sweeper,
      RideRole.navigator,
    ];

    return AlertDialog(
      title: const Text('Undang Rider'),
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
          DropdownButtonFormField<RideRole>(
            initialValue: _role,
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(),
            ),
            items: roles
                .map(
                  (RideRole role) => DropdownMenuItem<RideRole>(
                    value: role,
                    child: Text(role.label),
                  ),
                )
                .toList(growable: false),
            onChanged: (RideRole? value) {
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
            if (riderId.isEmpty) {
              return;
            }
            Navigator.of(context).pop(_RideInviteInput(riderId, _role));
          },
          child: const Text('Undang'),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} · '
      '${two(value.hour)}:${two(value.minute)}';
}
