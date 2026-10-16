import 'package:commride_mobile/src/api/account_api.dart';
import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/models/club_ride.dart';
import 'package:commride_mobile/src/screens/profile/delete_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDeletionAuthGateway
    implements AuthGateway, AccountDeletionAuthGateway {
  String? reauthenticatedWith;
  bool deleted = false;
  bool signedOut = false;
  AuthFailure? reauthFailure;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {}

  @override
  Future<String> idToken() async => 'token';

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async => signedOut = true;

  @override
  Future<void> reauthenticate({required String password}) async {
    if (reauthFailure != null) {
      throw reauthFailure!;
    }
    reauthenticatedWith = password;
  }

  @override
  Future<void> deleteSignedInAccount() async => deleted = true;
}

class FakeAccountApi implements AccountDeletionApi, ClubOwnershipApi {
  FakeAccountApi({required this.ownsClubWithMembers});

  bool ownsClubWithMembers;
  int deleteCalls = 0;
  String? transferredTo;

  @override
  Future<AccountDeletionPreview> previewDeletion() async {
    return AccountDeletionPreview(
      clubsRequiringTransfer: ownsClubWithMembers
          ? const <DeletionClub>[DeletionClub(clubId: 'club-x', name: 'Club X')]
          : const <DeletionClub>[],
      clubsToClose: const <DeletionClub>[
        DeletionClub(clubId: 'club-y', name: 'Club Y'),
      ],
      activeRides: const <DeletionRide>[],
    );
  }

  @override
  Future<void> deleteAccount() async => deleteCalls += 1;

  @override
  Future<List<ClubMember>> listMembers(String clubId) async {
    return const <ClubMember>[
      ClubMember(
        riderId: 'rider-a',
        displayName: 'Rider A',
        callsign: null,
        role: ClubRole.owner,
      ),
      ClubMember(
        riderId: 'rider-b',
        displayName: 'Rider B',
        callsign: 'Bravo',
        role: ClubRole.member,
      ),
    ];
  }

  @override
  Future<void> transferOwnership({
    required String clubId,
    required String riderId,
  }) async {
    transferredTo = riderId;
    ownsClubWithMembers = false;
  }
}

Widget _screen(FakeAccountApi api, FakeDeletionAuthGateway auth) {
  return MaterialApp(
    home: DeleteAccountScreen(
      riderId: 'rider-a',
      accountDeletionApi: api,
      clubOwnershipApi: api,
      authGateway: auth,
    ),
  );
}

Future<void> _confirmAndDelete(WidgetTester tester, String password) async {
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(CheckboxListTile));
  await tester.enterText(find.byType(TextField), password);
  await tester.ensureVisible(find.text('Hapus akun permanen'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Hapus akun permanen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner must transfer the Club before deletion is offered', (
    WidgetTester tester,
  ) async {
    final FakeAccountApi api = FakeAccountApi(ownsClubWithMembers: true);
    await tester.pumpWidget(_screen(api, FakeDeletionAuthGateway()));
    await tester.pumpAndSettle();

    expect(find.text('Serahkan kepemilikan dulu'), findsOneWidget);
    expect(find.text('Hapus akun permanen'), findsNothing);
    expect(find.textContaining('Club Y'), findsOneWidget);

    await tester.tap(find.text('Serahkan'));
    await tester.pumpAndSettle();
    // The current owner is not offered as the new owner.
    expect(find.text('Rider A'), findsNothing);
    await tester.tap(find.text('Rider B'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Serahkan'));
    await tester.pumpAndSettle();

    expect(api.transferredTo, 'rider-b');
    expect(find.text('Serahkan kepemilikan dulu'), findsNothing);
    expect(find.text('Hapus akun permanen'), findsOneWidget);
  });

  testWidgets('confirmed password deletes server data then the login', (
    WidgetTester tester,
  ) async {
    final FakeAccountApi api = FakeAccountApi(ownsClubWithMembers: false);
    final FakeDeletionAuthGateway auth = FakeDeletionAuthGateway();
    await tester.pumpWidget(_screen(api, auth));
    await tester.pumpAndSettle();

    await _confirmAndDelete(tester, 'secret123');

    expect(auth.reauthenticatedWith, 'secret123');
    expect(api.deleteCalls, 1);
    expect(auth.deleted, isTrue);
  });

  testWidgets('wrong password deletes nothing', (WidgetTester tester) async {
    final FakeAccountApi api = FakeAccountApi(ownsClubWithMembers: false);
    final FakeDeletionAuthGateway auth = FakeDeletionAuthGateway()
      ..reauthFailure = const AuthFailure(AuthFailureReason.wrongCredentials);
    await tester.pumpWidget(_screen(api, auth));
    await tester.pumpAndSettle();

    await _confirmAndDelete(tester, 'wrong');

    expect(find.text('Kata sandi salah.'), findsOneWidget);
    expect(api.deleteCalls, 0);
    expect(auth.deleted, isFalse);
  });
}
