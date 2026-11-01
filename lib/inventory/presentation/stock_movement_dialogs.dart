import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/inventory/data/inventory_repository.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:hasad_erp_v2/inventory/presentation/inventory_display.dart';
import 'package:hasad_erp_v2/inventory/presentation/stock_movement_validation.dart';
import 'package:uuid/uuid.dart';

class StockReceiptDialog extends StatefulWidget {
  const StockReceiptDialog({
    super.key,
    required this.companyId,
    required this.repository,
    required this.warehouses,
    required this.products,
  });

  final String companyId;
  final InventoryRepository repository;
  final List<Warehouse> warehouses;
  final List<Product> products;

  @override
  State<StockReceiptDialog> createState() => _StockReceiptDialogState();
}

class _StockReceiptDialogState extends State<StockReceiptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();
  final _movementId = const Uuid().v4();
  final _submissionGuard = StockMovementSubmissionGuard();
  String? _warehouseId;
  String? _productId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.warehouses.firstOrNull?.id;
    _productId = widget.products.firstOrNull?.id;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _review() => _submissionGuard.run(_submit);

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final qty = parseInventoryNumber(_qtyController.text)!;
    final unitCost = parseInventoryNumber(_costController.text)!;
    final warehouse = _warehouse();
    final product = _product();
    if (!stockSelectionMatchesCompany(
      companyId: widget.companyId,
      productCompanyId: product.companyId,
      warehouseCompanyId: warehouse.companyId,
    )) {
      setState(() => _error = 'الصنف أو المستودع لا يتبع الشركة الحالية.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ReviewDialog(
        title: 'مراجعة حركة الاستلام',
        rows: [
          _ReviewRow('المستودع', warehouse.label),
          _ReviewRow('الصنف', product.label),
          _ReviewRow('الكمية', formatInventoryQty(qty)),
          _ReviewRow('تكلفة الوحدة', formatInventoryMoney(unitCost)),
          _ReviewRow('قيمة الحركة', formatInventoryMoney(qty * unitCost)),
        ],
        note:
            'بعد التأكيد ستُسجَّل الحركة وتُحدَّث كمية المخزون والتكلفة '
            'المرجحة ذريًا على الخادم.',
        confirmLabel: 'تأكيد الترحيل',
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.postStockReceipt(
        StockReceiptDraft(
          id: _movementId,
          companyId: widget.companyId,
          warehouseId: warehouse.id,
          productId: product.id,
          qty: qty,
          unitCost: unitCost,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Warehouse _warehouse() =>
      widget.warehouses.firstWhere((warehouse) => warehouse.id == _warehouseId);

  Product _product() =>
      widget.products.firstWhere((product) => product.id == _productId);

  @override
  Widget build(BuildContext context) => _MovementDialogFrame(
    title: 'استلام مخزون',
    subtitle: 'تسجيل كمية واردة إلى مستودع الشركة.',
    saving: _saving,
    error: _error,
    onCancel: () => Navigator.pop(context, false),
    onConfirm: _review,
    confirmLabel: 'مراجعة الاستلام',
    confirmIcon: Icons.fact_check_outlined,
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WarehouseField(
            warehouses: widget.warehouses,
            value: _warehouseId,
            label: 'المستودع',
            onChanged: (value) => setState(() => _warehouseId = value),
          ),
          const SizedBox(height: 14),
          _ProductField(
            products: widget.products,
            value: _productId,
            onChanged: (value) => setState(() => _productId = value),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _qtyController,
                  enabled: !_saving,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'الكمية المستلمة',
                    hintText: 'مثال: 25',
                  ),
                  validator: validateStockQuantityInput,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextFormField(
                  controller: _costController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'تكلفة الوحدة',
                    hintText: '0.00',
                  ),
                  validator: validateStockCostInput,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _InfoNote(
            icon: Icons.lock_outline_rounded,
            message:
                'لن يُرسل أي تعديل مباشر على الأرصدة. تُنشأ الحركة ويُحدَّث '
                'الرصيد في معاملة واحدة على الخادم.',
          ),
        ],
      ),
    ),
  );
}

class StockIssueDialog extends StatefulWidget {
  const StockIssueDialog({
    super.key,
    required this.companyId,
    required this.repository,
    required this.warehouses,
    required this.products,
    required this.balances,
  });

  final String companyId;
  final InventoryRepository repository;
  final List<Warehouse> warehouses;
  final List<Product> products;
  final List<StockBalance> balances;

  @override
  State<StockIssueDialog> createState() => _StockIssueDialogState();
}

