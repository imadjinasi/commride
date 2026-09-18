import 'package:commride_mobile/src/api/club_ride_api.dart';
import 'package:commride_mobile/src/api/rider_profile_api.dart';
import 'package:commride_mobile/src/api/route_planner_api.dart';
import 'package:commride_mobile/src/api/vehicle_api.dart';
import 'package:commride_mobile/src/app.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/config/app_config.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/models/rider_profile.dart';
import 'package:commride_mobile/src/models/route_planner.dart';
import 'package:commride_mobile/src/models/vehicle_profile.dart';
import 'package:flutter_test/flutter_test.dart';

const AppConfig testConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: null,
);

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway(this.user);

  final AuthUser? user;

  @override
  Stream<AuthUser?> authStateChanges() => Stream<AuthUser?>.value(user);

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

class FakeRiderProfileApi implements RiderProfileApi {
  FakeRiderProfileApi(this.profile);

  RiderProfile? profile;

  @override
  Future<RiderProfile?> fetchProfile() async => profile;

  @override
  Future<RiderProfile> saveProfile(RiderProfileInput input) async {
    final RiderProfile saved = RiderProfile(
      id: 'rider-1',
      displayName: input.displayName,
      callsign: input.callsign,
      homeArea: input.homeArea,
    );
    profile = saved;
    return saved;
  }
}

class FakeVehicleApi implements VehicleApi {
  @override
  Future<VehicleProfile> createVehicle(VehicleProfileInput input) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteVehicle(String vehicleId) async {}

  @override
  Future<List<VehicleProfile>> listVehicles() async {
    return const <VehicleProfile>[];
  }

  @override
  Future<VehicleProfile> updateVehicle(
    String vehicleId,
    VehicleProfileInput input,
  ) {
    throw UnimplementedError();
  }
}

class FakeClubRideApi implements ClubRideApi {
  @override
  Future<Ride> cancelRide(String rideId) {
    throw UnimplementedError();
  }

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
    return const <ClubListItem>[];
  }

  @override
  Future<List<RideListItem>> listRides(String clubId) async {
    return const <RideListItem>[];
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

void main() {
  testWidgets('signed-out user sees authentication screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CommRideApp(
        config: testConfig,
        authGateway: FakeAuthGateway(null),
        riderProfileApi: FakeRiderProfileApi(null),
        vehicleApi: FakeVehicleApi(),
        clubRideApi: FakeClubRideApi(),
        routePlannerApi: FakeRoutePlannerApi(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Masuk'), findsWidgets);
    expect(find.textContaining('Izin lokasi tidak diminta'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('signed-in user without profile enters Rider onboarding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CommRideApp(
        config: testConfig,
        authGateway: FakeAuthGateway(
          const AuthUser(id: 'auth-user-1', email: 'rider@example.com'),
        ),
        riderProfileApi: FakeRiderProfileApi(null),
        vehicleApi: FakeVehicleApi(),
        clubRideApi: FakeClubRideApi(),
        routePlannerApi: FakeRoutePlannerApi(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profil Rider'), findsOneWidget);
    expect(find.text('Kenalkan diri Anda'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('signed-in Rider with profile enters application shell', (
    WidgetTester tester,
  ) async {
    const RiderProfile profile = RiderProfile(
      id: 'rider-1',
      displayName: 'Rider One',
      callsign: 'Lead',
      homeArea: 'Cirebon',
    );

    await tester.pumpWidget(
      CommRideApp(
        config: testConfig,
        authGateway: FakeAuthGateway(
          const AuthUser(id: 'auth-user-1', email: 'rider@example.com'),
        ),
        riderProfileApi: FakeRiderProfileApi(profile),
        vehicleApi: FakeVehicleApi(),
        clubRideApi: FakeClubRideApi(),
        routePlannerApi: FakeRoutePlannerApi(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
  });
}
