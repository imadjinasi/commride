import 'package:flutter/material.dart';

import 'api/checkpoint_api.dart';
import 'api/club_ride_api.dart';
import 'api/rider_profile_api.dart';
import 'api/ride_briefing_api.dart';
import 'api/route_planner_api.dart';
import 'api/vehicle_api.dart';
import 'auth/auth_gateway.dart';
import 'auth/auth_gate.dart';
import 'config/app_config.dart';
import 'screens/setup/setup_required_screen.dart';
import 'theme/commride_theme.dart';

class CommRideApp extends StatelessWidget {
  const CommRideApp({
    required this.config,
    required this.authGateway,
    required this.riderProfileApi,
    required this.vehicleApi,
    required this.clubRideApi,
    required this.checkpointApi,
    required this.routePlannerApi,
    required this.rideBriefingApi,
    super.key,
  });

  final AppConfig config;
  final AuthGateway authGateway;
  final RiderProfileApi riderProfileApi;
  final VehicleApi vehicleApi;
  final ClubRideApi clubRideApi;
  final CheckpointApi checkpointApi;
  final RoutePlannerApi routePlannerApi;
  final RideBriefingApi rideBriefingApi;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CommRide',
      debugShowCheckedModeBanner:
          config.environment != AppEnvironment.production,
      theme: CommRideTheme.light(),
      home: AuthGate(
        config: config,
        authGateway: authGateway,
        riderProfileApi: riderProfileApi,
        vehicleApi: vehicleApi,
        clubRideApi: clubRideApi,
        checkpointApi: checkpointApi,
        routePlannerApi: routePlannerApi,
        rideBriefingApi: rideBriefingApi,
      ),
    );
  }
}

class CommRideSetupApp extends StatelessWidget {
  const CommRideSetupApp({
    required this.config,
    required this.message,
    super.key,
  });

  final AppConfig config;
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CommRide',
      debugShowCheckedModeBanner:
          config.environment != AppEnvironment.production,
      theme: CommRideTheme.light(),
      home: SetupRequiredScreen(message: message),
    );
  }
}
