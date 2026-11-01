import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/inventory/data/inventory_repository.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:uuid/uuid.dart';

enum MasterDataType { unit, category }

class MasterDataScreen extends StatefulWidget {
  const MasterDataScreen({
    super.key,
    required this.companyId,
    required this.type,
  });
  final String companyId;
  final MasterDataType type;
  @override
  State<MasterDataScreen> createState() => _MasterDataScreenState();
}

class _MasterDataScreenState extends State<MasterDataScreen> {
  final _repo = SupabaseInventoryRepository();
  final _search = TextEditingController();
  List<dynamic> _items = const [];
  bool _loading = true;
  String? _error;
  bool get _isUnit => widget.type == MasterDataType.unit;
  String get _title => _isUnit ? 'وحدات القياس' : 'التصنيفات';
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
      final items = _isUnit
          ? await _repo.listUnits(companyId: widget.companyId)
          : await _repo.listCategories(companyId: widget.companyId);
      if (mounted) setState(() => _items = items);
    } on InventoryFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([dynamic item]) async {
    final saved = await showDialog<dynamic>(
      context: context,
      builder: (_) => MasterDataEditorDialog(
        type: widget.type,
        companyId: widget.companyId,
        item: item,
        repo: _repo,
      ),
    );
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final items = _items
        .where(
          (item) =>
              (item.code as String).toLowerCase().contains(query) ||
              (item.nameAr as String).toLowerCase().contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HasadPageHeader(
          title: _title,
          subtitle: 'بيانات شركتك الفعلية فقط.',
          trailing: HasadPrimaryButton(
            label: _isUnit ? 'إضافة وحدة' : 'إضافة تصنيف',
            icon: Icons.add,
            onPressed: () => _edit(),
          ),
        ),
        const SizedBox(height: 24),
        HasadCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: HasadSearchField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  hint: 'بحث بالاسم أو الكود',
                ),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const HasadLoadingState()
              else if (_error != null)
                HasadErrorState(message: _error!, onRetry: _load)
              else if (items.isEmpty)
                HasadEmptyState(
                  icon: _isUnit
                      ? Icons.straighten_outlined
                      : Icons.category_outlined,
                  title: _isUnit ? 'لا توجد وحدات قياس' : 'لا توجد تصنيفات',
                  message: _isUnit
                      ? 'أضف أول وحدة قياس حقيقية لبدء إنشاء الأصناف.'
                      : 'أضف التصنيفات التي تحتاجها شركتك.',
                  action: HasadPrimaryButton(
                    label: _isUnit ? 'إضافة وحدة' : 'إضافة تصنيف',
                    icon: Icons.add,
                    onPressed: () => _edit(),
                  ),
                )
              else
                HasadDataTable(
                  columns: const [
                    DataColumn(label: Text('الكود')),
                    DataColumn(label: Text('الاسم')),
                    DataColumn(label: Text('الحالة')),
                    DataColumn(label: Text('')),
                  ],
                  rows: items
                      .map(
                        (item) => DataRow(
                          cells: [
                            DataCell(Text(item.code)),
                            DataCell(Text(item.nameAr)),
                            DataCell(
                              HasadStatusBadge(
                                label: item.isActive ? 'نشط' : 'غير نشط',
                                color: item.isActive
                                    ? HasadPalette.success
                                    : HasadPalette.muted,
                              ),
                            ),
                            DataCell(
                              IconButton(
                                onPressed: () => _edit(item),
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'تعديل',
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

class MasterDataEditorDialog extends StatefulWidget {
  const MasterDataEditorDialog({
    super.key,
    required this.type,
    required this.companyId,
    required this.item,
    required this.repo,
  });
  final MasterDataType type;
  final String companyId;
  final dynamic item;
  final InventoryRepository repo;
  @override
  State<MasterDataEditorDialog> createState() => _MasterEditorState();
}

class _MasterEditorState extends State<MasterDataEditorDialog> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _name;
  late bool _active;
  bool _base = false;
  bool _saving = false;
  String? _error;
  bool get _unit => widget.type == MasterDataType.unit;
  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.item?.code);
    _name = TextEditingController(text: widget.item?.nameAr);
    _active = widget.item?.isActive ?? true;
    _base = widget.item is UnitOfMeasure
        ? (widget.item as UnitOfMeasure).isBase
        : false;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_key.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final saved = _unit
          ? (widget.item == null
                ? await widget.repo.createUnit(
                    UnitOfMeasureDraft(
                      id: const Uuid().v4(),
                      companyId: widget.companyId,
                      code: _code.text,
                      nameAr: _name.text,
                      isBase: _base,
                      isActive: _active,
                    ),
                  )
                : await widget.repo.updateUnit(
                    UnitOfMeasureDraft(
                      id: widget.item.id,
                      companyId: widget.companyId,
                      code: _code.text,
                      nameAr: _name.text,
                      isBase: _base,
                      isActive: _active,
                    ),
                  ))
          : (widget.item == null
                ? await widget.repo.createCategory(
                    ProductCategoryDraft(
                      id: const Uuid().v4(),
                      companyId: widget.companyId,
                      code: _code.text,
                      nameAr: _name.text,
                      isActive: _active,
                    ),
                  )
                : await widget.repo.updateCategory(
                    ProductCategoryDraft(
                      id: widget.item.id,
                      companyId: widget.companyId,
                      code: _code.text,
                      nameAr: _name.text,
                      isActive: _active,
                    ),
                  ));
      if (mounted) Navigator.pop(context, saved);
    } on InventoryFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.item == null
          ? (_unit ? 'إضافة وحدة قياس' : 'إضافة تصنيف')
          : 'تعديل',
    ),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HasadFormField(
              label: 'الكود',
              controller: _code,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'أدخل الكود.' : null,
            ),
            const SizedBox(height: 12),
            HasadFormField(
              label: 'الاسم بالعربية',
              controller: _name,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'أدخل الاسم.' : null,
            ),
            if (_unit)
              SwitchListTile.adaptive(
                value: _base,
                onChanged: _saving ? null : (v) => setState(() => _base = v),
                title: const Text('وحدة أساسية'),
              ),
            SwitchListTile.adaptive(
              value: _active,
              onChanged: _saving ? null : (v) => setState(() => _active = v),
              title: const Text('نشط'),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: HasadPalette.danger)),
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
