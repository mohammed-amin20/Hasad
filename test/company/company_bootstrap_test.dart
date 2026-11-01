import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/auth/application/auth_controller.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';
import 'package:hasad_erp_v2/company/application/company_context_controller.dart';
import 'package:hasad_erp_v2/company/domain/company_context.dart';
import 'package:hasad_erp_v2/company/domain/company_context_service.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/company/presentation/company_bootstrap_screen.dart';

void main() {
  testWidgets('shows no membership state with sign out', (tester) async {
    final authController = AuthController(_FakeAuthService());
    final service = _FakeService(state: _FakeState.noMembership);
    final controller = CompanyContextController(service);
    await controller.loadContext();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: CompanyBootstrapScreen(
          authController: authController,
          session: const AuthSession(userId: 'u1', email: 'u1@example.com'),
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('لا توجد عضوية نشطة'), findsWidgets);
    expect(find.text('تسجيل الخروج'), findsWidgets);
  });

  testWidgets('shows ready company context and empty products list', (
    tester,
  ) async {
    final authController = AuthController(_FakeAuthService());
    final service = _FakeService(
      state: _FakeState.ready,
      context: const CompanyContext(
        companyId: 'c1',
        companyName: 'شركة حصاد',
        isOwner: true,
        roleCode: null,
      ),
      products: const [],
    );
    final controller = CompanyContextController(service);
    await controller.loadContext();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: CompanyBootstrapScreen(
          authController: authController,
          session: const AuthSession(userId: 'u1', email: 'u1@example.com'),
          controller: controller,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('مرحباً بك في شركة حصاد'), findsOneWidget);
    expect(find.text('لوحة التحكم'), findsWidgets);
    expect(find.text('الأصناف'), findsWidgets);
    expect(find.text('لا يوجد نشاط معروض'), findsOneWidget);
  });
}

enum _FakeState { ready, noMembership, denied, revoked }

class _FakeService implements CompanyContextService {
  _FakeService({required this.state, this.context, this.products = const []});

  final _FakeState state;
  final CompanyContext? context;
  final List<Product> products;

  @override
  Future<CompanyContext> getCurrentContext() async {
    if (state == _FakeState.ready && context != null) {
      return context!;
    }
    if (state == _FakeState.noMembership) {
      throw const CompanyContextFailure(
        'لا توجد عضوية نشطة',
        code: 'NO_MEMBERSHIP',
      );
    }
    if (state == _FakeState.denied) {
      throw const CompanyContextFailure('غير مصرح', code: 'DENIED');
    }
    if (state == _FakeState.revoked) {
      throw const CompanyContextFailure('ملغاة', code: 'REVOKED');
    }
    throw const CompanyContextFailure('غير مهيأ', code: 'UNAPPROVED_BACKEND');
  }

  @override
  Future<List<Product>> getProducts({required String companyId}) async {
    return products;
  }
}

class _FakeAuthService implements AuthService {
  final _changes = StreamController<AuthSession?>.broadcast();

  @override
  AuthSession? get currentSession => null;

  @override
  String? get unavailableReason => null;

  @override
  Stream<AuthSession?> get sessionChanges => _changes.stream;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
