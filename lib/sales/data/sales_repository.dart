import 'dart:async';

import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/customers/domain/customer.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:hasad_erp_v2/sales/domain/sales_invoice.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SalesRepository {
  Future<List<SalesInvoice>> listInvoices({required String companyId});
  Future<List<SalesInvoiceLine>> listLines({
    required String companyId,
    required String documentId,
  });
  Future<SalesReferenceData> loadReferences({required String companyId});
  Future<SalesInvoice> saveDraftAtomically(SalesInvoiceDraft draft);

  /// False until the approved, reviewed S3 operation is deployed explicitly.
  bool get isPostingAvailable;
  Future<SalesPostingResult> postInvoice(SalesInvoice invoice);
}

/// Upper bound for one atomic draft save round trip, so a stalled request can
/// never leave the editor stuck in a permanent "saving" state with no feedback.
const saveDraftRequestTimeout = Duration(seconds: 30);
const postInvoiceRequestTimeout = Duration(seconds: 30);

class SalesReferenceData {
  const SalesReferenceData({
    required this.customers,
    required this.products,
    required this.warehouses,
    required this.documentTypes,
    required this.fiscalYears,
  });
  final List<Customer> customers;
  final List<Product> products;
  final List<Warehouse> warehouses;
  final List<SalesDocumentType> documentTypes;
  final List<FiscalYearOption> fiscalYears;
}

class SupabaseSalesRepository implements SalesRepository {
  SupabaseSalesRepository({SupabaseClient? client, this.postingEnabled = false})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  /// Deliberately false in this build. Enabling the UI requires a separately
  /// approved S3 database deployment; this flag does not grant any privilege.
  final bool postingEnabled;

  @override
  bool get isPostingAvailable => postingEnabled;

  static const _invoiceColumns =
      'id,company_id,doc_kind,status,party_id,doc_date,vat_mode,doc_type_id,fiscal_year_id,doc_no,idempotency_key,net,tax,gross,posted_at';
  static const _lineColumns =
      'id,company_id,document_id,line_no,product_id,warehouse_id,qty,unit_price,discount_amount,tax_rate,net,tax,gross';

