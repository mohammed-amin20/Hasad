import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/customers/data/customer_repository.dart';
import 'package:hasad_erp_v2/customers/domain/customer.dart';
import 'package:hasad_erp_v2/customers/domain/customer_validation.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:uuid/uuid.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.companyId, this.repository});

  final String companyId;
  final CustomerRepository? repository;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late final CustomerRepository _repository =
      widget.repository ?? SupabaseCustomerRepository();
  final _search = TextEditingController();
  List<Customer> _customers = const [];
  bool _loading = true;
  String? _error;
  bool? _activeFilter = true;

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
      final rows = await _repository.listCustomers(companyId: widget.companyId);
      if (rows.any((row) => row.companyId != widget.companyId)) {
        throw const CustomerFailure(
          'وصلت بيانات خارج سياق الشركة الحالي، لذلك لم يتم عرضها.',
          code: 'CROSS_COMPANY_RESPONSE',
        );
      }
      if (mounted) setState(() => _customers = rows);
    } on CustomerFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'تعذر تحميل العملاء. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Customer? customer]) async {
    final saved = await showDialog<Customer>(
      context: context,
      builder: (_) => CustomerEditorDialog(
        companyId: widget.companyId,
        customer: customer,
        repository: _repository,
      ),
    );
    if (saved == null || !mounted) return;
    HasadNotification.show(
      context,
      customer == null ? 'تم حفظ العميل.' : 'تم تحديث بيانات العميل.',
    );
    await _load();
  }

  void _showDetails(Customer customer) => showDialog<void>(
    context: context,
    builder: (_) => CustomerDetailsDialog(customer: customer),
  );

  @override
  Widget build(BuildContext context) {
    final needle = _search.text.trim().toLowerCase();
    final visible = _customers
        .where((customer) {
          final searchable = [
            customer.code,
            customer.nameAr,
            customer.nameEn ?? '',
            customer.phone ?? '',
            customer.email ?? '',
            customer.taxId ?? '',
          ].join(' ').toLowerCase();
          return (needle.isEmpty || searchable.contains(needle)) &&
              (_activeFilter == null || customer.isActive == _activeFilter);
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HasadPageHeader(
          title: 'العملاء',
          subtitle: 'إدارة بيانات العملاء المرتبطة بالشركة الحالية.',
          trailing: HasadPrimaryButton(
            label: 'إضافة عميل',
            icon: Icons.person_add_alt_1_outlined,
            onPressed: _loading ? null : () => _edit(),
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: 260,
              child: HasadMetricCard(
                label: 'إجمالي العملاء',
                value: '${_customers.length}',
                icon: Icons.groups_outlined,
              ),
            ),
            SizedBox(
              width: 260,
              child: HasadMetricCard(
                label: 'العملاء النشطون',
                value: '${_customers.where((row) => row.isActive).length}',
                icon: Icons.verified_user_outlined,
                note: 'من بيانات الشركة الحالية',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
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
                      hint: 'بحث بالرمز أو الاسم أو الهاتف',
                    ),
                  ),
                  DropdownButton<bool?>(
                    value: _activeFilter,
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
                const HasadLoadingState(label: 'جارٍ تحميل العملاء...')
              else if (_error != null)
                HasadErrorState(message: _error!, onRetry: _load)
              else if (_customers.isEmpty)
                HasadEmptyState(
                  icon: Icons.people_outline,
                  title: 'لا يوجد عملاء بعد',
                  message: 'أضف بيانات عميل حقيقية لبدء استخدامها في المبيعات.',
                  action: HasadPrimaryButton(
                    label: 'إضافة عميل',
                    icon: Icons.add,
                    onPressed: () => _edit(),
                  ),
                )
              else if (visible.isEmpty)
                const HasadEmptyState(
                  icon: Icons.search_off_outlined,
                  title: 'لا توجد نتائج',
                  message: 'غيّر كلمات البحث أو مرشح الحالة.',
                )
              else
                HasadDataTable(
                  columns: const [
                    DataColumn(label: Text('الرمز')),
                    DataColumn(label: Text('اسم العميل')),
                    DataColumn(label: Text('التصنيف')),
                    DataColumn(label: Text('الهاتف')),
                    DataColumn(label: Text('الحالة')),
                    DataColumn(label: Text('الإجراءات')),
                  ],
                  rows: visible.map(_customerRow).toList(growable: false),
                ),
            ],
          ),
        ),
      ],
    );
  }

  DataRow _customerRow(Customer customer) => DataRow(
    cells: [
      DataCell(Text(customer.code)),
      DataCell(
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Text(customer.nameAr, overflow: TextOverflow.ellipsis),
        ),
      ),
      DataCell(Text(customer.partyType == 'company' ? 'شركة' : 'فرد')),
      DataCell(Text(customer.phone ?? '—')),
      DataCell(
        HasadStatusBadge(
          label: customer.isActive ? 'نشط' : 'غير نشط',
          color: customer.isActive ? HasadPalette.success : HasadPalette.muted,
        ),
      ),
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'التفاصيل',
              onPressed: () => _showDetails(customer),
              icon: const Icon(Icons.visibility_outlined),
            ),
            IconButton(
              tooltip: 'تعديل',
              onPressed: () => _edit(customer),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    ],
  );
}

