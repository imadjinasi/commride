import 'package:firebase_auth/firebase_auth.dart';

import 'auth_gateway.dart';

class FirebaseAuthGateway implements AuthGateway, PasswordResetAuthGateway {
  FirebaseAuthGateway(this._firebaseAuth);

  final FirebaseAuth _firebaseAuth;

  @override
  Stream<AuthUser?> authStateChanges() {
    return _firebaseAuth.authStateChanges().map(_mapUser);
  }

  @override
  Future<void> signIn({required String email, required String password}) {
    return _mapFailure(
      () => _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) {
    return _mapFailure(
      () => _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) {
    return _firebaseAuth.sendPasswordResetEmail(email: email);
  }

  @override
  Future<void> signOut() {
    return _firebaseAuth.signOut();
  }

  @override
  Future<String> idToken() async {
    final User? user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('No authenticated Firebase user.');
    }

    final String? token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Firebase did not provide an ID token.');
    }

    return token;
  }

  Future<void> _mapFailure(Future<Object?> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_reasonFor(error.code));
    }
  }

  static AuthFailureReason _reasonFor(String code) {
    return switch (code) {
      'email-already-in-use' => AuthFailureReason.emailAlreadyInUse,
      'invalid-email' => AuthFailureReason.invalidEmail,
      'weak-password' => AuthFailureReason.weakPassword,
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' ||
      'INVALID_LOGIN_CREDENTIALS' => AuthFailureReason.wrongCredentials,
      'too-many-requests' => AuthFailureReason.tooManyRequests,
      'network-request-failed' => AuthFailureReason.network,
      _ => AuthFailureReason.unknown,
    };
  }

  AuthUser? _mapUser(User? user) {
    if (user == null) {
      return null;
    }

    return AuthUser(id: user.uid, email: user.email);
  }
}