class _StockIssueDialogState extends State<StockIssueDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _movementId = const Uuid().v4();
  final _submissionGuard = StockMovementSubmissionGuard();
  String? _warehouseId;
  String? _productId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _warehouseId = widget.warehouses.firstOrNull?.id;
    _productId = widget.products.firstOrNull?.id;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  double get _available => _availableQty(
    widget.balances,
    companyId: widget.companyId,
    productId: _productId,
    warehouseId: _warehouseId,
  );

  Future<void> _review() => _submissionGuard.run(_submit);

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final qty = parseInventoryNumber(_qtyController.text)!;
    final available = _available;
    if (qty > available) {
      setState(() => _error = 'الكمية تتجاوز المتاح المسجل حاليًا.');
      return;
    }
    final warehouse = _warehouse();
    final product = _product();
    if (!stockSelectionMatchesCompany(
      companyId: widget.companyId,
      productCompanyId: product.companyId,
      warehouseCompanyId: warehouse.companyId,
    )) {
      setState(() => _error = 'الصنف أو المستودع لا يتبع الشركة الحالية.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ReviewDialog(
        title: 'مراجعة حركة الصرف',
        rows: [
          _ReviewRow('المستودع', warehouse.label),
          _ReviewRow('الصنف', product.label),
          _ReviewRow('الكمية المصروفة', formatInventoryQty(qty)),
          _ReviewRow('المتاح المسجل', formatInventoryQty(available)),
          _ReviewRow('المتاح بعد الترحيل', formatInventoryQty(available - qty)),
        ],
        note:
            'يتحقق الخادم من الرصيد لحظة الترحيل ويرفض الصرف إذا أصبح '
            'غير كافٍ. لا يتم السماح برصيد سالب.',
        confirmLabel: 'تأكيد الترحيل',
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.postStockIssue(
        StockIssueDraft(
          id: _movementId,
          companyId: widget.companyId,
          warehouseId: warehouse.id,
          productId: product.id,
          qty: qty,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Warehouse _warehouse() =>
      widget.warehouses.firstWhere((warehouse) => warehouse.id == _warehouseId);

  Product _product() =>
      widget.products.firstWhere((product) => product.id == _productId);

  @override
  Widget build(BuildContext context) => _MovementDialogFrame(
    title: 'صرف مخزون',
    subtitle: 'إخراج كمية من مستودع مع التحقق من الرصيد المتاح.',
    saving: _saving,
    error: _error,
    onCancel: () => Navigator.pop(context, false),
    onConfirm: _review,
    confirmLabel: 'مراجعة الصرف',
    confirmIcon: Icons.fact_check_outlined,
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WarehouseField(
            warehouses: widget.warehouses,
            value: _warehouseId,
            label: 'المستودع',
            onChanged: (value) => setState(() {
              _warehouseId = value;
              _error = null;
            }),
          ),
          const SizedBox(height: 14),
          _ProductField(
            products: widget.products,
            value: _productId,
            onChanged: (value) => setState(() {
              _productId = value;
              _error = null;
            }),
          ),
          const SizedBox(height: 14),
          _AvailableCard(
            label: 'الكمية المتاحة حاليًا',
            qty: _available,
            warehouseId: _warehouseId,
            productId: _productId,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _qtyController,
            enabled: !_saving,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'الكمية المصروفة',
              hintText: 'مثال: 5',
            ),
            validator: (value) =>
                validateStockAvailableQuantity(value, _available),
          ),
          const SizedBox(height: 14),
          const _InfoNote(
            icon: Icons.verified_user_outlined,
            message:
                'الرصيد المعروض تقديري حتى لحظة الترحيل. يمنع الخادم الصرف '
                'الزائد أو الرصيد السالب حتى مع العمليات المتزامنة.',
          ),
        ],
      ),
    ),
  );
}

class StockTransferDialog extends StatefulWidget {
  const StockTransferDialog({
    super.key,
    required this.companyId,
    required this.repository,
    required this.warehouses,
    required this.products,
    required this.balances,
  });

  final String companyId;
  final InventoryRepository repository;
  final List<Warehouse> warehouses;
  final List<Product> products;
  final List<StockBalance> balances;

  @override
  State<StockTransferDialog> createState() => _StockTransferDialogState();
}

