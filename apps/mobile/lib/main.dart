import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'src/api/http_club_ride_api.dart';
import 'src/api/http_rider_profile_api.dart';
import 'src/api/http_vehicle_api.dart';
import 'src/app.dart';
import 'src/auth/firebase_auth_gateway.dart';
import 'src/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppConfig config = AppConfig.fromEnvironment();
  final Uri? apiBaseUrl = config.apiBaseUrl;

  if (apiBaseUrl == null) {
    runApp(
      CommRideSetupApp(
        config: config,
        message:
            'COMMRIDE_API_BASE_URL belum diatur. '
            'Tambahkan endpoint API non-secret saat menjalankan aplikasi.',
      ),
    );
    return;
  }

  try {
    await Firebase.initializeApp();

    final FirebaseAuthGateway authGateway = FirebaseAuthGateway(
      FirebaseAuth.instance,
    );
    final HttpRiderProfileApi riderProfileApi = HttpRiderProfileApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final HttpVehicleApi vehicleApi = HttpVehicleApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final HttpClubRideApi clubRideApi = HttpClubRideApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );

    runApp(
      CommRideApp(
        config: config,
        authGateway: authGateway,
        riderProfileApi: riderProfileApi,
        vehicleApi: vehicleApi,
        clubRideApi: clubRideApi,
      ),
    );
  } catch (_) {
    runApp(
      CommRideSetupApp(
        config: config,
        message:
            'Firebase belum dikonfigurasi untuk platform ini. '
            'Tambahkan konfigurasi Firebase resmi untuk build lokal '
            'atau environment deployment.',
      ),
    );
  }
}
