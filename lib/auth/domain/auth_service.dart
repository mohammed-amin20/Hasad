class AuthSession {
  const AuthSession({required this.userId, this.email});

  final String userId;
  final String? email;
}

enum AuthFailureCategory {
  invalidCredentials,
  emailUnconfirmed,
  configuration,
  network,
  rateLimited,
  unexpected,
}

class AuthFailure implements Exception {
  const AuthFailure(
    this.message, {
    this.category = AuthFailureCategory.unexpected,
  });

  final String message;
  final AuthFailureCategory category;
}

abstract class AuthService {
  AuthSession? get currentSession;

  String? get unavailableReason;

  Stream<AuthSession?> get sessionChanges;

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}

class UnavailableAuthService implements AuthService {
  const UnavailableAuthService(this.unavailableReason);

  @override
  final String? unavailableReason;

  @override
  AuthSession? get currentSession => null;

  @override
  Stream<AuthSession?> get sessionChanges => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) {
    throw AuthFailure(
      unavailableReason ?? 'خدمة الدخول غير متاحة.',
      category: AuthFailureCategory.configuration,
    );
  }

  @override
  Future<void> signOut() async {}
}
