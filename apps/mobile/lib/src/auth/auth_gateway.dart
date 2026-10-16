class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

/// Why an email/password action failed, independent of the auth provider.
enum AuthFailureReason {
  emailAlreadyInUse,
  invalidEmail,
  weakPassword,
  wrongCredentials,
  tooManyRequests,
  network,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.reason);

  final AuthFailureReason reason;

  @override
  String toString() => 'AuthFailure(${reason.name})';
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
