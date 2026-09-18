import 'package:commride_mobile/src/api/club_ride_api.dart';
import 'package:commride_mobile/src/api/route_planner_api.dart';
import 'package:commride_mobile/src/api/vehicle_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/config/app_config.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/rider_profile.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
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

class FakeClubRideApi implements ClubRideApi {
  @override
  Future<Ride> cancelRide(String rideId) {
    throw UnimplementedError();
  }

  FakeClubRideApi({
    List<ClubListItem>? clubs,
    Map<String, List<RideListItem>>? rides,
  }) : clubs = clubs ?? <ClubListItem>[],
       rides = rides ?? <String, List<RideListItem>>{};

  final List<ClubListItem> clubs;
  final Map<String, List<RideListItem>> rides;

  @override
  Future<Club> createClub(ClubInput input) {
    throw UnimplementedError();
  }

  @override
  Future<Ride> createRide(String clubId, RideInput input) {
    throw UnimplementedError();
  }

  @override
  Future<Ride> endRide(String rideId) {
    throw UnimplementedError();
  }

  @override
  Future<void> inviteClubMember({
    required String clubId,
    required String riderId,
    required ClubRole role,
  }) async {}

  @override
  Future<void> inviteRideMember({
    required String rideId,
    required String riderId,
    required RideRole role,
  }) async {}

  @override
  Future<void> joinClub(String clubId) async {}

  @override
  Future<void> joinRide(String rideId) async {}

  @override
  Future<List<ClubListItem>> listClubs() async {
    return List<ClubListItem>.unmodifiable(clubs);
  }

  @override
  Future<List<RideListItem>> listRides(String clubId) async {
    return List<RideListItem>.unmodifiable(
      rides[clubId] ?? const <RideListItem>[],
    );
  }

  @override
  Future<Ride> publishRide(String rideId) {
    throw UnimplementedError();
  }

  @override
  Future<Ride> startRide(String rideId) {
    throw UnimplementedError();
  }
}

class FakeRoutePlannerApi implements RoutePlannerApi {
  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    return const <PlaceSuggestion>[];
  }

  @override
  Future<List<RouteOption>> computeRoutes({
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required List<PlanningStop> stops,
    required RouteTravelMode travelMode,
    required bool computeAlternatives,
  }) async {
    return const <RouteOption>[];
  }

  @override
  Future<SavedRoutePlan?> fetchRoutePlan(String rideId) async => null;

  @override
  Future<ResolvedPlace> resolvePlace({
    required String reference,
    required String sessionToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<SavedRoutePlan> saveRoutePlan({
    required String rideId,
    required ResolvedPlace origin,
    required ResolvedPlace destination,
    required RouteOption route,
    required RouteTravelMode travelMode,
    required List<PlanningStop> stops,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<AlongRoutePlace>> searchAlongRoute({
    required String textQuery,
    required RouteOption route,
    required RouteTravelMode travelMode,
  }) async {
    return const <AlongRoutePlace>[];
  }
}

Widget buildShell({
  VehicleApi? vehicleApi,
  ClubRideApi? clubRideApi,
  RoutePlannerApi? routePlannerApi,
}) {
  return MaterialApp(
    theme: CommRideTheme.light(),
    home: AppShell(
      config: testConfig,
      riderProfile: testRider,
      vehicleApi: vehicleApi ?? FakeVehicleApi(),
      clubRideApi: clubRideApi ?? FakeClubRideApi(),
      routePlannerApi: routePlannerApi ?? FakeRoutePlannerApi(),
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

  testWidgets('Ride tab loads persistent Club/Ride state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildShell());

    await tester.tap(find.byIcon(Icons.route_outlined));
    await tester.pumpAndSettle();

    expect(find.textContaining('Gabung atau buat Club dulu'), findsOneWidget);
  });

  testWidgets('Clubs tab exposes Club creation', (WidgetTester tester) async {
    await tester.pumpWidget(buildShell());

    await tester.tap(find.byIcon(Icons.groups_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Buat Club'), findsOneWidget);
    expect(find.text('Belum ada Club'), findsOneWidget);
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
