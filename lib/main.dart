import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/auth/data/auth_service_factory.dart';
import 'package:hasad_erp_v2/auth/domain/auth_configuration.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';
import 'package:hasad_erp_v2/auth/presentation/auth_gate.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authService = await AuthServiceFactory.create(
    AuthConfiguration.fromEnvironment(),
  );
  runApp(HasadApp(authService: authService));
}

class HasadApp extends StatelessWidget {
  const HasadApp({super.key, required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حصاد ERP',
      debugShowCheckedModeBanner: false,
      theme: HasadTheme.light(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: AuthGate(authService: authService),
    );
  }
}
