import 'package:flutter/material.dart';

import '../api/club_ride_api.dart';
import '../api/rider_profile_api.dart';
import '../api/ride_briefing_api.dart';
import '../api/route_planner_api.dart';
import '../api/vehicle_api.dart';
import '../config/app_config.dart';
import '../models/rider_profile.dart';
import '../navigation/app_shell.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/profile/rider_profile_onboarding_screen.dart';
import 'auth_gateway.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    required this.config,
    required this.authGateway,
    required this.riderProfileApi,
    required this.vehicleApi,
    required this.clubRideApi,
    required this.routePlannerApi,
    required this.rideBriefingApi,
    super.key,
  });

  final AppConfig config;
  final AuthGateway authGateway;
  final RiderProfileApi riderProfileApi;
  final VehicleApi vehicleApi;
  final ClubRideApi clubRideApi;
  final RoutePlannerApi routePlannerApi;
  final RideBriefingApi rideBriefingApi;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: authGateway.authStateChanges(),
      builder: (BuildContext context, AsyncSnapshot<AuthUser?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        if (snapshot.hasError) {
          return _ErrorScreen(
            message: 'Status akun belum dapat dibaca.',
            onRetry: () {},
          );
        }

        final AuthUser? user = snapshot.data;
        if (user == null) {
          return SignInScreen(authGateway: authGateway);
        }

        return _RiderProfileGate(
          key: ValueKey<String>(user.id),
          config: config,
          authGateway: authGateway,
          riderProfileApi: riderProfileApi,
          vehicleApi: vehicleApi,
          clubRideApi: clubRideApi,
          routePlannerApi: routePlannerApi,
          rideBriefingApi: rideBriefingApi,
        );
      },
    );
  }
}

class _RiderProfileGate extends StatefulWidget {
  const _RiderProfileGate({
    required this.config,
    required this.authGateway,
    required this.riderProfileApi,
    required this.vehicleApi,
    required this.clubRideApi,
    required this.routePlannerApi,
    required this.rideBriefingApi,
    super.key,
  });

  final AppConfig config;
  final AuthGateway authGateway;
  final RiderProfileApi riderProfileApi;
  final VehicleApi vehicleApi;
  final ClubRideApi clubRideApi;
  final RoutePlannerApi routePlannerApi;
  final RideBriefingApi rideBriefingApi;

  @override
  State<_RiderProfileGate> createState() => _RiderProfileGateState();
}

class _RiderProfileGateState extends State<_RiderProfileGate> {
  late Future<RiderProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RiderProfile?>(
      future: _profileFuture,
      builder: (BuildContext context, AsyncSnapshot<RiderProfile?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }

        if (snapshot.hasError) {
          return _ErrorScreen(
            message: 'Profil Rider belum dapat dimuat.',
            onRetry: () {
              setState(_reload);
            },
            secondaryActionLabel: 'Keluar',
            onSecondaryAction: widget.authGateway.signOut,
          );
        }

        final RiderProfile? profile = snapshot.data;
        if (profile == null) {
          return RiderProfileOnboardingScreen(
            riderProfileApi: widget.riderProfileApi,
            onSaved: (RiderProfile savedProfile) {
              setState(() {
                _profileFuture = Future<RiderProfile?>.value(savedProfile);
              });
            },
          );
        }

        return AppShell(
          config: widget.config,
          riderProfile: profile,
          vehicleApi: widget.vehicleApi,
          clubRideApi: widget.clubRideApi,
          routePlannerApi: widget.routePlannerApi,
          rideBriefingApi: widget.rideBriefingApi,
          authGateway: widget.authGateway,
        );
      },
    );
  }

  void _reload() {
    _profileFuture = widget.riderProfileApi.fetchProfile();
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({
    required this.message,
    required this.onRetry,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String message;
  final VoidCallback onRetry;
  final String? secondaryActionLabel;
  final Future<void> Function()? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  message,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Coba lagi'),
                ),
                if (secondaryActionLabel != null &&
                    onSecondaryAction != null) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      onSecondaryAction!();
                    },
                    child: Text(secondaryActionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