class CustomerDetailsDialog extends StatelessWidget {
  const CustomerDetailsDialog({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(customer.nameAr),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailRow(label: 'الرمز', value: customer.code),
            _DetailRow(
              label: 'الاسم بالإنجليزية',
              value: customer.nameEn ?? '—',
            ),
            _DetailRow(
              label: 'النوع',
              value: customer.partyType == 'company' ? 'شركة' : 'فرد',
            ),
            _DetailRow(label: 'الرقم الضريبي', value: customer.taxId ?? '—'),
            _DetailRow(label: 'الهاتف', value: customer.phone ?? '—'),
            _DetailRow(
              label: 'البريد الإلكتروني',
              value: customer.email ?? '—',
            ),
            _DetailRow(label: 'العنوان', value: customer.address ?? '—'),
            _DetailRow(
              label: 'مدة السداد',
              value: customer.paymentTermsDays == null
                  ? '—'
                  : '${customer.paymentTermsDays} يوم',
            ),
            _DetailRow(
              label: 'التصنيف',
              value: customer.isSupplier ? 'عميل ومورد' : 'عميل',
            ),
            _DetailRow(
              label: 'الحالة',
              value: customer.isActive ? 'نشط' : 'غير نشط',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إغلاق'),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: const TextStyle(color: HasadPalette.muted)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class CustomerEditorDialog extends StatefulWidget {
  const CustomerEditorDialog({
    super.key,
    required this.companyId,
    required this.repository,
    this.customer,
  });

  final String companyId;
  final CustomerRepository repository;
  final Customer? customer;

  @override
  State<CustomerEditorDialog> createState() => _CustomerEditorDialogState();
}

class _CustomerEditorDialogState extends State<CustomerEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _nameAr;
  late final TextEditingController _nameEn;
  late final TextEditingController _taxId;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _paymentTerms;
  late String _partyType;
  late bool _isSupplier;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _code = TextEditingController(text: customer?.code ?? '');
    _nameAr = TextEditingController(text: customer?.nameAr ?? '');
    _nameEn = TextEditingController(text: customer?.nameEn ?? '');
    _taxId = TextEditingController(text: customer?.taxId ?? '');
    _phone = TextEditingController(text: customer?.phone ?? '');
    _email = TextEditingController(text: customer?.email ?? '');
    _address = TextEditingController(text: customer?.address ?? '');
    _paymentTerms = TextEditingController(
      text: customer?.paymentTermsDays?.toString() ?? '',
    );
    _partyType = customer?.partyType ?? 'individual';
    _isSupplier = customer?.isSupplier ?? false;
    _isActive = customer?.isActive ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _nameAr.dispose();
    _nameEn.dispose();
    _taxId.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _paymentTerms.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final termsText = _paymentTerms.text.trim();
    final draft = CustomerDraft(
      id: widget.customer?.id ?? const Uuid().v4(),
      companyId: widget.companyId,
      code: _code.text,
      nameAr: _nameAr.text,
      nameEn: _nameEn.text,
      partyType: _partyType,
      isSupplier: _isSupplier,
      taxId: _taxId.text,
      phone: _phone.text,
      email: _email.text,
      address: _address.text,
      paymentTermsDays: termsText.isEmpty ? null : int.tryParse(termsText),
      isActive: _isActive,
    );
    try {
      final customer = _editing
          ? await widget.repository.updateCustomer(draft)
          : await widget.repository.createCustomer(draft);
      if (customer.companyId != widget.companyId || !customer.isCustomer) {
        throw const CustomerFailure(
          'استجابة العميل لا تطابق الشركة الحالية.',
          code: 'CROSS_COMPANY_RESPONSE',
        );
      }
      if (mounted) Navigator.pop(context, customer);
    } on CustomerFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } on Object {
      if (mounted) setState(() => _error = 'تعذر حفظ العميل. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_editing ? 'تعديل بيانات العميل' : 'إضافة عميل'),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HasadFormField(
                label: 'رمز العميل',
                controller: _code,
                enabled: !_saving,
                validator: validateCustomerCode,
              ),
              const SizedBox(height: 12),
              HasadFormField(
                label: 'اسم العميل بالعربية',
                controller: _nameAr,
                enabled: !_saving,
                validator: validateCustomerName,
              ),
              const SizedBox(height: 12),
              HasadFormField(
                label: 'الاسم بالإنجليزية (اختياري)',
                controller: _nameEn,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _partyType,
                decoration: const InputDecoration(labelText: 'نوع العميل'),
                items: const [
                  DropdownMenuItem(value: 'individual', child: Text('فرد')),
                  DropdownMenuItem(value: 'company', child: Text('شركة')),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _partyType = value);
                      },
              ),
              const SizedBox(height: 12),
              HasadFormField(
                label: 'الرقم الضريبي (اختياري)',
                controller: _taxId,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              HasadFormField(
                label: 'الهاتف (اختياري)',
                controller: _phone,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              HasadFormField(
                label: 'البريد الإلكتروني (اختياري)',
                controller: _email,
                enabled: !_saving,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                enabled: !_saving,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'العنوان (اختياري)',
                ),
              ),
              const SizedBox(height: 12),
              HasadFormField(
                label: 'مدة السداد بالأيام (اختياري)',
                controller: _paymentTerms,
                enabled: !_saving,
                validator: validatePaymentTerms,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isSupplier,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _isSupplier = value),
                title: const Text('تصنيف العميل كمورد أيضاً'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _isActive = value),
                title: const Text('عميل نشط'),
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
}
