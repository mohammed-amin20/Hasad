import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/inventory/data/inventory_repository.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:uuid/uuid.dart';

class WarehouseManagementScreen extends StatefulWidget {
  const WarehouseManagementScreen({super.key, required this.companyId});
  final String companyId;
  @override
  State<WarehouseManagementScreen> createState() =>
      _WarehouseManagementScreenState();
}

class _WarehouseManagementScreenState extends State<WarehouseManagementScreen> {
  final _repository = SupabaseInventoryRepository();
  final _search = TextEditingController();
  List<Warehouse> _warehouses = const [];
  bool _loading = true;
  String? _error;
  bool? _activeFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final warehouses = await _repository.listWarehouses(
        companyId: widget.companyId,
      );
      if (mounted) setState(() => _warehouses = warehouses);
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Warehouse? warehouse]) async {
    final saved = await showDialog<Warehouse>(
      context: context,
      builder: (_) => WarehouseEditorDialog(
        warehouse: warehouse,
        companyId: widget.companyId,
        repository: _repository,
      ),
    );
    if (saved == null || !mounted) return;
    HasadNotification.show(
      context,
      warehouse == null
          ? 'تم حفظ المستودع في قاعدة البيانات.'
          : 'تم تحديث بيانات المستودع.',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final warehouses = _warehouses
        .where(
          (warehouse) =>
              (query.isEmpty ||
                  warehouse.code.toLowerCase().contains(query) ||
                  warehouse.nameAr.toLowerCase().contains(query)) &&
              (_activeFilter == null || warehouse.isActive == _activeFilter),
        )
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HasadPageHeader(
          title: 'المستودعات',
          subtitle: 'إدارة مستودعات الشركة الحالية من البيانات الفعلية.',
          trailing: HasadPrimaryButton(
            label: 'إضافة مستودع',
            icon: Icons.add,
            onPressed: _loading ? null : () => _edit(),
          ),
        ),
        const SizedBox(height: 24),
        HasadCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: HasadSearchField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      hint: 'بحث بالاسم أو الكود',
                    ),
                  ),
                  DropdownButton<bool?>(
                    value: _activeFilter,
                    hint: const Text('كل الحالات'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('كل الحالات')),
                      DropdownMenuItem(value: true, child: Text('نشط')),
                      DropdownMenuItem(value: false, child: Text('غير نشط')),
                    ],
                    onChanged: (value) => setState(() => _activeFilter = value),
                  ),
                  IconButton(
                    tooltip: 'تحديث',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading)
                const HasadLoadingState(label: 'جارٍ تحميل المستودعات...')
              else if (_error != null)
                HasadErrorState(message: _error!, onRetry: _load)
              else if (warehouses.isEmpty)
                HasadEmptyState(
                  icon: Icons.warehouse_outlined,
                  title: _warehouses.isEmpty
                      ? 'لا توجد مستودعات'
                      : 'لا توجد نتائج مطابقة',
                  message: _warehouses.isEmpty
                      ? 'أضف أول مستودع حقيقي لبدء تسجيل أرصدة المخزون.'
                      : 'جرّب تغيير كلمة البحث أو عامل تصفية الحالة.',
                  action: _warehouses.isEmpty
                      ? HasadPrimaryButton(
                          label: 'إضافة مستودع',
                          icon: Icons.add,
                          onPressed: () => _edit(),
                        )
                      : TextButton(
                          onPressed: () {
                            _search.clear();
                            setState(() => _activeFilter = null);
                          },
                          child: const Text('مسح عوامل التصفية'),
                        ),
                )
              else
                HasadDataTable(
                  columns: const [
                    DataColumn(label: Text('الكود')),
                    DataColumn(label: Text('اسم المستودع')),
                    DataColumn(label: Text('الحالة')),
                    DataColumn(label: Text('')),
                  ],
                  rows: warehouses
                      .map(
                        (warehouse) => DataRow(
                          cells: [
                            DataCell(Text(warehouse.code)),
                            DataCell(Text(warehouse.nameAr)),
                            DataCell(
                              HasadStatusBadge(
                                label: warehouse.isActive ? 'نشط' : 'غير نشط',
                                color: warehouse.isActive
                                    ? HasadPalette.success
                                    : HasadPalette.muted,
                              ),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'تعديل',
                                onPressed: () => _edit(warehouse),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class WarehouseEditorDialog extends StatefulWidget {
  const WarehouseEditorDialog({
    super.key,
    this.warehouse,
    required this.companyId,
    required this.repository,
  });
  final Warehouse? warehouse;
  final String companyId;
  final InventoryRepository repository;
  @override
  State<WarehouseEditorDialog> createState() => _WarehouseEditorDialogState();
}

class _WarehouseEditorDialogState extends State<WarehouseEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _nameAr;
  late bool _isActive;
  bool _saving = false;
  String? _error;
  bool get _editing => widget.warehouse != null;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.warehouse?.code);
    _nameAr = TextEditingController(text: widget.warehouse?.nameAr);
    _isActive = widget.warehouse?.isActive ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _nameAr.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = WarehouseDraft(
      id: widget.warehouse?.id ?? const Uuid().v4(),
      companyId: widget.companyId,
      code: _code.text,
      nameAr: _nameAr.text,
      isActive: _isActive,
    );
    try {
      final saved = _editing
          ? await widget.repository.updateWarehouse(draft)
          : await widget.repository.createWarehouse(draft);
      if (mounted) Navigator.pop(context, saved);
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'تعديل المستودع' : 'إضافة مستودع'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HasadFormField(
              label: 'كود المستودع',
              controller: _code,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'أدخل كود المستودع.'
                  : null,
            ),
            const SizedBox(height: 12),
            HasadFormField(
              label: 'اسم المستودع بالعربية',
              controller: _nameAr,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'أدخل اسم المستودع.'
                  : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _isActive,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _isActive = value),
              title: const Text('مستودع نشط'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: HasadPalette.danger),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      HasadPrimaryButton(
        label: _saving ? 'جارٍ الحفظ...' : 'حفظ',
        icon: Icons.save_outlined,
        onPressed: _saving ? null : _save,
      ),
    ],
  );
}