  @override
  Future<List<SalesInvoice>> listInvoices({required String companyId}) async {
    try {
      final rows = await _client
          .schema('hasad')
          .from('sales_documents')
          .select(_invoiceColumns)
          .eq('company_id', companyId)
          .eq('doc_kind', 'invoice')
          .order('doc_date', ascending: false);
      final invoices = rows
          .map((row) => SalesInvoice.fromJson(row))
          .toList(growable: false);
      _assertCompany(invoices.map((row) => row.companyId), companyId);
      return invoices;
    } on SalesFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _map(error, 'تحميل فواتير المبيعات');
    } on FormatException {
      throw const SalesFailure(
        'استجابة فواتير المبيعات لا تطابق عقد البيانات.',
        code: 'INVALID_RESPONSE',
      );
    } on Object {
      throw const SalesFailure(
        'تعذر تحميل فواتير المبيعات.',
        code: 'UNAVAILABLE',
      );
    }
  }

  @override
  Future<List<SalesInvoiceLine>> listLines({
    required String companyId,
    required String documentId,
  }) async {
    try {
      final rows = await _client
          .schema('hasad')
          .from('sales_document_lines')
          .select(_lineColumns)
          .eq('company_id', companyId)
          .eq('document_id', documentId)
          .order('line_no');
      final lines = rows
          .map((row) => SalesInvoiceLine.fromJson(row))
          .toList(growable: false);
      _assertCompany(lines.map((row) => row.companyId), companyId);
      return lines;
    } on SalesFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _map(error, 'تحميل بنود الفاتورة');
    } on FormatException {
      throw const SalesFailure(
        'استجابة بنود الفاتورة غير صالحة.',
        code: 'INVALID_RESPONSE',
      );
    } on Object {
      throw const SalesFailure(
        'تعذر تحميل بنود الفاتورة.',
        code: 'UNAVAILABLE',
      );
    }
  }

  @override
  Future<SalesReferenceData> loadReferences({required String companyId}) async {
    try {
      final results = await Future.wait<Object?>([
        _loadReference(
          _client
              .schema('hasad')
              .from('parties')
              .select(
                'id,company_id,code,name_ar,name_en,party_type,is_customer,is_supplier,tax_id,phone,email,address,payment_terms_days,is_active',
              )
              .eq('company_id', companyId)
              .eq('is_customer', true)
              .eq('is_active', true)
              .order('code'),
          'تحميل العملاء',
        ),
        _loadReference(
          _client
              .schema('hasad')
              .from('products')
              .select(
                'id,company_id,code,name_ar,name_en,barcode,category_id,base_uom_id,track_inventory,is_active',
              )
              .eq('company_id', companyId)
              .eq('is_active', true)
              .order('code'),
          'تحميل الأصناف',
        ),
        _loadReference(
          _client
              .schema('hasad')
              .from('warehouses')
              .select('id,company_id,code,name_ar,is_active')
              .eq('company_id', companyId)
              .eq('is_active', true)
              .order('code'),
          'تحميل المستودعات',
        ),
        _loadReference(
          _client
              .schema('hasad')
              .from('document_types')
              .select('id,company_id,code,name_ar,issuance,is_active')
              .eq('company_id', companyId)
              .eq('is_active', true)
              .order('code'),
          'تحميل أنواع مستندات المبيعات',
        ),
        _loadReference(
          _client
              .schema('hasad')
              .from('fiscal_years')
              .select('id,company_id,start_date,end_date,status')
              .eq('company_id', companyId)
              .eq('status', 'open')
              .order('start_date', ascending: false),
          'تحميل السنوات المالية',
        ),
      ]);
      final customers = (results[0] as List)
          .map((row) => Customer.fromJson(row))
          .toList(growable: false);
      final products = (results[1] as List)
          .map(_product)
          .toList(growable: false);
      final warehouses = (results[2] as List)
          .map(_warehouse)
          .toList(growable: false);
      final types = (results[3] as List)
          .map(
            (row) => SalesDocumentType.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
      final years = (results[4] as List)
          .map(
            (row) => FiscalYearOption.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
      _assertCompany([
        ...customers.map((x) => x.companyId),
        ...products.map((x) => x.companyId),
        ...warehouses.map((x) => x.companyId),
        ...types.map((x) => x.companyId),
        ...years.map((x) => x.companyId),
      ], companyId);
      return SalesReferenceData(
        customers: customers,
        products: products,
        warehouses: warehouses,
        documentTypes: types,
        fiscalYears: years,
      );
    } on SalesFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _map(error, 'تحميل بيانات إنشاء الفاتورة');
    } on FormatException {
      throw const SalesFailure(
        'استجابة بيانات الفاتورة غير صالحة.',
        code: 'INVALID_RESPONSE',
      );
    } on Object {
      throw const SalesFailure(
        'تعذر تحميل بيانات إنشاء الفاتورة.',
        code: 'UNAVAILABLE',
      );
    }
  }

  Future<T> _loadReference<T>(Future<T> request, String action) async {
    try {
      return await request;
    } on PostgrestException catch (error) {
      throw _map(error, action);
    }
  }

  @override
  Future<SalesInvoice> saveDraftAtomically(SalesInvoiceDraft draft) async {
    try {
      final response = await _client
          .schema('hasad')
          .rpc('save_sales_invoice_draft', params: draft.toRpcParams())
          .timeout(saveDraftRequestTimeout);
      if (response is! Map) {
        throw const FormatException('Invalid draft response');
      }
      final invoice = SalesInvoice.fromJson(
        Map<String, dynamic>.from(response),
      );
      _assertCompany([invoice.companyId], draft.companyId);
      if (invoice.id != draft.id) {
        throw const FormatException('Draft response identity mismatch');
      }
      return invoice;
    } on SalesFailure {
      rethrow;
    } on TimeoutException {
      throw const SalesFailure(
        'انتهت مهلة حفظ المسودة دون رد من الخادم، لذلك لم يتم تأكيد الحفظ. أعد المحاولة بعد التحقق من الاتصال.',
        code: 'TIMEOUT',
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw draftPersistenceUnavailable();
      }
      throw mapSalesDraftFailure(error);
    } on FormatException {
      throw const SalesFailure(
        'استجابة حفظ المسودة لا تطابق عقد الفاتورة.',
        code: 'INVALID_RESPONSE',
      );
    } on Object {
      throw const SalesFailure('تعذر حفظ مسودة الفاتورة.', code: 'UNAVAILABLE');
    }
  }

  @override
  Future<SalesPostingResult> postInvoice(SalesInvoice invoice) async {
    if (!isPostingAvailable) throw salesPostingUnavailable();
    try {
      final response = await _client
          .schema('hasad')
          .rpc(
            'post_sales_invoice',
            params: {
              'p_company_id': invoice.companyId,
              'p_document_id': invoice.id,
              'p_idempotency_key': invoice.idempotencyKey,
            },
          )
          .timeout(postInvoiceRequestTimeout);
      if (response is! Map) {
        throw const FormatException('Invalid posting response');
      }
      final result = SalesPostingResult.fromJson(
        Map<String, dynamic>.from(response),
      );
      _assertCompany([result.invoice.companyId], invoice.companyId);
      if (result.invoice.id != invoice.id ||
          result.invoice.status != SalesInvoiceStatus.posted ||
          result.invoice.documentNo == null ||
          result.invoice.idempotencyKey != invoice.idempotencyKey) {
        throw const FormatException('Posting response identity mismatch');
      }
      return result;
    } on SalesFailure {
      rethrow;
    } on TimeoutException {
      throw const SalesFailure(
        'انتهت مهلة الترحيل دون تأكيد من الخادم. لا تعِد المحاولة قبل تحديث الفاتورة للتحقق من حالتها.',
        code: 'TIMEOUT',
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw salesPostingUnavailable();
      }
      throw mapSalesPostingFailure(error);
    } on FormatException {
      throw const SalesFailure(
        'استجابة ترحيل الفاتورة لا تطابق العقد الآمن.',
        code: 'INVALID_RESPONSE',
      );
    } on Object {
      throw const SalesFailure('تعذر ترحيل الفاتورة.', code: 'UNAVAILABLE');
    }
  }

  Product _product(Object? row) {
    final data = Map<String, dynamic>.from(row as Map);
    return Product(
      id: '${data['id']}',
      companyId: '${data['company_id']}',
      code: '${data['code']}',
      nameAr: '${data['name_ar']}',
      nameEn: data['name_en'] as String?,
      barcode: data['barcode'] as String?,
      categoryId: data['category_id'] as String?,
      baseUomId: data['base_uom_id'] as String?,
      trackInventory: data['track_inventory'] == true,
      isActive: data['is_active'] == true,
    );
  }

  Warehouse _warehouse(Object? row) {
    final data = Map<String, dynamic>.from(row as Map);
    return Warehouse(
      id: '${data['id']}',
      companyId: '${data['company_id']}',
      code: '${data['code']}',
      nameAr: '${data['name_ar']}',
      isActive: data['is_active'] == true,
    );
  }

  void _assertCompany(Iterable<String> values, String companyId) {
    try {
      requireSalesCompanyScope(values, companyId);
    } on SalesCompanyScopeFailure {
      throw const SalesFailure(
        'وصلت بيانات خارج سياق الشركة الحالي وتم إيقاف العرض بأمان.',
        code: 'CROSS_COMPANY_RESPONSE',
      );
    }
  }

  SalesFailure _map(PostgrestException error, String action) =>
      mapSalesFailureCode(error.code, action);
}

