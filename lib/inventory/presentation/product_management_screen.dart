import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/company/application/company_context_controller.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/inventory/data/inventory_repository.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:hasad_erp_v2/inventory/presentation/master_data_screen.dart';
import 'package:uuid/uuid.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key, required this.controller});
  final CompanyContextController controller;
  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  final _search = TextEditingController();
  final _repository = SupabaseInventoryRepository();
  List<UnitOfMeasure> _units = const [];
  bool _unitsLoading = true;
  String? _unitsError;
  bool? _activeFilter;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    final companyId = widget.controller.context?.companyId;
    if (companyId == null) return;
    setState(() {
      _unitsLoading = true;
      _unitsError = null;
    });
    try {
      final units = await _repository.listUnits(companyId: companyId);
      if (mounted) {
        setState(() => _units = units.where((unit) => unit.isActive).toList());
      }
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _unitsError = error.message);
    } finally {
      if (mounted) setState(() => _unitsLoading = false);
    }
  }

  Future<void> _openEditor([Product? product]) async {
    if (_unitsLoading) {
      HasadNotification.show(context, 'جارٍ تحميل وحدات القياس.');
      return;
    }
    if (_units.isEmpty) {
      HasadNotification.show(
        context,
        _unitsError ?? 'لا توجد وحدة قياس فعلية متاحة لإنشاء صنف.',
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductEditorDialog(
        product: product,
        units: _units,
        companyId: widget.controller.context!.companyId,
        repository: _repository,
      ),
    );
    if (saved == true && mounted) {
      await widget.controller.loadContext();
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final products = widget.controller.products
        .where(
          (product) =>
              (query.isEmpty ||
                  product.nameAr.toLowerCase().contains(query) ||
                  product.code.toLowerCase().contains(query)) &&
              (_activeFilter == null || product.isActive == _activeFilter),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HasadPageHeader(
          title: 'الأصناف',
          subtitle:
              'إدارة أصناف ${widget.controller.context?.companyName ?? ''} من البيانات الفعلية.',
          trailing: HasadPrimaryButton(
            label: 'إضافة صنف',
            icon: Icons.add,
            onPressed: _unitsLoading ? null : () => _openEditor(),
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
                      hint: 'ابحث بالاسم أو الكود',
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
                  if (_unitsLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (_unitsError != null)
                    TextButton.icon(
                      onPressed: _loadUnits,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة تحميل الوحدات'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (widget.controller.productsLoading)
                const HasadLoadingState(label: 'جارٍ تحميل الأصناف...')
              else if (products.isEmpty)
                const HasadEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'لا توجد أصناف للعرض',
                  message: 'لا يتم إنشاء بيانات تجريبية في حصاد.',
                )
              else
                HasadDataTable(
                  columns: const [
                    DataColumn(label: Text('الكود')),
                    DataColumn(label: Text('اسم الصنف')),
                    DataColumn(label: Text('التتبع')),
                    DataColumn(label: Text('الحالة')),
                    DataColumn(label: Text('')),
                  ],
                  rows: products
                      .map(
                        (product) => DataRow(
                          onSelectChanged: (_) => _showDetails(product),
                          cells: [
                            DataCell(Text(product.code)),
                            DataCell(Text(product.nameAr)),
                            DataCell(
                              Text(
                                product.trackInventory ? 'مخزني' : 'غير مخزني',
                              ),
                            ),
                            DataCell(
                              HasadStatusBadge(
                                label: product.isActive ? 'نشط' : 'غير نشط',
                                color: product.isActive
                                    ? HasadPalette.success
                                    : HasadPalette.muted,
                              ),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'تعديل',
                                onPressed: () => _openEditor(product),
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

  Future<void> _showDetails(Product product) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(product.nameAr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الكود: ${product.code}'),
          Text('الباركود: ${product.barcode ?? '—'}'),
          Text('التتبع: ${product.trackInventory ? 'مخزني' : 'غير مخزني'}'),
          Text('الحالة: ${product.isActive ? 'نشط' : 'غير نشط'}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _openEditor(product);
          },
          icon: const Icon(Icons.edit),
          label: const Text('تعديل'),
        ),
      ],
    ),
  );
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    this.product,
    required this.units,
    required this.companyId,
    required this.repository,
  });
  final Product? product;
  final List<UnitOfMeasure> units;
  final String companyId;
  final InventoryRepository repository;
  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _nameAr;
  late final TextEditingController _nameEn;
  late final TextEditingController _barcode;
  late String _uomId;
  late List<UnitOfMeasure> _units;
  late bool _trackInventory;
  late bool _isActive;
  bool _saving = false;
  String? _error;
  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _code = TextEditingController(text: product?.code);
    _nameAr = TextEditingController(text: product?.nameAr);
    _nameEn = TextEditingController(text: product?.nameEn);
    _barcode = TextEditingController(text: product?.barcode);
    _uomId = product?.baseUomId ?? widget.units.first.id;
    _units = List.of(widget.units);
    _trackInventory = product?.trackInventory ?? true;
    _isActive = product?.isActive ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _nameAr.dispose();
    _nameEn.dispose();
    _barcode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = ProductDraft(
      id: widget.product?.id ?? const Uuid().v4(),
      companyId: widget.companyId,
      code: _code.text,
      nameAr: _nameAr.text,
      nameEn: _nameEn.text,
      barcode: _barcode.text,
      baseUomId: _uomId,
      trackInventory: _trackInventory,
      isActive: _isActive,
    );
    try {
      if (_editing) {
        await widget.repository.updateProduct(draft);
      } else {
        await widget.repository.createProduct(draft);
      }
      if (mounted) Navigator.pop(context, true);
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'تعديل الصنف' : 'إضافة صنف جديد'),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HasadFormField(
                label: 'رمز الصنف',
                controller: _code,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل رمز الصنف.'
                    : null,
              ),
              const SizedBox(height: 12),
              HasadFormField(
                label: 'اسم الصنف بالعربية',
                controller: _nameAr,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل اسم الصنف.'
                    : null,
              ),
              const SizedBox(height: 12),
              HasadFormField(
                label: 'الاسم بالإنجليزية (اختياري)',
                controller: _nameEn,
              ),
              const SizedBox(height: 12),
              HasadFormField(label: 'الباركود (اختياري)', controller: _barcode),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _uomId,
                      decoration: const InputDecoration(
                        labelText: 'وحدة القياس الأساسية',
                      ),
                      items: _units
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit.id,
                              child: Text('${unit.nameAr} (${unit.code})'),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _uomId = value ?? _uomId),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _saving ? null : _createUnit,
                    icon: const Icon(Icons.add),
                    label: const Text('وحدة جديدة'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                value: _trackInventory,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _trackInventory = value),
                title: const Text('صنف مخزني'),
              ),
              SwitchListTile.adaptive(
                value: _isActive,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _isActive = value),
                title: const Text('صنف نشط'),
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

  Future<void> _createUnit() async {
    final created = await showDialog<dynamic>(
      context: context,
      builder: (_) => MasterDataEditorDialog(
        type: MasterDataType.unit,
        companyId: widget.companyId,
        item: null,
        repo: widget.repository,
      ),
    );
    if (created is UnitOfMeasure && mounted) {
      setState(() {
        _units = [..._units, created];
        _uomId = created.id;
      });
      HasadNotification.show(context, 'تم حفظ وحدة القياس واختيارها للصنف.');
    }
  }
}
