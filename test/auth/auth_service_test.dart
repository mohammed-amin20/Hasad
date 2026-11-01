import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/auth/data/auth_service_factory.dart';
import 'package:hasad_erp_v2/auth/domain/auth_configuration.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('sign in trims email and exposes the restored session', () async {
    final gateway = _FakeGateway();
    final service = SupabaseAuthService(gateway);

    await service.signIn(email: ' user@example.com ', password: 'secret');

    expect(gateway.email, 'user@example.com');
    expect(service.currentSession?.email, 'user@example.com');
  });

  test('maps gateway failures to a safe authentication error', () async {
    final service = SupabaseAuthService(_FakeGateway(shouldFail: true));

    expect(
      () => service.signIn(email: 'user@example.com', password: 'secret'),
      throwsA(isA<AuthFailure>()),
    );
  });

  test(
    'maps Supabase invalid credentials without exposing provider details',
    () async {
      final service = SupabaseAuthService(
        _FakeGateway(
          error: const AuthException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
      );

      await expectLater(
        service.signIn(email: 'user@example.com', password: 'secret'),
        throwsA(
          isA<AuthFailure>()
              .having(
                (failure) => failure.category,
                'category',
                AuthFailureCategory.invalidCredentials,
              )
              .having(
                (failure) => failure.message,
                'message',
                'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
              ),
        ),
      );
    },
  );

  test(
    'maps unconfirmed email and rate limiting to actionable Arabic guidance',
    () async {
      final unconfirmed = SupabaseAuthService(
        _FakeGateway(
          error: const AuthException(
            'Email not confirmed',
            statusCode: '400',
            code: 'email_not_confirmed',
          ),
        ),
      );
      final rateLimited = SupabaseAuthService(
        _FakeGateway(
          error: const AuthException(
            'Too many requests',
            statusCode: '429',
            code: 'over_request_rate_limit',
          ),
        ),
      );

      await expectLater(
        unconfirmed.signIn(email: 'user@example.com', password: 'secret'),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.category,
            'category',
            AuthFailureCategory.emailUnconfirmed,
          ),
        ),
      );
      await expectLater(
        rateLimited.signIn(email: 'user@example.com', password: 'secret'),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.category,
            'category',
            AuthFailureCategory.rateLimited,
          ),
        ),
      );
    },
  );

  test(
    'maps retryable Supabase connection failures without exposing details',
    () async {
      final service = SupabaseAuthService(
        _FakeGateway(error: AuthRetryableFetchException()),
      );

      await expectLater(
        service.signIn(email: 'user@example.com', password: 'secret'),
        throwsA(
          isA<AuthFailure>().having(
            (failure) => failure.category,
            'category',
            AuthFailureCategory.network,
          ),
        ),
      );
    },
  );

  test('rejects incomplete public configuration before SDK initialization', () {
    const configuration = AuthConfiguration(projectUrl: '', publishableKey: '');

    expect(configuration.validationMessage, isNotNull);
  });
}

class _FakeGateway implements SupabaseAuthGateway {
  _FakeGateway({this.shouldFail = false, this.error});

  final bool shouldFail;
  final Object? error;
  final _changes = StreamController<AuthSession?>.broadcast();
  AuthSession? _session;
  String? email;

  @override
  AuthSession? get currentSession => _session;

  @override
  Stream<AuthSession?> get sessionChanges => _changes.stream;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (error case final error?) {
      throw error;
    }
    if (shouldFail) {
      throw StateError('gateway failure');
    }
    this.email = email;
    _session = AuthSession(userId: 'synthetic-user', email: email);
    _changes.add(_session);
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _changes.add(null);
  }
}
