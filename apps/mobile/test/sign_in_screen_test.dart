import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/screens/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ResettableFakeAuthGateway
    implements AuthGateway, PasswordResetAuthGateway {
  String? resetEmail;

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
  Future<void> sendPasswordResetEmail({required String email}) async {
    resetEmail = email;
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('forgot password sends reset email for entered address', (
    WidgetTester tester,
  ) async {
    final ResettableFakeAuthGateway gateway = ResettableFakeAuthGateway();

    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(authGateway: gateway)),
    );

    await tester.enterText(
      find.byType(TextField).first,
      'rider@example.com',
    );
    await tester.tap(find.text('Lupa kata sandi?'));
    await tester.pumpAndSettle();

    expect(gateway.resetEmail, 'rider@example.com');
    expect(
      find.text('Jika email terdaftar, tautan reset kata sandi akan dikirim.'),
      findsOneWidget,
    );
  });

  testWidgets('forgot password requires an email first', (
    WidgetTester tester,
  ) async {
    final ResettableFakeAuthGateway gateway = ResettableFakeAuthGateway();

    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(authGateway: gateway)),
    );

    await tester.tap(find.text('Lupa kata sandi?'));
    await tester.pump();

    expect(gateway.resetEmail, isNull);
    expect(
      find.text('Masukkan email terlebih dahulu untuk reset kata sandi.'),
      findsOneWidget,
    );
  });
}
