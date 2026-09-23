import 'dart:async';

import 'package:flutter/material.dart';

import '../active_ride/active_ride_runtime.dart';
import '../api/checkpoint_api.dart';
import '../api/club_ride_api.dart';
import '../api/notification_api.dart';
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
import '../screens/clubs/clubs_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/notifications/notification_center_screen.dart';
import '../screens/profile/profile_screen.dart';
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
    required this.notificationApi,
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
  final NotificationApi notificationApi;
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
  RideForegroundPush? _shownForegroundPush;

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
    final RideForegroundPush? message =
        _ridePushController?.state.latestForegroundPush;
    if (message == null ||
        identical(message, _shownForegroundPush) ||
        !mounted) {
      return;
    }
    _shownForegroundPush = message;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.displayText),
          action: SnackBarAction(
            label: 'Tutup',
            onPressed: () {
              _ridePushController?.clearForegroundPush();
            },
          ),
        ),
      );
    });
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => NotificationCenterScreen(
          notificationApi: widget.notificationApi,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> destinations = <Widget>[
      const HomeScreen(),
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
            _MainAppBrandHeader(onNotifications: _openNotifications),
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
  const _MainAppBrandHeader({required this.onNotifications});

  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 6, 10, 6),
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
                child: CommRideBrandImage(
                  variant: CommRideBrandVariant.primary,
                  width: 150,
                  height: 48,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Notifikasi',
              onPressed: onNotifications,
              icon: const Icon(Icons.notifications_none),
            ),
          ],
        ),
      ),
    );
  }
}
