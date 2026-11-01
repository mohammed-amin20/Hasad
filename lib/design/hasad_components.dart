import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';

class HasadCard extends StatelessWidget {
  const HasadCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class HasadPageHeader extends StatelessWidget {
  const HasadPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: HasadPalette.muted),
            ),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class HasadMetricCard extends StatelessWidget {
  const HasadMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.note,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? note;

  @override
  Widget build(BuildContext context) => HasadCard(
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: HasadPalette.amberDark),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: HasadPalette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (note case final note?)
                Text(
                  note,
                  style: const TextStyle(
                    color: HasadPalette.muted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class HasadStatusBadge extends StatelessWidget {
  const HasadStatusBadge({
    super.key,
    required this.label,
    this.color = HasadPalette.warning,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

class HasadEmptyState extends StatelessWidget {
  const HasadEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: HasadPalette.muted),
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
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

class HasadLoadingState extends StatelessWidget {
  const HasadLoadingState({super.key, this.label = 'جارٍ التحميل...'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(label),
      ],
    ),
  );
}

class HasadErrorState extends StatelessWidget {
  const HasadErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => HasadEmptyState(
    icon: Icons.cloud_off_outlined,
    title: 'تعذر تحميل البيانات',
    message: message,
    action: HasadPrimaryButton(
      label: 'إعادة المحاولة',
      icon: Icons.refresh,
      onPressed: onRetry,
    ),
  );
}

class HasadSearchField extends StatelessWidget {
  const HasadSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'بحث',
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      hintText: hint,
    ),
  );
}

class HasadFormField extends StatelessWidget {
  const HasadFormField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.enabled = true,
  });
  final String label;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool enabled;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    enabled: enabled,
    decoration: InputDecoration(labelText: label),
  );
}

class HasadPrimaryButton extends StatelessWidget {
  const HasadPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}

class HasadDataTable extends StatelessWidget {
  const HasadDataTable({super.key, required this.columns, required this.rows});
  final List<DataColumn> columns;
  final List<DataRow> rows;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(columns: columns, rows: rows),
  );
}

abstract final class HasadDialog {
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
  }) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}

abstract final class HasadNotification {
  static void show(BuildContext context, String message) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
}
