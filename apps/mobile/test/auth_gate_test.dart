import 'package:commride_mobile/src/api/rider_profile_api.dart';
import 'package:commride_mobile/src/app.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/config/app_config.dart';
import 'package:commride_mobile/src/models/rider_profile.dart';
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

void main() {
  testWidgets('signed-out user sees authentication screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CommRideApp(
        config: testConfig,
        authGateway: FakeAuthGateway(null),
        riderProfileApi: FakeRiderProfileApi(null),
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
  });
}
