import 'package:commride_mobile/src/api/vehicle_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/config/app_config.dart';
import 'package:commride_mobile/src/models/rider_profile.dart';
import 'package:commride_mobile/src/models/vehicle_profile.dart';
import 'package:commride_mobile/src/navigation/app_shell.dart';
import 'package:commride_mobile/src/theme/commride_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const AppConfig testConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: null,
);

const RiderProfile testRider = RiderProfile(
  id: 'rider-1',
  displayName: 'Rider One',
  callsign: 'Lead',
  homeArea: 'Cirebon',
);

class FakeAuthGateway implements AuthGateway {
  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {}

  @override
  Future<String> idToken() async => 'test-token';

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

class FakeVehicleApi implements VehicleApi {
  FakeVehicleApi([List<VehicleProfile>? vehicles])
      : vehicles = vehicles ?? <VehicleProfile>[];

  final List<VehicleProfile> vehicles;

  @override
  Future<VehicleProfile> createVehicle(VehicleProfileInput input) async {
    final VehicleProfile vehicle = VehicleProfile(
      id: 'vehicle-new',
      kind: input.kind,
      make: input.make,
      model: input.model,
      nickname: input.nickname,
      fuelType: input.fuelType,
      safeRangeKm: input.safeRangeKm,
    );
    vehicles.add(vehicle);
    return vehicle;
  }

  @override
  Future<void> deleteVehicle(String vehicleId) async {
    vehicles.removeWhere((VehicleProfile item) => item.id == vehicleId);
  }

  @override
  Future<List<VehicleProfile>> listVehicles() async {
    return List<VehicleProfile>.unmodifiable(vehicles);
  }

  @override
  Future<VehicleProfile> updateVehicle(
    String vehicleId,
    VehicleProfileInput input,
  ) async {
    final int index = vehicles.indexWhere(
      (VehicleProfile item) => item.id == vehicleId,
    );
    final VehicleProfile vehicle = VehicleProfile(
      id: vehicleId,
      kind: input.kind,
      make: input.make,
      model: input.model,
      nickname: input.nickname,
      fuelType: input.fuelType,
      safeRangeKm: input.safeRangeKm,
    );
    vehicles[index] = vehicle;
    return vehicle;
  }
}

Widget buildShell({VehicleApi? vehicleApi}) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: AppShell(
      config: testConfig,
      riderProfile: testRider,
      vehicleApi: vehicleApi ?? FakeVehicleApi(),
      authGateway: FakeAuthGateway(),
    ),
  );
}

void main() {
  testWidgets('renders the documented primary navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildShell());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets('can switch to Ride without requesting permissions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildShell());

    await tester.tap(find.byIcon(Icons.route_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Plan, join, and review Rides here. Route planning, Add Stop, '
        'Search Along Route, and the Active Ride command center come next.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Profile shows Rider Vehicle planning metadata', (
    WidgetTester tester,
  ) async {
    final VehicleApi api = FakeVehicleApi(<VehicleProfile>[
      const VehicleProfile(
        id: 'vehicle-1',
        kind: VehicleKind.motorcycle,
        make: 'Honda',
        model: 'CB150R',
        nickname: 'Black',
        fuelType: 'Pertamax',
        safeRangeKm: 220,
      ),
    ]);

    await tester.pumpWidget(buildShell(vehicleApi: api));
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Rider One'), findsOneWidget);
    expect(find.text('Black · Honda · CB150R'), findsOneWidget);
    expect(find.textContaining('Safe range 220 km'), findsOneWidget);
  });
}
