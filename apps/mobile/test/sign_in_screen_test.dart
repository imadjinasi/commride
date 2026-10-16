import 'package:commride_mobile/src/auth/auth_gateway.dart';
import 'package:commride_mobile/src/screens/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ResettableFakeAuthGateway
    implements AuthGateway, PasswordResetAuthGateway {
  String? resetEmail;
  AuthFailure? createAccountFailure;
  AuthFailure? signInFailure;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream<AuthUser?>.empty();

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    if (createAccountFailure != null) {
      throw createAccountFailure!;
    }
  }

  @override
  Future<String> idToken() async => 'test-token';

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    resetEmail = email;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (signInFailure != null) {
      throw signInFailure!;
    }
  }

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

    await tester.enterText(find.byType(TextField).first, 'rider@example.com');
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

  testWidgets('existing email on Buat akun points the Rider back to Masuk', (
    WidgetTester tester,
  ) async {
    final ResettableFakeAuthGateway gateway = ResettableFakeAuthGateway()
      ..createAccountFailure = const AuthFailure(
        AuthFailureReason.emailAlreadyInUse,
      );

    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(authGateway: gateway)),
    );

    await tester.tap(find.text('Belum punya akun? Buat akun'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'rider@example.com');
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Buat akun'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Email ini sudah punya akun CommRide'),
      findsOneWidget,
    );
    // Back on the sign-in form with the same email, ready for Masuk or reset.
    expect(find.widgetWithText(FilledButton, 'Masuk'), findsOneWidget);
    expect(find.text('Lupa kata sandi?'), findsOneWidget);
    expect(find.text('rider@example.com'), findsOneWidget);
  });

  testWidgets('wrong password suggests password reset', (
    WidgetTester tester,
  ) async {
    final ResettableFakeAuthGateway gateway = ResettableFakeAuthGateway()
      ..signInFailure = const AuthFailure(AuthFailureReason.wrongCredentials);

    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(authGateway: gateway)),
    );

    await tester.enterText(find.byType(TextField).first, 'rider@example.com');
    await tester.enterText(find.byType(TextField).last, 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Masuk'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Email atau kata sandi salah'), findsOneWidget);
  });
}
