import 'package:flutter/material.dart';

import '../api/checkpoint_api.dart';
import '../api/club_ride_api.dart';
import '../api/ride_briefing_api.dart';
import '../api/ride_comms_api.dart';
import '../api/route_planner_api.dart';
import '../api/vehicle_api.dart';
import '../auth/auth_gateway.dart';
import '../config/app_config.dart';
import '../models/rider_profile.dart';
import '../screens/clubs/clubs_screen.dart';
import '../screens/explore/explore_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/ride/ride_screen.dart';

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
    required this.authGateway,
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
  final AuthGateway authGateway;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

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
      ),
      const ExploreScreen(),
      ClubsScreen(
        clubRideApi: widget.clubRideApi,
        checkpointApi: widget.checkpointApi,
        routePlannerApi: widget.routePlannerApi,
        rideBriefingApi: widget.rideBriefingApi,
        rideCommsApi: widget.rideCommsApi,
      ),
      ProfileScreen(
        riderProfile: widget.riderProfile,
        vehicleApi: widget.vehicleApi,
        authGateway: widget.authGateway,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: destinations),
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
