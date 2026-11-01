import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hasad_erp_v2/auth/domain/auth_configuration.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';

abstract class SupabaseAuthGateway {
  AuthSession? get currentSession;

  Stream<AuthSession?> get sessionChanges;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

class AuthServiceFactory {
  static Future<AuthService> create(AuthConfiguration configuration) async {
    final configurationError = configuration.validationMessage;
    if (configurationError != null) {
      return UnavailableAuthService(configurationError);
    }

    try {
      await Supabase.initialize(
        url: configuration.projectUrl,
        publishableKey: configuration.publishableKey,
      );
      return SupabaseAuthService(
        _SupabaseAuthGateway(Supabase.instance.client.auth),
      );
    } on Object {
      return const UnavailableAuthService('تعذر تهيئة خدمة الدخول بأمان.');
    }
  }
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._gateway);

  final SupabaseAuthGateway _gateway;

  @override
  AuthSession? get currentSession => _gateway.currentSession;

  @override
  String? get unavailableReason => null;

  @override
  Stream<AuthSession?> get sessionChanges => _gateway.sessionChanges;

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _gateway.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthFailure {
      rethrow;
    } on AuthRetryableFetchException {
      throw const AuthFailure(
        'تعذر الاتصال بخدمة تسجيل الدخول. تحقق من الإنترنت ثم أعد المحاولة.',
        category: AuthFailureCategory.network,
      );
    } on AuthUnknownException catch (error) {
      if (error.statusCode == null) {
        throw const AuthFailure(
          'تعذر الاتصال بخدمة تسجيل الدخول. تحقق من الإنترنت ثم أعد المحاولة.',
          category: AuthFailureCategory.network,
        );
      }
      throw const AuthFailure(
        'حدثت استجابة غير متوقعة من خدمة تسجيل الدخول. أعد المحاولة لاحقًا.',
        category: AuthFailureCategory.unexpected,
      );
    } on AuthException catch (error) {
      throw _mapAuthException(error);
    } on Object {
      throw const AuthFailure(
        'حدث خطأ غير متوقع أثناء تسجيل الدخول. أعد المحاولة لاحقًا.',
        category: AuthFailureCategory.unexpected,
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _gateway.signOut();
    } on Object {
      throw const AuthFailure('تعذر تسجيل الخروج الآن. أعد المحاولة.');
    }
  }

  AuthFailure _mapAuthException(AuthException error) {
    switch (error.code) {
      case 'email_not_confirmed':
        return const AuthFailure(
          'لم يتم تأكيد البريد الإلكتروني بعد. افتح رسالة التأكيد ثم أعد تسجيل الدخول.',
          category: AuthFailureCategory.emailUnconfirmed,
        );
      case 'invalid_credentials':
      case 'user_not_found':
        return const AuthFailure(
          'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
          category: AuthFailureCategory.invalidCredentials,
        );
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
      case 'over_sms_send_rate_limit':
        return const AuthFailure(
          'تم تجاوز الحد المؤقت للمحاولات. انتظر قليلًا ثم أعد المحاولة.',
          category: AuthFailureCategory.rateLimited,
        );
      default:
        if (error.statusCode == '429') {
          return const AuthFailure(
            'تم تجاوز الحد المؤقت للمحاولات. انتظر قليلًا ثم أعد المحاولة.',
            category: AuthFailureCategory.rateLimited,
          );
        }
        if (error.statusCode == '401') {
          return const AuthFailure(
            'تعذر التحقق من إعداد خدمة تسجيل الدخول. تواصل مع مسؤول النظام.',
            category: AuthFailureCategory.configuration,
          );
        }
        return const AuthFailure(
          'تعذر تسجيل الدخول بسبب استجابة غير متوقعة من الخدمة. أعد المحاولة لاحقًا.',
          category: AuthFailureCategory.unexpected,
        );
    }
  }
}

class _SupabaseAuthGateway implements SupabaseAuthGateway {
  _SupabaseAuthGateway(this._auth);

  final GoTrueClient _auth;

  @override
  AuthSession? get currentSession => _toSession(_auth.currentSession);

  @override
  Stream<AuthSession?> get sessionChanges =>
      _auth.onAuthStateChange.map((state) => _toSession(state.session));

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.session == null) {
      throw const AuthFailure('لم تكتمل جلسة الدخول. تحقق من حالة حسابك.');
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  AuthSession? _toSession(Session? session) {
    if (session == null) {
      return null;
    }
    return AuthSession(userId: session.user.id, email: session.user.email);
  }
}
