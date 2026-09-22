class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

abstract interface class AuthGateway {
  Stream<AuthUser?> authStateChanges();

  Future<void> signIn({required String email, required String password});

  Future<void> createAccount({required String email, required String password});

  Future<void> signOut();

  Future<String> idToken();
}


abstract interface class PasswordResetAuthGateway {
  Future<void> sendPasswordResetEmail({required String email});
}