SalesFailure mapSalesFailureCode(String? code, String action) => switch (code) {
  '42501' => SalesFailure('لا توجد صلاحية مفعلة لـ $action.', code: 'DENIED'),
  'PGRST116' => SalesFailure(
    'البيان غير متاح في الشركة الحالية.',
    code: 'NOT_FOUND',
  ),
  '23505' => SalesFailure(
    'تم إرسال العملية مسبقاً أو يوجد رقم/معرّف مكرر.',
    code: 'DUPLICATE',
  ),
  '23514' || '22003' => SalesFailure(
    'بيانات الفاتورة لا تطابق قيود قاعدة البيانات.',
    code: 'VALIDATION',
  ),
  _ => SalesFailure('تعذر $action. حاول مرة أخرى.', code: code),
};

/// Maps the safe, server-authored failure reasons of
/// `hasad.save_sales_invoice_draft` to explicit Arabic messages. The PostgREST
/// error code is preserved so the operator can quote it exactly.
SalesFailure mapSalesDraftFailure(PostgrestException error) {
  final reason = error.message.toUpperCase();
  if (error.code == '42501' || reason.contains('PERMISSION_DENIED')) {
    return const SalesFailure(
      'لا توجد صلاحية مفعلة لحفظ مسودة الفاتورة لهذا المستخدم في هذه الشركة.',
      code: 'DENIED',
    );
  }
  if (error.code == '23505' || reason.contains('IDEMPOTENCY_MISMATCH')) {
    return const SalesFailure(
      'تم إرسال هذه المسودة مسبقاً بمفتاح تكرار مختلف. أغلق النافذة وأنشئ فاتورة جديدة.',
      code: 'DUPLICATE',
    );
  }
  if (reason.contains('DRAFT_REFERENCE_INVALID')) {
    return SalesFailure(
      'العميل أو نوع المستند أو السنة المالية غير صالح لهذه الشركة، أو أن تاريخ الفاتورة خارج السنة المالية المفتوحة.',
      code: error.code ?? 'VALIDATION',
    );
  }
  if (reason.contains('DRAFT_LINE_REFERENCE_INVALID')) {
    return SalesFailure(
      'أحد الأصناف أو المستودعات غير صالح أو غير مفعّل، أو أن صنفاً مخزنيًا بلا مستودع.',
      code: error.code ?? 'VALIDATION',
    );
  }
  if (reason.contains('DRAFT_LINE_AMOUNT_INVALID')) {
    return SalesFailure(
      'قيم الكمية أو سعر الوحدة أو الخصم أو نسبة الضريبة لا تطابق دقة قاعدة البيانات.',
      code: error.code ?? 'VALIDATION',
    );
  }
  if (reason.contains('DRAFT_LINES_INVALID') ||
      reason.contains('DRAFT_INPUT_INVALID')) {
    return SalesFailure(
      'بنود الفاتورة أو بياناتها الأساسية غير مكتملة.',
      code: error.code ?? 'VALIDATION',
    );
  }
  if (reason.contains('DRAFT_NOT_EDITABLE')) {
    return const SalesFailure(
      'هذه الفاتورة لم تعد مسودة قابلة للتعديل.',
      code: 'NOT_EDITABLE',
    );
  }
  if (error.code == '23502') {
    return const SalesFailure(
      'قاعدة البيانات ترفض حقلاً إلزامياً في مسودة الفاتورة. تحتاج مراجعة بنية الجدول قبل إعادة المحاولة.',
      code: 'SCHEMA_NOT_NULL',
    );
  }
  if (error.code == '23514' || error.code == '22003') {
    return SalesFailure(
      'بيانات الفاتورة لا تطابق قيود قاعدة البيانات.',
      code: error.code,
    );
  }
  return SalesFailure(
    'تعذر حفظ مسودة الفاتورة${error.code == null ? '' : ' (رمز الخادم: ${error.code})'}.',
    code: error.code,
  );
}

