class AuthConfiguration {
  const AuthConfiguration({
    required this.projectUrl,
    required this.publishableKey,
  });

  final String projectUrl;
  final String publishableKey;

  factory AuthConfiguration.fromEnvironment() {
    return const AuthConfiguration(
      projectUrl: String.fromEnvironment('SUPABASE_URL'),
      publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
  }

  String? get validationMessage {
    final uri = Uri.tryParse(projectUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'إعداد عنوان خدمة الدخول غير مكتمل.';
    }
    if (publishableKey.trim().isEmpty) {
      return 'إعداد مفتاح الوصول العام غير مكتمل.';
    }
    return null;
  }
}
