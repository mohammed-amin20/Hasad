import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/customers/domain/customer.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:hasad_erp_v2/sales/data/sales_repository.dart';
import 'package:hasad_erp_v2/sales/domain/invoice_calculations.dart';
import 'package:hasad_erp_v2/sales/domain/sales_invoice.dart';
import 'package:uuid/uuid.dart';

class SalesInvoicesScreen extends StatefulWidget {
  const SalesInvoicesScreen({
    super.key,
    required this.companyId,
    this.repository,
    this.openEditor = false,
  });
  final String companyId;
  final SalesRepository? repository;
  final bool openEditor;
  @override
  State<SalesInvoicesScreen> createState() => _SalesInvoicesScreenState();
}

class _SalesInvoicesScreenState extends State<SalesInvoicesScreen> {
  late final SalesRepository _repository =
      widget.repository ?? SupabaseSalesRepository();
  final _search = TextEditingController();
  List<SalesInvoice> _invoices = const [];
  bool _loading = true;
  String? _error;
  SalesInvoiceStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.openEditor) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEditor());
    }
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
      final rows = await _repository.listInvoices(companyId: widget.companyId);
      if (!mounted) return;
      setState(() => _invoices = rows);
    } on SalesFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) setState(() => _error = 'تعذر تحميل فواتير المبيعات.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor() async {
    final saved = await showDialog<SalesInvoice>(
      context: context,
      builder: (_) => SalesInvoiceEditorDialog(
        companyId: widget.companyId,
        repository: _repository,
      ),
    );
    if (!mounted || saved == null) return;
    await _load();
    if (mounted) {
      HasadNotification.show(context, 'تم حفظ مسودة الفاتورة بنجاح.');
    }
  }

  Future<void> _details(SalesInvoice invoice) async {
    final result = await showDialog<SalesPostingResult>(
      context: context,
      builder: (_) =>
          SalesInvoiceDetailsDialog(invoice: invoice, repository: _repository),
    );
    if (!mounted || result == null) return;
    await _load();
    if (mounted) {
      HasadNotification.show(
        context,
        result.replayed
            ? 'الفاتورة كانت مرحّلة بالفعل بالرقم ${result.invoice.documentNo}. '
            : 'تم ترحيل الفاتورة بالرقم الرسمي ${result.invoice.documentNo}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = _search.text.trim().toLowerCase();
    final visible = _invoices
        .where(
          (invoice) =>
              (_status == null || invoice.status == _status) &&
              (search.isEmpty ||
                  '${invoice.documentNo ?? ''} ${invoice.gross} ${invoice.docDate.toIso8601String()}'
                      .toLowerCase()
                      .contains(search)),
        )
        .toList();
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HasadPageHeader(
            title: 'فواتير المبيعات',
            subtitle: 'عرض الفواتير الحقيقية للشركة الحالية. حفظ المسودة يتم بعملية خادم ذرية؛ الترحيل والطباعة لم يُفعّلا بعد.',
            trailing: HasadPrimaryButton(
              label: 'إنشاء فاتورة',
              icon: Icons.add_chart_outlined,
              onPressed: _loading ? null : _openEditor,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 230,
                child: HasadMetricCard(
                  label: 'كل الفواتير',
                  value: '${_invoices.length}',
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              SizedBox(
                width: 230,
                child: HasadMetricCard(
                  label: 'مسودات',
                  value:
                      '${_invoices.where((x) => x.status == SalesInvoiceStatus.draft).length}',
                  icon: Icons.edit_note_outlined,
                ),
              ),
              SizedBox(
                width: 230,
                child: HasadMetricCard(
                  label: 'مرحّلة',
                  value:
                      '${_invoices.where((x) => x.status == SalesInvoiceStatus.posted).length}',
                  icon: Icons.verified_outlined,
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
                      width: 330,
                      child: HasadSearchField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        hint: 'بحث بالرقم أو التاريخ أو الإجمالي',
                      ),
                    ),
                    DropdownButton<SalesInvoiceStatus?>(
                      value: _status,
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('كل الحالات'),
                        ),
                        DropdownMenuItem(
                          value: SalesInvoiceStatus.draft,
                          child: Text('مسودة'),
                        ),
                        DropdownMenuItem(
                          value: SalesInvoiceStatus.posted,
                          child: Text('مرحّلة'),
                        ),
                        DropdownMenuItem(
                          value: SalesInvoiceStatus.cancelled,
                          child: Text('ملغاة'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _status = value),
                    ),
                    IconButton(
                      tooltip: 'تحديث',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const HasadLoadingState(
                    label: 'جارٍ تحميل فواتير المبيعات...',
                  )
                else if (_error != null)
                  HasadErrorState(message: _error!, onRetry: _load)
                else if (_invoices.isEmpty)
                  HasadEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'لا توجد فواتير مرئية',
                    message: 'قد لا تكون صلاحية قراءة المبيعات مفعّلة بعد، أو لا توجد فواتير في هذه الشركة.',
                    action: HasadPrimaryButton(
                      label: 'إنشاء فاتورة',
                      icon: Icons.add,
                      onPressed: _openEditor,
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
                      DataColumn(label: Text('الرقم')),
                      DataColumn(label: Text('التاريخ')),
                      DataColumn(label: Text('الصافي')),
                      DataColumn(label: Text('الضريبة')),
                      DataColumn(label: Text('الإجمالي')),
                      DataColumn(label: Text('الحالة')),
                      DataColumn(label: Text('')),
                    ],
                    rows: visible.map(_row).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataRow _row(SalesInvoice invoice) => DataRow(
    cells: [
      DataCell(Text(invoice.documentNo ?? 'مسودة بلا رقم')),
      DataCell(Text(_date(invoice.docDate))),
      DataCell(Text(invoice.net.toString())),
      DataCell(Text(invoice.tax.toString())),
      DataCell(Text(invoice.gross.toString())),
      DataCell(_statusBadge(invoice.status)),
      DataCell(
        IconButton(
          tooltip: 'التفاصيل',
          icon: const Icon(Icons.visibility_outlined),
          onPressed: () => _details(invoice),
        ),
      ),
    ],
  );
}

class SalesInvoiceDetailsDialog extends StatefulWidget {
  const SalesInvoiceDetailsDialog({
    super.key,
    required this.invoice,
    required this.repository,
  });
  final SalesInvoice invoice;
  final SalesRepository repository;
  @override
  State<SalesInvoiceDetailsDialog> createState() =>
      _SalesInvoiceDetailsDialogState();
}

class _SalesInvoiceDetailsDialogState extends State<SalesInvoiceDetailsDialog> {
  List<SalesInvoiceLine>? _lines;
  String? _error;
  String? _postingError;
  bool _posting = false;
  late bool _postingUnavailable = !widget.repository.isPostingAvailable;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lines = await widget.repository.listLines(
        companyId: widget.invoice.companyId,
        documentId: widget.invoice.id,
      );
      if (mounted) setState(() => _lines = lines);
    } on SalesFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool get _isDraft => widget.invoice.status == SalesInvoiceStatus.draft;

  Future<void> _confirmAndPost() async {
    if (_posting || _postingUnavailable || !_isDraft) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد ترحيل الفاتورة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيُخصص الرقم الرسمي ويُنشئ الخادم حركة المخزون والقيد المحاسبي في عملية واحدة. لا يمكن تعديل الفاتورة بعد الترحيل.',
            ),
            const SizedBox(height: 16),
            Text('الصافي: ${widget.invoice.net}'),
            Text('الضريبة: ${widget.invoice.tax}'),
            Text(
              'الإجمالي: ${widget.invoice.gross}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            key: const ValueKey('sales-post-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('تأكيد الترحيل'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _post();
  }

  Future<void> _post() async {
    if (_posting || _postingUnavailable || !_isDraft) return;
    setState(() {
      _posting = true;
      _postingError = null;
    });
    try {
      final result = await widget.repository.postInvoice(widget.invoice);
      if (!mounted) return;
      if (result.invoice.id != widget.invoice.id ||
          result.invoice.companyId != widget.invoice.companyId ||
          result.invoice.status != SalesInvoiceStatus.posted ||
          result.invoice.documentNo == null) {
        throw const SalesFailure(
          'لم يؤكد الخادم ترحيل الفاتورة بالرقم الرسمي، لذلك لم تُعتبر العملية ناجحة.',
          code: 'UNCONFIRMED_POST',
        );
      }
      Navigator.of(context).pop(result);
    } on SalesFailure catch (error) {
      if (mounted) {
        setState(() {
          _postingError = error.message;
          _postingUnavailable = error.postingUnavailable;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _postingError = 'تعذر تأكيد الترحيل بسبب خطأ غير متوقع. لم تُعتبر العملية ناجحة؛ حدّث الفاتورة قبل إعادة المحاولة.';
        });
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.receipt_long_outlined, color: HasadPalette.amberDark),
        const SizedBox(width: 8),
        Expanded(child: Text(widget.invoice.documentNo ?? 'مسودة فاتورة')),
        _statusBadge(widget.invoice.status),
      ],
    ),
    content: SizedBox(
      width: 860,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 28,
              runSpacing: 10,
              children: [
                Text('التاريخ: ${_date(widget.invoice.docDate)}'),
                Text('الصافي: ${widget.invoice.net}'),
                Text('الضريبة: ${widget.invoice.tax}'),
                Text('الإجمالي: ${widget.invoice.gross}'),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: HasadPalette.danger))
            else if (_lines == null)
              const HasadLoadingState(label: 'جارٍ تحميل البنود...')
            else
              HasadDataTable(
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('الكمية')),
                  DataColumn(label: Text('السعر')),
                  DataColumn(label: Text('الخصم')),
                  DataColumn(label: Text('الضريبة')),
                  DataColumn(label: Text('الإجمالي')),
                ],
                rows: _lines!
                    .map(
                      (line) => DataRow(
                        cells: [
                          DataCell(Text('${line.lineNo}')),
                          DataCell(Text(line.quantity.toDecimalString())),
                          DataCell(Text(line.unitPrice.toString())),
                          DataCell(Text(line.discount.toString())),
                          DataCell(Text(line.tax.toString())),
                          DataCell(Text(line.gross.toString())),
                        ],
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 16),
            if (_postingError != null)
              SaveErrorBanner(message: _postingError!, code: null),
            if (_isDraft && _postingUnavailable)
              const Text(
                'ترحيل هذه المسودة غير متاح هنا حتى يُعتمد ويُنشر إجراء S3 الذري. لا يتم تنفيذ أي خصم مخزون أو قيد محاسبي من الواجهة.',
                style: TextStyle(color: HasadPalette.muted),
              )
            else if (_isDraft)
              const Text(
                'يُنفذ الترحيل من خلال طلب خادم ذري واحد فقط؛ لا تُرسل الواجهة أي حركات مخزون أو قيود محاسبية منفصلة.',
                style: TextStyle(color: HasadPalette.muted),
              )
            else
              const Text(
                'الفاتورة المرحّلة للعرض فقط. تتم التصحيحات لاحقاً بعكس مرتبط، وليس بتعديل هذه الفاتورة.',
                style: TextStyle(color: HasadPalette.muted),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (_isDraft && !_postingUnavailable)
        FilledButton.icon(
          key: const ValueKey('sales-details-post'),
          onPressed: _posting ? null : _confirmAndPost,
          icon: _posting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_outlined),
          label: Text(_posting ? 'جارٍ الترحيل...' : 'ترحيل الفاتورة'),
        ),
      TextButton(
        onPressed: _posting ? null : () => Navigator.pop(context),
        child: const Text('إغلاق'),
      ),
    ],
  );
}

class SalesInvoiceEditorDialog extends StatefulWidget {
  const SalesInvoiceEditorDialog({
    super.key,
    required this.companyId,
    required this.repository,
  });
  final String companyId;
  final SalesRepository repository;
  @override
  State<SalesInvoiceEditorDialog> createState() =>
      _SalesInvoiceEditorDialogState();
}

class _SalesInvoiceEditorDialogState extends State<SalesInvoiceEditorDialog> {
  final _form = GlobalKey<FormState>();
  SalesReferenceData? _refs;
  String? _loadError;
  String? _saveError;
  String? _saveErrorCode;
  bool _loading = true;
  bool _saving = false;
  Customer? _customer;
  SalesDocumentType? _type;
  FiscalYearOption? _year;
  VatMode _vatMode = VatMode.exclusive;
  final List<_EditableLine> _lines = [_EditableLine()];

  // Stable identities for this editor session. A retried save updates the same
  // draft instead of inserting a second invoice, even when the first attempt
  // timed out after the server had already committed.
  final String _draftId = const Uuid().v4();
  final String _idempotencyKey = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    _loadError = null;
    if (!_loading) setState(() => _loading = true);
    try {
      final refs = await widget.repository.loadReferences(
        companyId: widget.companyId,
      );
      if (!mounted) return;
      setState(() {
        _refs = refs;
        _type =
            refs.documentTypes
                .where((x) => x.issuance == 'posting')
                .firstOrNull ??
            refs.documentTypes.firstOrNull;
        _year = refs.fiscalYears.firstOrNull;
      });
    } on SalesFailure catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } on Object {
      if (mounted) {
        setState(() => _loadError = 'تعذر تحميل بيانات إنشاء الفاتورة.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InvoiceTotals get _totals =>
      sumInvoiceTotals(_lines.map((line) => line.totals(_vatMode)));

  void _showSaveError(String message, [String? code]) => setState(() {
    _saveError = message;
    _saveErrorCode = code;
  });

  /// Local calendar date of the document, so the fiscal-year check on the
  /// server never sees a UTC-shifted day.
  DateTime _documentDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _requireConfirmedDraft(SalesInvoice saved, SalesInvoiceDraft draft) {
    if (saved.id != draft.id ||
        saved.companyId != draft.companyId ||
        saved.status != SalesInvoiceStatus.draft) {
      throw const SalesFailure(
        'لم يؤكد الخادم حفظ المسودة كما هو متوقع، لذلك لم تُعتبر العملية ناجحة.',
        code: 'UNCONFIRMED_SAVE',
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final form = _form.currentState;
    if (form == null) return;
    if (!form.validate()) {
      _showSaveError('راجع الحقول المميزة قبل حفظ المسودة.');
      return;
    }
    if (_customer == null || _type == null || _year == null) {
      _showSaveError('اختر العميل ونوع المستند والسنة المالية المفتوحة.');
      return;
    }
    if (_lines.any(
      (line) =>
          line.product == null ||
          (line.product!.trackInventory && line.warehouse == null),
    )) {
      _showSaveError('اختر صنفاً، واختر مستودعاً لكل صنف مخزني.');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
      _saveErrorCode = null;
    });
    try {
      final draft = SalesInvoiceDraft(
        id: _draftId,
        companyId: widget.companyId,
        partyId: _customer!.id,
        docDate: _documentDate(),
        vatMode: _vatMode,
        documentTypeId: _type!.id,
        fiscalYearId: _year!.id,
        idempotencyKey: _idempotencyKey,
        lines: _lines.map((line) => line.toDraft()).toList(growable: false),
      );
      final saved = await widget.repository.saveDraftAtomically(draft);
      if (!mounted) return;
      _requireConfirmedDraft(saved, draft);
      Navigator.of(context).pop(saved);
      return;
    } on SalesFailure catch (e) {
      if (mounted) _showSaveError(e.message, e.code);
    } on Object {
      if (mounted) {
        _showSaveError(
          'تعذر حفظ المسودة بسبب خطأ غير متوقع في التطبيق، ولم يتم تأكيد الحفظ. أعد المحاولة أو راجع مسؤول النظام.',
          'UNEXPECTED',
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('إنشاء فاتورة مبيعات'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1120),
      child: _body(context),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton.icon(
        key: const ValueKey('sales-editor-save'),
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text(_saving ? 'جارٍ حفظ المسودة...' : 'حفظ المسودة'),
      ),
    ],
  );

  Widget _body(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 300,
        child: HasadLoadingState(
          label: 'جارٍ تحميل العملاء والأصناف والمستودعات...',
        ),
      );
    }
    if (_refs == null) {
      return SizedBox(
        height: 300,
        child: HasadErrorState(
          message: _loadError ?? 'تعذر تحميل بيانات إنشاء الفاتورة.',
          onRetry: _load,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pinned above the scrollable form so a failed save is always visible,
        // whatever the dialog height or scroll position.
        if (_saveError != null)
          SaveErrorBanner(message: _saveError!, code: _saveErrorCode),
        Flexible(
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تُحفظ المسودة على الخادم في عملية واحدة تشمل الرأس والبنود. لا يتم ترحيل الفاتورة ولا خصم مخزون في هذه الخطوة.',
                    style: TextStyle(color: HasadPalette.muted),
                  ),
                  const SizedBox(height: 16),
                  _header(context),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text(
                        'بنود الفاتورة',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _lines.add(_EditableLine())),
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة بند'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._lines.asMap().entries.map(
                    (entry) => _lineEditor(entry.key, entry.value),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: HasadCard(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 22,
                        runSpacing: 10,
                        children: [
                          _total('الصافي', _totals.net),
                          _total('الضريبة', _totals.tax),
                          _total('الإجمالي', _totals.gross, bold: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_saving)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(minHeight: 3),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 14,
    children: [
      SizedBox(
        width: 260,
        child: DropdownButtonFormField<Customer>(
          // ignore: deprecated_member_use
          value: _customer,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'العميل'),
          items: _refs!.customers
              .map(
                (x) => DropdownMenuItem(
                  value: x,
                  child: Text(
                    '${x.code} — ${x.nameAr}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (x) => setState(() => _customer = x),
          validator: (x) => x == null ? 'اختر العميل.' : null,
        ),
      ),
      SizedBox(
        width: 230,
        child: DropdownButtonFormField<SalesDocumentType>(
          // ignore: deprecated_member_use
          value: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'نوع المستند'),
          items: _refs!.documentTypes
              .map(
                (x) => DropdownMenuItem(
                  value: x,
                  child: Text(
                    x.nameAr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (x) => setState(() => _type = x),
          validator: (x) => x == null ? 'اختر نوع المستند.' : null,
        ),
      ),
      SizedBox(
        width: 210,
        child: DropdownButtonFormField<FiscalYearOption>(
          // ignore: deprecated_member_use
          value: _year,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'السنة المالية'),
          items: _refs!.fiscalYears
              .map(
                (x) => DropdownMenuItem(
                  value: x,
                  child: Text(
                    '${x.startDate.year} (${x.status})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (x) => setState(() => _year = x),
          validator: (x) => x == null ? 'اختر سنة مالية مفتوحة.' : null,
        ),
      ),
      SizedBox(
        width: 190,
        child: DropdownButtonFormField<VatMode>(
          // ignore: deprecated_member_use
          value: _vatMode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'طريقة الضريبة'),
          items: const [
            DropdownMenuItem(
              value: VatMode.exclusive,
              child: Text(
                'غير شامل الضريبة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DropdownMenuItem(
              value: VatMode.inclusive,
              child: Text(
                'شامل الضريبة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          onChanged: (x) {
            if (x != null) setState(() => _vatMode = x);
          },
        ),
      ),
    ],
  );

  Widget _lineEditor(int index, _EditableLine line) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 225,
          child: DropdownButtonFormField<Product>(
            // ignore: deprecated_member_use
            value: line.product,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'الصنف ${index + 1}'),
            items: _refs!.products
                .map(
                  (x) => DropdownMenuItem(
                    value: x,
                    child: Text(
                      '${x.code} — ${x.nameAr}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (x) => setState(() {
              line.product = x;
              if (x?.trackInventory == false) line.warehouse = null;
            }),
            validator: (x) => x == null ? 'اختر الصنف.' : null,
          ),
        ),
        SizedBox(
          width: 185,
          child: DropdownButtonFormField<Warehouse>(
            // ignore: deprecated_member_use
            value: line.warehouse,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'المستودع'),
            items: _refs!.warehouses
                .map(
                  (x) => DropdownMenuItem(
                    value: x,
                    child: Text(
                      x.nameAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: line.product?.trackInventory == false
                ? null
                : (x) => setState(() => line.warehouse = x),
            validator: (_) =>
                line.product?.trackInventory == true && line.warehouse == null
                ? 'المستودع مطلوب.'
                : null,
          ),
        ),
        _input(
          'الكمية',
          line.quantity,
          validateQuantity,
          () => setState(() {}),
        ),
        _input(
          'سعر الوحدة',
          line.price,
          validateUnitPrice,
          () => setState(() {}),
        ),
        _input('الخصم', line.discount, validateDiscount, () => setState(() {})),
        _input(
          'ضريبة %',
          line.taxRate,
          (x) => parseTaxRateMillis(x ?? '') == null ? 'نسبة غير صالحة.' : null,
          () => setState(() {}),
        ),
        SizedBox(
          width: 94,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              line.totals(_vatMode).gross.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        IconButton(
          tooltip: 'حذف البند',
          onPressed: _lines.length == 1
              ? null
              : () => setState(() {
                  final removed = _lines.removeAt(index);
                  removed.dispose();
                }),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
  Widget _input(
    String label,
    TextEditingController controller,
    String? Function(String?) validator,
    VoidCallback onChanged,
  ) => SizedBox(
    width: 105,
    child: TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: validator,
      onChanged: (_) => onChanged(),
    ),
  );
  Widget _total(String label, InvoiceAmount value, {bool bold = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: HasadPalette.muted)),
          Text(
            value.toString(),
            style: TextStyle(
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
              fontSize: bold ? 20 : 16,
            ),
          ),
        ],
      );
}

/// Always-visible save feedback. Rendered outside the scrollable form so a
/// failure can never be scrolled out of sight.
class SaveErrorBanner extends StatelessWidget {
  const SaveErrorBanner({super.key, required this.message, this.code});

  final String message;
  final String? code;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3F2),
      border: Border.all(color: HasadPalette.danger),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: HasadPalette.danger, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(
                  color: HasadPalette.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (code != null && code!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'رمز الخطأ: $code',
                    style: const TextStyle(
                      color: HasadPalette.danger,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EditableLine {
  _EditableLine()
    : quantity = TextEditingController(text: '1'),
      price = TextEditingController(text: '0.00'),
      discount = TextEditingController(text: '0.00'),
      taxRate = TextEditingController(text: '0');
  Product? product;
  Warehouse? warehouse;
  final TextEditingController quantity, price, discount, taxRate;
  InvoiceLineTotals totals(VatMode mode) => calculateInvoiceLine(
    quantity:
        InvoiceQuantity.tryParse(quantity.text) ??
        InvoiceQuantity.tryParse('0')!,
    unitPrice: InvoiceAmount.tryParse(price.text) ?? InvoiceAmount.zero(),
    discount: InvoiceAmount.tryParse(discount.text) ?? InvoiceAmount.zero(),
    taxRateMillis: parseTaxRateMillis(taxRate.text) ?? 0,
    vatMode: mode,
  );
  SalesInvoiceDraftLine toDraft() => SalesInvoiceDraftLine(
    id: const Uuid().v4(),
    productId: product!.id,
    warehouseId: warehouse?.id,
    quantity: InvoiceQuantity.tryParse(quantity.text)!,
    unitPrice: InvoiceAmount.tryParse(price.text)!,
    discount: InvoiceAmount.tryParse(discount.text)!,
    taxRateMillis: parseTaxRateMillis(taxRate.text) ?? 0,
  );
  void dispose() {
    quantity.dispose();
    price.dispose();
    discount.dispose();
    taxRate.dispose();
  }
}

HasadStatusBadge _statusBadge(SalesInvoiceStatus status) => HasadStatusBadge(
  label: salesInvoiceStatusLabel(status),
  color: switch (status) {
    SalesInvoiceStatus.draft => HasadPalette.warning,
    SalesInvoiceStatus.posted => HasadPalette.success,
    SalesInvoiceStatus.cancelled => HasadPalette.danger,
  },
);
String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