/// Maps the S3 server-authored failure reasons without exposing database
/// internals. This client performs one RPC only; it never writes inventory or
/// accounting tables itself.
SalesFailure mapSalesPostingFailure(PostgrestException error) {
  final reason = error.message.toUpperCase();
  if (error.code == '42501' || reason.contains('PERMISSION_DENIED')) {
    return const SalesFailure(
      'لا توجد صلاحية ترحيل فواتير المبيعات لهذه الشركة.',
      code: 'DENIED',
    );
  }
  if (reason.contains('STOCK_INSUFFICIENT')) {
    return const SalesFailure(
      'المخزون المتاح لا يكفي لترحيل هذه الفاتورة. لم يُخصم أي مخزون.',
      code: 'STOCK_INSUFFICIENT',
    );
  }
  if (reason.contains('ALREADY_POSTED')) {
    return const SalesFailure(
      'الفاتورة مرحّلة بالفعل. حدّث القائمة للتحقق من الرقم الرسمي.',
      code: 'ALREADY_POSTED',
    );
  }
  if (reason.contains('ACCOUNTING_PREREQUISITES_MISSING')) {
    return const SalesFailure(
      'تعذر الترحيل لأن إعدادات الفترة أو الحسابات المحاسبية اللازمة غير مكتملة. لم تُرحّل الفاتورة.',
      code: 'ACCOUNTING_PREREQUISITES_MISSING',
    );
  }
  if (reason.contains('RATE_NOT_FOUND_FOR_DATE')) {
    return const SalesFailure(
      'نسبة الضريبة في الفاتورة غير مفعّلة لتاريخها. لم تُرحّل الفاتورة.',
      code: 'RATE_NOT_FOUND_FOR_DATE',
    );
  }
  if (reason.contains('IDEMPOTENCY_MISMATCH') || error.code == '23505') {
    return const SalesFailure(
      'مفتاح أمان الفاتورة لا يطابق المسودة المحفوظة. لا يمكن ترحيلها بهذه الحالة.',
      code: 'DUPLICATE',
    );
  }
  if (error.code == '23514' || error.code == '22003') {
    return SalesFailure(
      'بيانات الفاتورة أو إجمالياتها لا تجتاز تحقق الخادم. لم تُرحّل الفاتورة.',
      code: error.code,
    );
  }
  return SalesFailure(
    'تعذر ترحيل الفاتورة${error.code == null ? '' : ' (رمز الخادم: ${error.code})'}.',
    code: error.code,
  );
}

class SalesFailure implements Exception {
  const SalesFailure(
    this.message, {
    this.code,
    this.postingUnavailable = false,
  });
  final String message;
  final String? code;
  final bool postingUnavailable;
}

SalesFailure draftPersistenceUnavailable() => const SalesFailure(
  'الحفظ الذري للمسودات غير مفعّل بعد. لا يمكن حفظ الرأس والبنود بطلبات منفصلة.',
  code: 'DRAFT_PERSISTENCE_UNAVAILABLE',
);

SalesFailure salesPostingUnavailable() => const SalesFailure(
  'ترحيل الفواتير غير متاح في هذه البيئة حتى يُعتمد ويُنشر إجراء S3 الذري. لا يتم تنفيذ أي خصم مخزون أو قيد محاسبي من التطبيق.',
  code: 'POSTING_UNAVAILABLE',
  postingUnavailable: true,
);
