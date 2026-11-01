import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hasad_erp_v2/sales/data/sales_repository.dart';
import 'package:hasad_erp_v2/sales/dev/s3_posting_smoke_contract.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Narrow, injectable boundary for the DEV-only S3 posting smoke test.
///
/// Every method except [postSalesInvoice] is a read. Tests replace the whole
/// gateway, so no test can reach Supabase or invoke the posting RPC.
abstract interface class S3PostingSmokeGateway {
  /// Live PostgREST URL of the already-initialized Supabase client.
  String get activeRestUrl;

  String? get currentUserId;
  String? get currentUserEmail;

  Future<Map<String, dynamic>?> fetchMembership({
    required String userId,
    required String companyId,
  });

  Future<Map<String, dynamic>?> fetchCompanySettings({
    required String companyId,
  });

  Future<Map<String, dynamic>?> fetchInvoice({
    required String companyId,
    required String documentId,
  });

  Future<List<Map<String, dynamic>>> fetchLines({
    required String companyId,
    required String documentId,
  });

  Future<List<Map<String, dynamic>>> fetchProducts({
    required String companyId,
    required List<String> productIds,
  });

  Future<List<Map<String, dynamic>>> fetchStockLevels({
    required String companyId,
    required List<String> productIds,
  });

  /// Server-side `sales.post` eligibility probe. The posting RPC rechecks it.
  Future<bool> salesPostAllowed({required String companyId});

  Future<S3PostingOutcome> postSalesInvoice({
    required String companyId,
    required String documentId,
    required String idempotencyKey,
  });
}