class _StockTransferDialogState extends State<StockTransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _outMovementId = const Uuid().v4();
  final _inMovementId = const Uuid().v4();
  final _submissionGuard = StockMovementSubmissionGuard();
  String? _sourceWarehouseId;
  String? _destinationWarehouseId;
  String? _productId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sourceWarehouseId = widget.warehouses.firstOrNull?.id;
    _destinationWarehouseId = widget.warehouses.length > 1
        ? widget.warehouses[1].id
        : widget.warehouses.firstOrNull?.id;
    _productId = widget.products.firstOrNull?.id;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  double get _available => _availableQty(
    widget.balances,
    companyId: widget.companyId,
    productId: _productId,
    warehouseId: _sourceWarehouseId,
  );

  Future<void> _review() => _submissionGuard.run(_submit);

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final qty = parseInventoryNumber(_qtyController.text)!;
    final available = _available;
    if (_sourceWarehouseId == _destinationWarehouseId) {
      setState(() => _error = 'اختر مستودعًا مصدرًا ومستودعًا وجهة مختلفين.');
      return;
    }
    if (qty > available) {
      setState(() => _error = 'الكمية تتجاوز المتاح في المستودع المصدر.');
      return;
    }
    final source = _sourceWarehouse();
    final destination = _destinationWarehouse();
    final product = _product();
    if (!stockSelectionMatchesCompany(
          companyId: widget.companyId,
          productCompanyId: product.companyId,
          warehouseCompanyId: source.companyId,
        ) ||
        destination.companyId != widget.companyId) {
      setState(() => _error = 'الصنف أو المستودع لا يتبع الشركة الحالية.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _ReviewDialog(
        title: 'مراجعة التحويل بين المستودعات',
        rows: [
          _ReviewRow('من مستودع', source.label),
          _ReviewRow('إلى مستودع', destination.label),
          _ReviewRow('الصنف', product.label),
          _ReviewRow('الكمية المحوّلة', formatInventoryQty(qty)),
          _ReviewRow('المتاح في المصدر', formatInventoryQty(available)),
        ],
        note:
            'سيُنشأ صادر ووارد بنفس التكلفة والقيمة داخل معاملة واحدة. '
            'إذا لم يكن رصيد المصدر كافيًا فلن يُسجَّل أي طرف من التحويل.',
        confirmLabel: 'تأكيد التحويل',
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.postStockTransfer(
        StockTransferDraft(
          outMovementId: _outMovementId,
          inMovementId: _inMovementId,
          companyId: widget.companyId,
          sourceWarehouseId: source.id,
          destinationWarehouseId: destination.id,
          productId: product.id,
          qty: qty,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Warehouse _sourceWarehouse() => widget.warehouses.firstWhere(
    (warehouse) => warehouse.id == _sourceWarehouseId,
  );

  Warehouse _destinationWarehouse() => widget.warehouses.firstWhere(
    (warehouse) => warehouse.id == _destinationWarehouseId,
  );

  Product _product() =>
      widget.products.firstWhere((product) => product.id == _productId);

  @override
  Widget build(BuildContext context) => _MovementDialogFrame(
    title: 'تحويل بين المستودعات',
    subtitle: 'نقل كمية بين مستودعين مع الحفاظ على قيمة المخزون.',
    saving: _saving,
    error: _error,
    onCancel: () => Navigator.pop(context, false),
    onConfirm: _review,
    confirmLabel: 'مراجعة التحويل',
    confirmIcon: Icons.fact_check_outlined,
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _WarehouseField(
                  warehouses: widget.warehouses,
                  value: _sourceWarehouseId,
                  label: 'من مستودع',
                  onChanged: (value) => setState(() {
                    _sourceWarehouseId = value;
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _WarehouseField(
                  warehouses: widget.warehouses,
                  value: _destinationWarehouseId,
                  label: 'إلى مستودع',
                  onChanged: (value) => setState(() {
                    _destinationWarehouseId = value;
                    _error = null;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProductField(
            products: widget.products,
            value: _productId,
            onChanged: (value) => setState(() {
              _productId = value;
              _error = null;
            }),
          ),
          const SizedBox(height: 14),
          _AvailableCard(
            label: 'المتاح في المستودع المصدر',
            qty: _available,
            warehouseId: _sourceWarehouseId,
            productId: _productId,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _qtyController,
            enabled: !_saving,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'الكمية المحوّلة',
              hintText: 'مثال: 10',
            ),
            validator: (value) =>
                validateStockAvailableQuantity(value, _available),
          ),
          const SizedBox(height: 14),
          const _InfoNote(
            icon: Icons.swap_horiz_rounded,
            message:
                'تُرحَّل حركتان متقابلتان بنفس التكلفة دفعة واحدة، ويُحدَّث '
                'رصيد المستودعين دون أي كتابة مباشرة من التطبيق.',
          ),
        ],
      ),
    ),
  );
}

class _MovementDialogFrame extends StatelessWidget {
  const _MovementDialogFrame({
    required this.title,
    required this.subtitle,
    required this.saving,
    required this.error,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    required this.confirmIcon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool saving;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final IconData confirmIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: HasadPalette.muted,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            child,
            if (error != null) ...[
              const SizedBox(height: 14),
              _InlineError(message: error!),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : onCancel,
        child: const Text('إلغاء'),
      ),
      FilledButton.icon(
        onPressed: saving ? null : onConfirm,
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(confirmIcon),
        label: Text(saving ? 'جارٍ الترحيل...' : confirmLabel),
      ),
    ],
  );
}

class _WarehouseField extends StatelessWidget {
  const _WarehouseField({
    required this.warehouses,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final List<Warehouse> warehouses;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: warehouses
        .map(
          (warehouse) => DropdownMenuItem(
            value: warehouse.id,
            child: Text('${warehouse.nameAr} (${warehouse.code})'),
          ),
        )
        .toList(growable: false),
    onChanged: onChanged,
    validator: (value) => value == null ? 'اختر المستودع.' : null,
  );
}

class _ProductField extends StatelessWidget {
  const _ProductField({
    required this.products,
    required this.value,
    required this.onChanged,
  });

  final List<Product> products;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: const InputDecoration(labelText: 'الصنف'),
    items: products
        .map(
          (product) => DropdownMenuItem(
            value: product.id,
            child: Text('${product.nameAr} (${product.code})'),
          ),
        )
        .toList(growable: false),
    onChanged: onChanged,
    validator: (value) => value == null ? 'اختر الصنف.' : null,
  );
}

class _AvailableCard extends StatelessWidget {
  const _AvailableCard({
    required this.label,
    required this.qty,
    required this.warehouseId,
    required this.productId,
  });

  final String label;
  final double qty;
  final String? warehouseId;
  final String? productId;

  @override
  Widget build(BuildContext context) {
    if (warehouseId == null || productId == null) {
      return const _InfoNote(
        icon: Icons.info_outline_rounded,
        message: 'اختر المستودع والصنف لعرض الرصيد المتاح.',
      );
    }
    final empty = qty <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: empty
            ? HasadPalette.danger.withValues(alpha: .06)
            : HasadPalette.success.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: empty
              ? HasadPalette.danger.withValues(alpha: .25)
              : HasadPalette.success.withValues(alpha: .22),
        ),
      ),
      child: Row(
        children: [
          Icon(
            empty ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
            color: empty ? HasadPalette.danger : HasadPalette.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: HasadPalette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            formatInventoryQty(qty),
            style: TextStyle(
              color: empty ? HasadPalette.danger : HasadPalette.success,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: HasadPalette.canvas,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: HasadPalette.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: HasadPalette.muted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: HasadPalette.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: HasadPalette.danger.withValues(alpha: .06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: HasadPalette.danger.withValues(alpha: .25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: HasadPalette.danger,
          size: 19,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: HasadPalette.danger,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ReviewDialog extends StatelessWidget {
  const _ReviewDialog({
    required this.title,
    required this.rows,
    required this.note,
    required this.confirmLabel,
  });

  final String title;
  final List<_ReviewRow> rows;
  final String note;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: HasadPalette.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HasadPalette.border),
            ),
            child: Column(
              children: [
                for (var index = 0; index < rows.length; index++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            rows[index].label,
                            style: const TextStyle(color: HasadPalette.muted),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            rows[index].value,
                            textAlign: TextAlign.left,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            note,
            style: const TextStyle(
              color: HasadPalette.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('رجوع'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.pop(context, true),
        icon: const Icon(Icons.lock_open_rounded),
        label: Text(confirmLabel),
      ),
    ],
  );
}

class _ReviewRow {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;
}

double _availableQty(
  List<StockBalance> balances, {
  required String companyId,
  required String? productId,
  required String? warehouseId,
}) {
  if (productId == null || warehouseId == null) return 0;
  for (final balance in balances) {
    if (balance.companyId == companyId &&
        balance.productId == productId &&
        balance.warehouseId == warehouseId) {
      return balance.qty;
    }
  }
  return 0;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension WarehouseLabel on Warehouse {
  String get label => '$nameAr ($code)';
}

extension ProductLabel on Product {
  String get label => '$nameAr ($code)';
}
