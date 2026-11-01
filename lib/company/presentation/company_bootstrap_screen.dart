import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/auth/application/auth_controller.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';
import 'package:hasad_erp_v2/company/application/company_context_controller.dart';
import 'package:hasad_erp_v2/company/domain/company_context.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_logo.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/shell/hasad_app_shell.dart';

class CompanyBootstrapScreen extends StatelessWidget {
  const CompanyBootstrapScreen({
    super.key,
    required this.authController,
    required this.session,
    required this.controller,
  });

  final AuthController authController;
  final AuthSession session;
  final CompanyContextController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.state) {
      CompanyContextState.loading => const _BootstrapScaffold(
        child: HasadLoadingState(label: 'جارٍ تجهيز مساحة عملك...'),
      ),
      CompanyContextState.ready => HasadAppShell(
        authController: authController,
        session: session,
        controller: controller,
      ),
      CompanyContextState.noMembership => _BootstrapScaffold(
        child: _BootstrapMessage(
          icon: Icons.person_off_outlined,
          title: 'لا توجد عضوية نشطة',
          message:
              controller.message ??
              'لا توجد عضوية نشطة لهذه الشركة للمستخدم الحالي.',
          authController: authController,
        ),
      ),
      CompanyContextState.revoked => _BootstrapScaffold(
        child: _BootstrapMessage(
          icon: Icons.block_outlined,
          title: 'تم إلغاء العضوية',
          message:
              controller.message ??
              'تم إلغاء عضويتك أو تعليقها. يرجى التواصل مع مسؤول الشركة.',
          authController: authController,
        ),
      ),
      CompanyContextState.denied => _BootstrapScaffold(
        child: _BootstrapMessage(
          icon: Icons.lock_person_outlined,
          title: 'غير مصرح بالوصول',
          message:
              controller.message ??
              'لا تملك الصلاحية المطلوبة للوصول إلى الشركة.',
          authController: authController,
        ),
      ),
      CompanyContextState.unavailable => _BootstrapScaffold(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HasadErrorState(
              message: controller.message ?? 'تعذر الاتصال ببيانات الشركة.',
              onRetry: controller.loadContext,
            ),
            OutlinedButton.icon(
              onPressed: authController.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    };
  }
}

class _BootstrapScaffold extends StatelessWidget {
  const _BootstrapScaffold({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HasadBrandLockup(),
                const SizedBox(height: 28),
                HasadCard(
                  child: SizedBox(width: double.infinity, child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _BootstrapMessage extends StatelessWidget {
  const _BootstrapMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.authController,
  });
  final IconData icon;
  final String title;
  final String message;
  final AuthController authController;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: HasadPalette.amberDark, size: 48),
      const SizedBox(height: 16),
      Text(
        title,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: HasadPalette.muted),
      ),
      const SizedBox(height: 22),
      OutlinedButton.icon(
        onPressed: authController.signOut,
        icon: const Icon(Icons.logout),
        label: const Text('تسجيل الخروج'),
      ),
    ],
  );
}