class SupabaseS3PostingSmokeGateway implements S3PostingSmokeGateway {
  SupabaseS3PostingSmokeGateway({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  String get activeRestUrl => _client.rest.url;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  String? get currentUserEmail => _client.auth.currentUser?.email;

  @override
  Future<Map<String, dynamic>?> fetchMembership({
    required String userId,
    required String companyId,
  }) => _read('قراءة عضوية الشركة', () async {
    final response = await _client
        .schema('hasad')
        .from('company_memberships')
        .select('company_id,user_id,is_owner,status')
        .eq('user_id', userId)
        .eq('company_id', companyId)
        .eq('status', 'active')
        .maybeSingle();
    return _mapOrNull(response);
  });

  @override
  Future<Map<String, dynamic>?> fetchCompanySettings({
    required String companyId,
  }) => _read('قراءة إعدادات الشركة', () async {
    final response = await _client
        .schema('hasad')
        .from('company_settings')
        .select(
          S3PostingSmokeContract.companySettingsReadColumns.join(','),
        )
        .eq('company_id', companyId)
        .maybeSingle();
    return _mapOrNull(response);
  });

  @override
  Future<Map<String, dynamic>?> fetchInvoice({
    required String companyId,
    required String documentId,
  }) => _read('قراءة الفاتورة المستهدفة', () async {
    final response = await _client
        .schema('hasad')
        .from('sales_documents')
        .select(
          'id,company_id,doc_kind,status,party_id,doc_date,vat_mode,doc_type_id,'
          'fiscal_year_id,doc_no,idempotency_key,net,tax,gross,posted_at',
        )
        .eq('company_id', companyId)
        .eq('id', documentId)
        .maybeSingle();
    return _mapOrNull(response);
  });

  @override
  Future<List<Map<String, dynamic>>> fetchLines({
    required String companyId,
    required String documentId,
  }) => _read('قراءة بنود الفاتورة', () async {
    final response = await _client
        .schema('hasad')
        .from('sales_document_lines')
        .select(
          'id,company_id,document_id,line_no,product_id,warehouse_id,qty,'
          'unit_price,discount_amount,tax_rate,net,tax,gross',
        )
        .eq('company_id', companyId)
        .eq('document_id', documentId)
        .order('line_no');
    return _maps(response);
  });

  @override
  Future<List<Map<String, dynamic>>> fetchProducts({
    required String companyId,
    required List<String> productIds,
  }) {
    if (productIds.isEmpty) return Future.value(const []);
    return _read('قراءة الأصناف', () async {
      final response = await _client
          .schema('hasad')
          .from('products')
          .select('id,company_id,track_inventory,is_active')
          .eq('company_id', companyId)
          .inFilter('id', productIds);
      return _maps(response);
    });
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStockLevels({
    required String companyId,
    required List<String> productIds,
  }) {
    if (productIds.isEmpty) return Future.value(const []);
    return _read('قراءة أرصدة المخزون', () async {
      final response = await _client
          .schema('hasad')
          .from('stock_levels')
          .select('company_id,product_id,warehouse_id,qty,last_unit_cost')
          .eq('company_id', companyId)
          .inFilter('product_id', productIds);
      return _maps(response);
    });
  }

  @override
  Future<bool> salesPostAllowed({required String companyId}) =>
      _read('التحقق من صلاحية sales.post', () async {
        final response = await _client
            .schema('hasad')
            .rpc('sales_posting_allowed', params: {'p_company_id': companyId});
        if (response is! bool) {
          throw const S3SmokeFailure(
            'استجابة فحص صلاحية الترحيل غير صالحة. لم يُعتبر الفحص ناجحاً.',
            code: 'PERMISSION_PROBE_INVALID',
          );
        }
        return response;
      });

  @override
  Future<S3PostingOutcome> postSalesInvoice({
    required String companyId,
    required String documentId,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _client
          .schema('hasad')
          .rpc(
            'post_sales_invoice',
            params: {
              'p_company_id': companyId,
              'p_document_id': documentId,
              'p_idempotency_key': idempotencyKey,
            },
          )
          .timeout(postInvoiceRequestTimeout);
      final map = _asMap(response);
      final document = _asMap(map?['document']);
      final docNo = document?['doc_no'];
      final journalNo = map?['journal_entry_no'];
      final confirmed =
          document != null &&
          document['id'] == documentId &&
          document['company_id'] == companyId &&
          document['status'] == 'posted' &&
          document['idempotency_key'] == idempotencyKey &&
          docNo is String &&
          docNo.isNotEmpty &&
          journalNo is String &&
          journalNo.isNotEmpty;
      if (!confirmed) {
        throw const S3SmokeFailure(
          'لم تؤكد استجابة الخادم الرقم الرسمي والقيد. النتيجة غير مؤكدة ولا يجوز إعادة المحاولة.',
          code: 'UNCONFIRMED_RESPONSE',
          outcomeUncertain: true,
        );
      }
      return S3PostingOutcome(
        documentNo: docNo,
        journalEntryNo: journalNo,
        replayed: map?['replayed'] == true,
      );
    } on S3SmokeFailure {
      rethrow;
    } on TimeoutException {
      throw const S3SmokeFailure(
        'انتهت المهلة دون رد مؤكد من الخادم. لا تُعِد المحاولة؛ شغّل فحص ما بعد الترحيل للتحقق من الحالة.',
        code: 'TIMEOUT',
        outcomeUncertain: true,
      );
    } on PostgrestException catch (error) {
      throw _mapPostingFailure(error);
    } on Object {
      throw const S3SmokeFailure(
        'تعذر تأكيد نتيجة طلب الترحيل. لا تُعِد المحاولة؛ شغّل فحص ما بعد الترحيل أولاً.',
        code: 'UNCERTAIN',
        outcomeUncertain: true,
      );
    }
  }

  Future<T> _read<T>(String action, Future<T> Function() request) async {
    try {
      return await request();
    } on S3SmokeFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapReadFailure(error, action);
    } on Object {
      throw S3SmokeFailure(
        'تعذر $action. لم تُنفذ أي كتابة.',
        code: 'READ_UNAVAILABLE',
      );
    }
  }

  S3SmokeFailure _mapReadFailure(PostgrestException error, String action) =>
      mapS3ReadFailure(error, action);

  S3SmokeFailure _mapPostingFailure(PostgrestException error) {
    final reason = error.message.toUpperCase();
    final code = error.code;
    if (code == '42501' || reason.contains('PERMISSION_DENIED')) {
      return const S3SmokeFailure(
        'رفض الخادم الترحيل: صلاحية sales.post غير مثبتة لهذا المستخدم.',
        code: 'PERMISSION_DENIED',
      );
    }
    if (reason.contains('STOCK_INSUFFICIENT')) {
      return const S3SmokeFailure(
        'رفض الخادم الترحيل: المخزون غير كافٍ. لم تُرحّل الفاتورة.',
        code: 'STOCK_INSUFFICIENT',
      );
    }
    if (reason.contains('ALREADY_POSTED')) {
      return const S3SmokeFailure(
        'الفاتورة مرحّلة بالفعل. لا تُعِد المحاولة؛ تحقق من الرقم الرسمي.',
        code: 'ALREADY_POSTED',
      );
    }
    if (reason.contains('ACCOUNTING_PREREQUISITES_MISSING')) {
      return const S3SmokeFailure(
        'رفض الخادم الترحيل: إعدادات الفترة أو الحسابات المحاسبية غير مكتملة.',
        code: 'ACCOUNTING_PREREQUISITES_MISSING',
      );
    }
    if (reason.contains('RATE_NOT_FOUND_FOR_DATE')) {
      return const S3SmokeFailure(
        'رفض الخادم الترحيل: نسبة الضريبة غير مفعّلة لتاريخ الفاتورة.',
        code: 'RATE_NOT_FOUND_FOR_DATE',
      );
    }
    if (reason.contains('IDEMPOTENCY_MISMATCH') || code == '23505') {
      return const S3SmokeFailure(
        'رفض الخادم الترحيل: مفتاح التكرار لا يطابق الفاتورة المحفوظة.',
        code: 'IDEMPOTENCY_MISMATCH',
      );
    }
    if (code == '23514' || code == '22003') {
      return S3SmokeFailure(
        'رفض الخادم الترحيل: بيانات الفاتورة لا تجتاز تحقق قاعدة البيانات '
        '(رمز $code).',
        code: code!,
      );
    }
    if (code == null) {
      return const S3SmokeFailure(
        'تعذر تأكيد نتيجة طلب الترحيل. لا تُعِد المحاولة؛ شغّل فحص ما بعد الترحيل أولاً.',
        code: 'UNCERTAIN',
        outcomeUncertain: true,
      );
    }
    return S3SmokeFailure(
      'رفض الخادم الترحيل (رمز $code). لم يُعتبر الطلب ناجحاً.',
      code: code,
    );
  }
}

Map<String, dynamic>? _mapOrNull(Object? response) =>
    response is Map ? Map<String, dynamic>.from(response) : null;

/// Maps a read failure without guessing a cause.
///
/// A PostgREST privilege denial arrives as SQLSTATE `42501`. When the client
/// reports the bare HTTP status (`401`/`403`) the response carried no database
/// error code, so the failure is *not* evidence of a missing RLS policy or a
/// missing grant: only the read-only `company_settings` diagnostic can decide.
/// RLS row filtering never produces 403 — it returns zero rows, which
/// `maybeSingle()` surfaces as `null`.
S3SmokeFailure mapS3ReadFailure(PostgrestException error, String action) {
  switch (error.code) {
    case '42501':
      return S3SmokeFailure(
        'لا توجد صلاحية قراءة لازمة لـ $action. أوقف الفحص.',
        code: 'DENIED',
      );
    case '28000':
    case 'PGRST301':
      return const S3SmokeFailure(
        'انتهت جلسة الدخول. سجّل الدخول ثم أعد الفحص.',
        code: 'UNAUTHENTICATED',
      );
    case 'PGRST106':
    case '3F000':
      return const S3SmokeFailure(
        'مخطط hasad غير متاح لهذا المشروع. أوقف الفحص.',
        code: 'SCHEMA_NOT_EXPOSED',
      );
    case '42P01':
      return S3SmokeFailure(
        'الجدول اللازم لـ $action غير متاح. أوقف الفحص.',
        code: 'UNDEFINED_TABLE',
      );
    case '401':
    case '403':
      return S3SmokeFailure(
        'رفض الخادم $action على مستوى الطلب (HTTP ${error.code}) دون رمز قاعدة '
        'بيانات. هذا لا يثبت غياب صلاحية أو سياسة RLS؛ شغّل تشخيص '
        'company_settings للقراءة فقط قبل أي تغيير.',
        code: 'HTTP_${error.code}',
      );
    default:
      final serverMessage = _readableServerMessage(error.message);
      return S3SmokeFailure(
        serverMessage == null
            ? 'تعذر $action (رمز الخادم: ${error.code ?? 'غير متاح'}).'
            : 'تعذر $action (رمز الخادم: ${error.code ?? 'غير متاح'} — '
                  '$serverMessage).',
        code: error.code ?? 'READ_FAILED',
      );
  }
}

/// Keeps the PostgREST message (for example
/// `permission denied for table company_settings`) while refusing to render a
/// proxy/HTML body or an unbounded payload in the diagnostic screen.
String? _readableServerMessage(String raw) {
  final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) return null;
  if (collapsed.contains('<') || collapsed.contains('>')) return null;
  return collapsed.length <= 160 ? collapsed : '${collapsed.substring(0, 160)}…';
}

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _maps(Object? response) {
  if (response is! List) return const [];
  return response
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

class S3PostingSmokeController extends ChangeNotifier {
  S3PostingSmokeController(
    this._gateway, {
    required this.selectedCompanyId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The SQL precheck is authoritative; the app-side copy must be recent.
  static const precheckTtl = Duration(minutes: 10);

  final S3PostingSmokeGateway _gateway;
  final DateTime Function() _now;

  /// Company currently selected in the authenticated app shell.
  final String selectedCompanyId;

  S3PrecheckReport? _report;
  S3SmokeFailure? _failure;
  S3PostingOutcome? _outcome;
  bool _runningPrecheck = false;
  bool _posting = false;
  bool _attempted = false;
  bool _attestation = false;

  S3PrecheckReport? get report => _report;
  S3SmokeFailure? get failure => _failure;
  S3PostingOutcome? get outcome => _outcome;
  bool get runningPrecheck => _runningPrecheck;
  bool get posting => _posting;
  bool get attempted => _attempted;
  bool get attestation => _attestation;
  String? get activeProjectRef =>
      S3PostingSmokeContract.projectRefFromUrl(_gateway.activeRestUrl);
  String? get currentUserId => _gateway.currentUserId;
  String? get currentUserEmail => _gateway.currentUserEmail;

  bool get isPrecheckFresh {
    final report = _report;
    if (report == null) return false;
    return _now().difference(report.checkedAt) <= precheckTtl;
  }

  bool get canRunPrecheck =>
      !_runningPrecheck && !_posting && !_attempted;

  bool get canAttest =>
      !_posting &&
      !_attempted &&
      (_report?.passed ?? false) &&
      isPrecheckFresh;

  bool get canPost =>
      canAttest && _attestation && _outcome == null && !_posting;

  void setAttestation(bool value) {
    if (_attestation == value) return;
    _attestation = value;
    notifyListeners();
  }

  Future<void> runPrecheck() async {
    if (!canRunPrecheck) return;
    _runningPrecheck = true;
    _failure = null;
    _outcome = null;
    _attestation = false;
    notifyListeners();

    final checkedAt = _now();
    S3PrecheckReport? report;
    try {
      final activeRef = S3PostingSmokeContract.projectRefFromUrl(
        _gateway.activeRestUrl,
      );
      if (activeRef != S3PostingSmokeContract.projectRef) {
        report = _blockedReport(checkedAt);
        return;
      }

      final userId = _gateway.currentUserId;
      if (userId == null || userId.isEmpty) {
        report = _blockedReport(checkedAt);
        return;
      }

      // Never read the target company while the shell is scoped to another
      // company: the owner authorization names one company and one invoice.
      if (selectedCompanyId != S3PostingSmokeContract.companyId) {
        report = _blockedReport(checkedAt, userId: userId);
        return;
      }

      final membership = await _gateway.fetchMembership(
        userId: userId,
        companyId: S3PostingSmokeContract.companyId,
      );
      if (membership == null) {
        report = _blockedReport(checkedAt, userId: userId);
        return;
      }

      final settings = await _gateway.fetchCompanySettings(
        companyId: S3PostingSmokeContract.companyId,
      );
      if (!S3PostingSmokeContract.isAboAmenSettings(settings)) {
        report = evaluateS3PostingPrecheck(
          selectedCompanyId: selectedCompanyId,
          activeRestUrl: _gateway.activeRestUrl,
          currentUserId: userId,
          currentUserEmail: _gateway.currentUserEmail,
          membership: membership,
          companySettings: settings,
          invoice: null,
          lines: const [],
          productsById: const {},
          stockByProductWarehouse: const {},
          salesPostAllowed: null,
          checkedAt: checkedAt,
        );
        return;
      }

      final invoice = await _gateway.fetchInvoice(
        companyId: S3PostingSmokeContract.companyId,
        documentId: S3PostingSmokeContract.documentId,
      );

      var lines = const <Map<String, dynamic>>[];
      var products = const <String, Map<String, dynamic>>{};
      var stock = const <String, Map<String, dynamic>>{};
      if (invoice != null) {
        lines = await _gateway.fetchLines(
          companyId: S3PostingSmokeContract.companyId,
          documentId: S3PostingSmokeContract.documentId,
        );
        final productIds = lines
            .map((line) => line['product_id'])
            .whereType<String>()
            .toSet()
            .toList(growable: false);
        final productRows = await _gateway.fetchProducts(
          companyId: S3PostingSmokeContract.companyId,
          productIds: productIds,
        );
        products = {
          for (final row in productRows)
            if (row['id'] is String) row['id'] as String: row,
        };
        final stockRows = await _gateway.fetchStockLevels(
          companyId: S3PostingSmokeContract.companyId,
          productIds: productIds,
        );
        stock = {
          for (final row in stockRows)
            '${row['product_id']}|${row['warehouse_id']}': row,
        };
      }

      bool? allowed;
      S3SmokeFailure? permissionFailure;
      try {
        allowed = await _gateway.salesPostAllowed(
          companyId: S3PostingSmokeContract.companyId,
        );
      } on S3SmokeFailure catch (error) {
        permissionFailure = error;
      }

      report = evaluateS3PostingPrecheck(
        selectedCompanyId: selectedCompanyId,
        activeRestUrl: _gateway.activeRestUrl,
        currentUserId: userId,
        currentUserEmail: _gateway.currentUserEmail,
        membership: membership,
        companySettings: settings,
        invoice: invoice,
        lines: lines,
        productsById: products,
        stockByProductWarehouse: stock,
        salesPostAllowed: allowed,
        checkedAt: checkedAt,
      );
      if (permissionFailure != null) {
        report = report.withFailure(
          S3PrecheckCheck(
            key: 'permission',
            label: 'صلاحية sales.post مثبتة من الخادم للمستخدم الحالي',
            passed: false,
            detail: permissionFailure.message,
          ),
        );
      }
    } on S3SmokeFailure catch (error) {
      _failure = error;
      report = _failureReport(checkedAt, error);
    } on Object {
      const error = S3SmokeFailure(
        'تعذر إكمال الفحص الآلي. لم يُنفذ أي كتابة.',
        code: 'PRECHECK_UNAVAILABLE',
      );
      _failure = error;
      report = _failureReport(checkedAt, error);
    } finally {
      _report = report;
      _runningPrecheck = false;
      notifyListeners();
    }
  }

  Future<void> postOnce() async {
    if (_posting || _attempted || _outcome != null) return;
    final report = _report;
    if (report == null || !report.passed || !_attestation) return;
    if (!isPrecheckFresh) {
      _failure = const S3SmokeFailure(
        'انتهت صلاحية الفحص الآلي. أعد تشغيل فحص القراءة فقط قبل أي محاولة.',
        code: 'STALE_PRECHECK',
      );
      notifyListeners();
      return;
    }

    // The single attempt is consumed before the request leaves the client, so
    // no UI path can invoke the RPC a second time.
    _attempted = true;
    _posting = true;
    _failure = null;
    notifyListeners();

    try {
      _outcome = await _gateway.postSalesInvoice(
        companyId: S3PostingSmokeContract.companyId,
        documentId: S3PostingSmokeContract.documentId,
        idempotencyKey: S3PostingSmokeContract.idempotencyKey,
      );
    } on S3SmokeFailure catch (error) {
      _failure = error;
    } on Object {
      _failure = const S3SmokeFailure(
        'تعذر تأكيد نتيجة طلب الترحيل. لا تُعِد المحاولة؛ شغّل فحص ما بعد الترحيل أولاً.',
        code: 'UNCERTAIN',
        outcomeUncertain: true,
      );
    } finally {
      _posting = false;
      notifyListeners();
    }
  }

  S3PrecheckReport _blockedReport(
    DateTime checkedAt, {
    String? userId,
  }) => evaluateS3PostingPrecheck(
    selectedCompanyId: selectedCompanyId,
    activeRestUrl: _gateway.activeRestUrl,
    currentUserId: userId,
    currentUserEmail: userId == null ? null : _gateway.currentUserEmail,
    membership: null,
    companySettings: null,
    invoice: null,
    lines: const [],
    productsById: const {},
    stockByProductWarehouse: const {},
    salesPostAllowed: null,
    checkedAt: checkedAt,
  );

  S3PrecheckReport _failureReport(DateTime checkedAt, S3SmokeFailure error) =>
      S3PrecheckReport(
        checks: [
          S3PrecheckCheck(
            key: 'read',
            label: 'اكتمل الفحص الآلي للقراءة فقط',
            passed: false,
            detail: '${error.message} (${error.code})',
          ),
        ],
        checkedAt: checkedAt,
        activeProjectRef: S3PostingSmokeContract.projectRefFromUrl(
          _gateway.activeRestUrl,
        ),
      );
}
