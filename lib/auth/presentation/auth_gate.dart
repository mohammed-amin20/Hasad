import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/auth/application/auth_controller.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';
import 'package:hasad_erp_v2/company/application/company_context_controller.dart';
import 'package:hasad_erp_v2/company/data/company_context_repository.dart';
import 'package:hasad_erp_v2/company/presentation/company_bootstrap_screen.dart';
import 'package:hasad_erp_v2/design/hasad_logo.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.authService});

  final AuthService authService;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AuthController(widget.authService)..restoreSession();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isRestoring) {
      return const _StatusScaffold(
        title: 'جارٍ استعادة الجلسة',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_controller.unavailableReason case final reason?) {
      return _StatusScaffold(
        title: 'إعداد الدخول غير مكتمل',
        body: _MessageCard(
          icon: Icons.settings_outlined,
          title: 'تعذر تشغيل تسجيل الدخول',
          message: reason,
        ),
      );
    }
    if (_controller.session case final session?) {
      return _CompanyBootstrapGate(
        key: ValueKey(session.userId),
        authController: _controller,
        session: session,
      );
    }
    return _LoginScreen(controller: _controller);
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.controller});

  final AuthController controller;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  bool _showPassword = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await widget.controller.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthFailure catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StatusScaffold(
      title: 'تسجيل الدخول',
      body: _MessageCard(
        title: 'مرحبًا بك في حصاد',
        message: 'سجّل الدخول للوصول إلى مساحة شركتك المصرح بها.',
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const HasadLogo(size: 86),
              const SizedBox(height: 24),
              TextFormField(
                key: const Key('login-email'),
                controller: _emailController,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل البريد الإلكتروني.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('login-password'),
                controller: _passwordController,
                autofillHints: const [AutofillHints.password],
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'كلمة المرور',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? 'إخفاء كلمة المرور'
                        : 'إظهار كلمة المرور',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'أدخل كلمة المرور.' : null,
              ),
              if (_errorMessage case final error?) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  key: const Key('login-submit'),
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('تسجيل الدخول'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyBootstrapGate extends StatefulWidget {
  const _CompanyBootstrapGate({
    super.key,
    required this.authController,
    required this.session,
  });

  final AuthController authController;
  final AuthSession session;

  @override
  State<_CompanyBootstrapGate> createState() => _CompanyBootstrapGateState();
}

class _CompanyBootstrapGateState extends State<_CompanyBootstrapGate> {
  late final CompanyContextController _controller;

  @override
  void initState() {
    super.initState();
    final repository = CompanyContextRepository(CompanyContextApiGateway());
    _controller = CompanyContextController(repository)..loadContext();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompanyBootstrapScreen(
      authController: widget.authController,
      session: widget.session,
      controller: _controller,
    );
  }
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(padding: const EdgeInsets.all(24), child: body),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    this.icon,
    required this.title,
    required this.message,
    this.child,
  });

  final IconData? icon;
  final String title;
  final String message;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 32, color: theme.colorScheme.primary),
                const SizedBox(height: 20),
              ],
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(message, style: theme.textTheme.bodyLarge),
              ?child,
            ],
          ),
        ),
      ),
    );
  }
}
