import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/api/http_checkpoint_api.dart';
import 'src/api/http_club_ride_api.dart';
import 'src/api/http_notification_api.dart';
import 'src/api/http_push_token_api.dart';
import 'src/api/http_rider_profile_api.dart';
import 'src/api/http_ride_briefing_api.dart';
import 'src/api/http_ride_comms_api.dart';
import 'src/api/http_ride_recap_api.dart';
import 'src/api/http_ride_sos_api.dart';
import 'src/api/http_route_planner_api.dart';
import 'src/api/http_vehicle_api.dart';
import 'src/app.dart';
import 'src/auth/firebase_auth_gateway.dart';
import 'src/api/push_token_api.dart';
import 'src/push/firebase_ride_push_messaging.dart';
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
    final RidePushPlatform? pushPlatform = switch (defaultTargetPlatform) {
      TargetPlatform.android => RidePushPlatform.android,
      TargetPlatform.iOS => RidePushPlatform.ios,
      _ => null,
    };
    final HttpPushTokenApi pushTokenApi = HttpPushTokenApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final HttpNotificationApi notificationApi = HttpNotificationApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final FirebaseRidePushMessaging pushMessaging = FirebaseRidePushMessaging(
      FirebaseMessaging.instance,
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
    final HttpCheckpointApi checkpointApi = HttpCheckpointApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final HttpRoutePlannerApi routePlannerApi = HttpRoutePlannerApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final HttpRideBriefingApi rideBriefingApi = HttpRideBriefingApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final HttpRideCommsApi rideCommsApi = HttpRideCommsApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final HttpRideSosApi rideSosApi = HttpRideSosApi(
      apiBaseUrl: apiBaseUrl,
      authGateway: authGateway,
    );
    final HttpRideRecapApi rideRecapApi = HttpRideRecapApi(
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
        checkpointApi: checkpointApi,
        routePlannerApi: routePlannerApi,
        rideBriefingApi: rideBriefingApi,
        rideCommsApi: rideCommsApi,
        rideSosApi: rideSosApi,
        rideRecapApi: rideRecapApi,
        notificationApi: notificationApi,
        pushTokenApi: pushPlatform == null ? null : pushTokenApi,
        pushMessaging: pushPlatform == null ? null : pushMessaging,
        pushPlatform: pushPlatform,
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
