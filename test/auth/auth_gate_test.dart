import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';
import 'package:hasad_erp_v2/main.dart';

void main() {
  testWidgets('missing public configuration fails safely', (tester) async {
    await tester.pumpWidget(
      const HasadApp(
        authService: UnavailableAuthService(
          'إعداد عنوان خدمة الدخول غير مكتمل.',
        ),
      ),
    );

    expect(find.text('إعداد الدخول غير مكتمل'), findsOneWidget);
    expect(find.text('تعذر تشغيل تسجيل الدخول'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets(
    'authenticates through the injected service and shows company bootstrap',
    (tester) async {
      final service = _FakeAuthService();
      await tester.pumpWidget(HasadApp(authService: service));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(
        find.byKey(const Key('login-email')),
        'user@example.com',
      );
      await tester.enterText(find.byKey(const Key('login-password')), 'secret');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(service.receivedEmail, 'user@example.com');
      expect(find.text('تعذر تحميل البيانات'), findsOneWidget);
      expect(find.textContaining('تعذر الاتصال بخدمة الشركة'), findsOneWidget);

      await tester.tap(find.text('تسجيل الخروج'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('مرحبًا بك في حصاد'), findsOneWidget);
    },
  );

  testWidgets('restores an existing session into company bootstrap', (
    tester,
  ) async {
    final service = _FakeAuthService(
      initialSession: const AuthSession(
        userId: 'synthetic-user',
        email: 'restored@example.com',
      ),
    );

    await tester.pumpWidget(HasadApp(authService: service));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('تعذر تحميل البيانات'), findsOneWidget);
  });
}

class _FakeAuthService implements AuthService {
  _FakeAuthService({AuthSession? initialSession}) : _session = initialSession;

  final _changes = StreamController<AuthSession?>.broadcast();
  AuthSession? _session;
  String? receivedEmail;

  @override
  AuthSession? get currentSession => _session;

  @override
  String? get unavailableReason => null;

  @override
  Stream<AuthSession?> get sessionChanges => _changes.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    receivedEmail = email;
    _session = AuthSession(userId: 'synthetic-user', email: email);
    _changes.add(_session);
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _changes.add(null);
  }
}
