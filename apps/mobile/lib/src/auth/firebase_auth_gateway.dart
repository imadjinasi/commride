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
  Future<void> signIn({required String email, required String password}) async {
    await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
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

  AuthUser? _mapUser(User? user) {
    if (user == null) {
      return null;
    }

    return AuthUser(id: user.uid, email: user.email);
  }
}
