import 'dart:async';

import 'package:flutter/material.dart';

import '../active_ride/active_ride_runtime.dart';
import '../api/checkpoint_api.dart';
import '../api/club_ride_api.dart';
import '../api/push_token_api.dart';
import '../api/ride_briefing_api.dart';
import '../api/ride_comms_api.dart';
import '../api/ride_recap_api.dart';
import '../api/ride_sos_api.dart';
import '../api/route_planner_api.dart';
import '../api/vehicle_api.dart';
import '../auth/auth_gateway.dart';
import '../config/app_config.dart';
import '../models/rider_profile.dart';
import '../push/ride_push_controller.dart';
import '../push/ride_push_messaging.dart';
import '../screens/clubs/club_detail_screen.dart';
import '../screens/clubs/clubs_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/notifications/ride_notifications_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/ride/ride_detail_screen.dart';
import '../screens/ride/ride_screen.dart';
import '../widgets/commride_brand.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.config,
    required this.riderProfile,
    required this.vehicleApi,
    required this.clubRideApi,
    required this.checkpointApi,
    required this.routePlannerApi,
    required this.rideBriefingApi,
    required this.rideCommsApi,
    required this.rideSosApi,
    this.rideRecapApi,
    required this.authGateway,
    this.pushTokenApi,
    this.pushMessaging,
    this.pushPlatform,
    super.key,
  });

  final AppConfig config;
  final RiderProfile riderProfile;
  final VehicleApi vehicleApi;
  final ClubRideApi clubRideApi;
  final CheckpointApi checkpointApi;
  final RoutePlannerApi routePlannerApi;
  final RideBriefingApi rideBriefingApi;
  final RideCommsApi rideCommsApi;
  final RideSosApi rideSosApi;
  final RideRecapApi? rideRecapApi;
  final AuthGateway authGateway;
  final PushTokenApi? pushTokenApi;
  final RidePushMessaging? pushMessaging;
  final RidePushPlatform? pushPlatform;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  ActiveRideRuntimeManager? _activeRideRuntimeManager;
  RidePushController? _ridePushController;
  String? _shownForegroundNotificationId;

  @override
  void initState() {
    super.initState();
    final Uri? apiBaseUrl = widget.config.apiBaseUrl;
    if (apiBaseUrl != null) {
      _activeRideRuntimeManager = ActiveRideRuntimeManager(
        apiBaseUrl: apiBaseUrl,
        authGateway: widget.authGateway,
      );
    }

    final PushTokenApi? pushTokenApi = widget.pushTokenApi;
    final RidePushMessaging? pushMessaging = widget.pushMessaging;
    final RidePushPlatform? pushPlatform = widget.pushPlatform;
    if (pushTokenApi != null && pushMessaging != null && pushPlatform != null) {
      final RidePushController controller = RidePushController(
        tokenApi: pushTokenApi,
        messaging: pushMessaging,
        platform: pushPlatform,
      );
      _ridePushController = controller;
      controller.addListener(_onPushStateChanged);
      unawaited(controller.start());
    }
  }

  @override
  void dispose() {
    _ridePushController?.removeListener(_onPushStateChanged);
    _ridePushController?.dispose();
    _activeRideRuntimeManager?.dispose();
    super.dispose();
  }

  void _onPushStateChanged() {
    final RidePushController? controller = _ridePushController;
    if (controller == null || !mounted) {
      return;
    }
    final RidePushState state = controller.state;
    final RideNotificationEntry? notification = state.notifications.isEmpty
        ? null
        : state.notifications.first;
    if (notification == null ||
        notification.id == _shownForegroundNotificationId) {
      return;
    }
    _shownForegroundNotificationId = notification.id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notification.message.displayText),
          action: SnackBarAction(
            label: 'Buka',
            onPressed: () {
              unawaited(_openNotification(notification));
            },
          ),
        ),
      );
    });
  }

  Future<void> _openNotifications() async {
    final RidePushController? controller = _ridePushController;
    if (controller == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifikasi belum tersedia pada konfigurasi ini.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RideNotificationsScreen(
          controller: controller,
          onOpen: _openNotification,
        ),
      ),
    );
  }

  Future<void> _openNotification(RideNotificationEntry notification) async {
    _ridePushController?.markNotificationRead(notification.id);
    _ridePushController?.clearForegroundPush();

    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      await Future<void>.delayed(Duration.zero);
    }

    final String? rideId = notification.rideId;
    if (rideId != null) {
      final RideListItem? ride = await _findRide(rideId);
      if (!mounted) {
        return;
      }
      if (ride != null) {
        await _openRide(ride);
        return;
      }
    }

    final String? clubId = notification.clubId;
    if (clubId != null) {
      final List<ClubListItem> clubs = await widget.clubRideApi.listClubs();
      if (!mounted) {
        return;
      }
      for (final ClubListItem club in clubs) {
        if (club.club.id == clubId) {
          await _openClub(club);
          return;
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tujuan notifikasi belum dapat dibuka.')),
      );
    }
  }

  Future<RideListItem?> _findRide(String rideId) async {
    final List<ClubListItem> clubs = await widget.clubRideApi.listClubs();
    for (final ClubListItem club in clubs) {
      if (club.membership.status != ClubMembershipStatus.active) {
        continue;
      }
      try {
        final List<RideListItem> rides = await widget.clubRideApi.listRides(
          club.club.id,
        );
        for (final RideListItem item in rides) {
          if (item.ride.id == rideId) {
            return item;
          }
        }
      } catch (_) {
        // Continue through other accessible Clubs.
      }
    }
    return null;
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
          activeRideRuntimeManager: _activeRideRuntimeManager,
          mapsEnabled: widget.config.mapsEnabled,
          navigationEnabled: widget.config.navigationEnabled,
          voiceIntercomEnabled: widget.config.voiceIntercomEnabled,
          onChanged: () => setState(() {}),
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
          rideCommsApi: widget.rideCommsApi,
          rideSosApi: widget.rideSosApi,
          rideRecapApi: widget.rideRecapApi,
          activeRideRuntimeManager: _activeRideRuntimeManager,
          mapsEnabled: widget.config.mapsEnabled,
          navigationEnabled: widget.config.navigationEnabled,
          voiceIntercomEnabled: widget.config.voiceIntercomEnabled,
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> destinations = <Widget>[
      HomeScreen(
        clubRideApi: widget.clubRideApi,
        onOpenRide: _openRide,
        onOpenClub: _openClub,
      ),
      RideScreen(
        clubRideApi: widget.clubRideApi,
        checkpointApi: widget.checkpointApi,
        routePlannerApi: widget.routePlannerApi,
        rideBriefingApi: widget.rideBriefingApi,
        rideCommsApi: widget.rideCommsApi,
        rideSosApi: widget.rideSosApi,
        rideRecapApi: widget.rideRecapApi,
        activeRideRuntimeManager: _activeRideRuntimeManager,
        mapsEnabled: widget.config.mapsEnabled,
        navigationEnabled: widget.config.navigationEnabled,
        voiceIntercomEnabled: widget.config.voiceIntercomEnabled,
      ),
      const ExploreScreen(),
      ClubsScreen(
        clubRideApi: widget.clubRideApi,
        checkpointApi: widget.checkpointApi,
        routePlannerApi: widget.routePlannerApi,
        rideBriefingApi: widget.rideBriefingApi,
        rideCommsApi: widget.rideCommsApi,
        rideSosApi: widget.rideSosApi,
        rideRecapApi: widget.rideRecapApi,
        activeRideRuntimeManager: _activeRideRuntimeManager,
        mapsEnabled: widget.config.mapsEnabled,
        navigationEnabled: widget.config.navigationEnabled,
        voiceIntercomEnabled: widget.config.voiceIntercomEnabled,
      ),
      ProfileScreen(
        riderProfile: widget.riderProfile,
        vehicleApi: widget.vehicleApi,
        authGateway: widget.authGateway,
        ridePushController: _ridePushController,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _MainAppBrandHeader(
              ridePushController: _ridePushController,
              onOpenNotifications: _openNotifications,
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedIndex,
                children: destinations,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Ride',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Clubs',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _MainAppBrandHeader extends StatelessWidget {
  const _MainAppBrandHeader({
    required this.ridePushController,
    required this.onOpenNotifications,
  });

  final RidePushController? ridePushController;
  final Future<void> Function() onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: CommRideHeaderBrand(),
              ),
            ),
            if (ridePushController == null)
              IconButton(
                tooltip: 'Notifikasi',
                onPressed: () => unawaited(onOpenNotifications()),
                icon: const Icon(Icons.notifications_none),
              )
            else
              ListenableBuilder(
                listenable: ridePushController!,
                builder: (BuildContext context, Widget? child) {
                  final int unread = ridePushController!.state.unreadCount;
                  return IconButton(
                    tooltip: unread > 0
                        ? 'Notifikasi · $unread belum dibaca'
                        : 'Notifikasi',
                    onPressed: () => unawaited(onOpenNotifications()),
                    icon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text(unread > 99 ? '99+' : '$unread'),
                      child: Icon(
                        unread > 0
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
