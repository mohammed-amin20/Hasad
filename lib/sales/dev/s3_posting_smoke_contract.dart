import 'package:hasad_erp_v2/sales/domain/invoice_calculations.dart';

/// Fixed, owner-authorized target of the one-time DEV S3 posting smoke test.
///
/// This file is deliberately free of Supabase imports so every rule below can
/// be unit-tested without a network or a session. Nothing here grants a
/// privilege: the RPC rechecks project data, membership, permission, period and
/// stock on the server.
abstract final class S3PostingSmokeContract {
  static const projectRef = 'sxasnunzspkuwbxiddqd';
  static const companyId = 'aed949e1-9561-4ae6-a44f-31c25e7e3658';
  static const documentId = '86e7a408-479f-4d41-b699-6940cd6b50c8';
  static const idempotencyKey = '9c225844-e45b-48ef-b7a1-a2cc0572036e';
  static const docDate = '2026-10-31';
  static const grossCents = 1000;
  static const taxCents = 0;
  static const netCents = 1000;
  static const expectedPrecheckVerdict = 'READY_FOR_ZERO_TAX_POSTING_TEST';

  /// Exactly the `company_settings` columns the normal Flutter company-context
  /// read is granted on DEV. The `authenticated` role has column-level SELECT
  /// only, not table-level SELECT; asking for `name_en`, `vat_enabled` or
  /// `currency` would make PostgREST return 403 (SQLSTATE 42501).
  static const companySettingsReadColumns = <String>[
    'company_id',
    'display_name',
    'name_ar',
  ];

  /// Compile-time opt-in. Without it the diagnostic never appears in the UI.
  static const enableFlag = 'ENABLE_S3_POSTING_SMOKE';
  static const requested = bool.fromEnvironment(enableFlag);
  static const configuredProjectUrl = String.fromEnvironment('SUPABASE_URL');

  static bool get isEnabled =>
      requested &&
      projectRefFromUrl(configuredProjectUrl) == projectRef;

  /// Extracts the project ref from a Supabase URL or PostgREST URL.
  ///
  /// `https://<ref>.supabase.co` and `https://<ref>.supabase.co/rest/v1` both
  /// yield `<ref>`; anything that does not expose a three-label host yields
  /// `null` so the caller fails closed.
  static String? projectRefFromUrl(String? url) {
    final raw = url?.trim();
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    final labels = uri.host.toLowerCase().split('.');
    if (labels.length < 3 || labels.first.isEmpty) return null;
    return labels.first;
  }

  /// The precheck SQL selects Abo Amen by these exact settings names.
  ///
  /// `name_en` is kept for SQL parity, but the Flutter gateway no longer reads
  /// it: DEV grants `authenticated` only `company_id, display_name, name_ar` on
  /// `company_settings`. A missing field simply cannot match; it never widens
  /// the read.
  static bool isAboAmenSettings(Map<String, dynamic>? settings) {
    if (settings == null) return false;
    for (final field in const ['name_ar', 'name_en', 'display_name']) {
      final raw = settings[field];
      if (raw is! String) continue;
      final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (normalized == 'أبو أمين' || normalized == 'abo amen') return true;
    }
    return false;
  }

  static String? amountText(Object? value) =>
      InvoiceAmount.tryParse('${value ?? ''}')?.toDecimalString();

  static int? amountCents(Object? value) =>
      InvoiceAmount.tryParse('${value ?? ''}')?.cents;

  static int? quantityUnits4(Object? value) =>
      InvoiceQuantity.tryParse('${value ?? ''}')?.units4;

  /// Half-up rounding of `numerator / denominator` for non-negative integers,
  /// matching PostgreSQL `round(numeric, 2)` on the same positive values.
  static int roundHalfUp(int numerator, int denominator) =>
      (numerator + denominator ~/ 2) ~/ denominator;
}

class S3PrecheckCheck {
  const S3PrecheckCheck({
    required this.key,
    required this.label,
    required this.passed,
    required this.detail,
  });

  final String key;
  final String label;
  final bool passed;
  final String detail;
}

class S3SmokeLineEffect {
  const S3SmokeLineEffect({
    required this.lineNo,
    required this.productId,
    required this.warehouseId,
    required this.quantity,
    required this.tracked,
    required this.unitCost,
    required this.cogs,
  });

  final int lineNo;
  final String? productId;
  final String? warehouseId;
  final String quantity;
  final bool tracked;
  final String? unitCost;
  final String cogs;
}

class S3SmokeTarget {
  const S3SmokeTarget({
    required this.companyName,
    required this.invoiceId,
    required this.companyId,
    required this.idempotencyKey,
    required this.docDate,
    required this.net,
    required this.tax,
    required this.gross,
    required this.cogsCents,
    required this.lines,
  });

  final String companyName;
  final String invoiceId;
  final String companyId;
  final String idempotencyKey;
  final String docDate;
  final String net;
  final String tax;
  final String gross;
  final int cogsCents;
  final List<S3SmokeLineEffect> lines;

  String get cogs => InvoiceAmount.fromCents(cogsCents).toDecimalString();

  int get stockedLineCount => lines.where((line) => line.tracked).length;

  /// AR debit + revenue credit, plus the COGS/inventory pair only when the
  /// expected cost is above zero (the documented zero-cost gap).
  int get journalLineCount => 2 + (cogsCents > 0 ? 2 : 0);
}

class S3PrecheckReport {
  const S3PrecheckReport({
    required this.checks,
    required this.checkedAt,
    required this.activeProjectRef,
    this.target,
  });

  final List<S3PrecheckCheck> checks;
  final DateTime checkedAt;
  final String? activeProjectRef;
  final S3SmokeTarget? target;

  bool get passed => checks.isNotEmpty && checks.every((check) => check.passed);

  List<S3PrecheckCheck> get failures =>
      checks.where((check) => !check.passed).toList(growable: false);

  String get verdict => passed
      ? S3PostingSmokeContract.expectedPrecheckVerdict
      : 'BLOCKED_BY_APP_PRECHECK';

  S3PrecheckReport withFailure(S3PrecheckCheck failure) => S3PrecheckReport(
    checks: [...checks.where((check) => check.key != failure.key), failure],
    checkedAt: checkedAt,
    activeProjectRef: activeProjectRef,
    target: target,
  );
}

class S3SmokeFailure implements Exception {
  const S3SmokeFailure(
    this.message, {
    required this.code,
    this.outcomeUncertain = false,
  });

  final String message;
  final String code;

  /// True when the request may or may not have committed. The only safe next
  /// step is the read-only post-verification query, never a retry.
  final bool outcomeUncertain;
}

class S3PostingOutcome {
  const S3PostingOutcome({
    required this.documentNo,
    required this.journalEntryNo,
    required this.replayed,
  });

  final String documentNo;
  final String journalEntryNo;
  final bool replayed;
}

/// Pure, read-only evaluation of the application-side precheck subset.
///
/// The prepared SQL precheck remains authoritative for server-only facts
/// (account mappings, open period, counters and official numbers). This report
/// covers project, session, membership, company name, invoice identity,
/// amounts, date, key, official-number state, lines and stock.
S3PrecheckReport evaluateS3PostingPrecheck({
  required String selectedCompanyId,
  required String activeRestUrl,
  required String? currentUserId,
  required String? currentUserEmail,
  required Map<String, dynamic>? membership,
  required Map<String, dynamic>? companySettings,
  required Map<String, dynamic>? invoice,
  required List<Map<String, dynamic>> lines,
  required Map<String, Map<String, dynamic>> productsById,
  required Map<String, Map<String, dynamic>> stockByProductWarehouse,
  required bool? salesPostAllowed,
  DateTime? checkedAt,
}) {
  final checks = <S3PrecheckCheck>[];
  final activeProjectRef = S3PostingSmokeContract.projectRefFromUrl(
    activeRestUrl,
  );

  checks.add(
    S3PrecheckCheck(
      key: 'project',
      label: 'مشروع Supabase النشط هو المشروع المصرح به',
      passed: activeProjectRef == S3PostingSmokeContract.projectRef,
      detail: 'المشروع النشط: ${activeProjectRef ?? 'غير معروف'}',
    ),
  );

  final hasSession = currentUserId != null && currentUserId.isNotEmpty;
  checks.add(
    S3PrecheckCheck(
      key: 'session',
      label: 'توجد جلسة مستخدم حقيقية',
      passed: hasSession,
      detail: hasSession
          ? 'المستخدم: ${currentUserEmail ?? currentUserId}'
          : 'لا توجد جلسة دخول صالحة.',
    ),
  );

  final membershipOk =
      membership != null &&
      membership['user_id'] == currentUserId &&
      membership['company_id'] == S3PostingSmokeContract.companyId &&
      membership['status'] == 'active';
  checks.add(
    S3PrecheckCheck(
      key: 'membership',
      label: 'عضوية نشطة للمستخدم الحالي في الشركة المصرح بها',
      passed: membershipOk,
      detail: membershipOk
          ? 'العضوية نشطة في الشركة المصرح بها.'
          : 'لم تُثبت عضوية نشطة في الشركة المصرح بها.',
    ),
  );

  final companyName = _companyName(companySettings);
  final companyOk =
      selectedCompanyId == S3PostingSmokeContract.companyId &&
      S3PostingSmokeContract.isAboAmenSettings(companySettings);
  checks.add(
    S3PrecheckCheck(
      key: 'company',
      label: 'الشركة المختارة هي Abo Amen والشركة المصرح بها',
      passed: companyOk,
      detail: companyOk
          ? 'الشركة: $companyName'
          : 'الشركة المختارة: $selectedCompanyId — الاسم المسجل: '
                '${companyName.isEmpty ? 'غير متاح' : companyName}',
    ),
  );

  final invoiceOk =
      invoice != null &&
      invoice['id'] == S3PostingSmokeContract.documentId &&
      invoice['company_id'] == S3PostingSmokeContract.companyId &&
      invoice['doc_kind'] == 'invoice';
  checks.add(
    S3PrecheckCheck(
      key: 'invoice_identity',
      label: 'الفاتورة هي نفسها الفاتورة المصرح بها',
      passed: invoiceOk,
      detail: invoiceOk
          ? 'معرّف الفاتورة: ${S3PostingSmokeContract.documentId}'
          : 'الفاتورة غير موجودة أو لا تطابق المعرّف المصرح به.',
    ),
  );

  final status = invoice?['status'];
  checks.add(
    S3PrecheckCheck(
      key: 'invoice_status',
      label: 'الفاتورة ما زالت مسودة قابلة للترحيل',
      passed: status == 'draft',
      detail: 'الحالة الحالية: ${status ?? 'غير متاحة'}',
    ),
  );

  final netCents = S3PostingSmokeContract.amountCents(invoice?['net']);
  final taxCents = S3PostingSmokeContract.amountCents(invoice?['tax']);
  final grossCents = S3PostingSmokeContract.amountCents(invoice?['gross']);
  final amountsOk =
      netCents == S3PostingSmokeContract.netCents &&
      taxCents == S3PostingSmokeContract.taxCents &&
      grossCents == S3PostingSmokeContract.grossCents;
  checks.add(
    S3PrecheckCheck(
      key: 'amounts',
      label: 'الصافي 10.00 والضريبة 0.00 والإجمالي 10.00',
      passed: amountsOk,
      detail:
          'الصافي: ${S3PostingSmokeContract.amountText(invoice?['net']) ?? '?'} — '
          'الضريبة: ${S3PostingSmokeContract.amountText(invoice?['tax']) ?? '?'} — '
          'الإجمالي: ${S3PostingSmokeContract.amountText(invoice?['gross']) ?? '?'}',
    ),
  );

  final docDate = '${invoice?['doc_date'] ?? ''}';
  checks.add(
    S3PrecheckCheck(
      key: 'doc_date',
      label: 'تاريخ الفاتورة هو 2026-10-31 داخل فترة أكتوبر 2026',
      passed: docDate == S3PostingSmokeContract.docDate,
      detail: 'التاريخ: ${docDate.isEmpty ? 'غير متاح' : docDate}',
    ),
  );

  final idempotencyOk =
      '${invoice?['idempotency_key'] ?? ''}' ==
      S3PostingSmokeContract.idempotencyKey;
  checks.add(
    S3PrecheckCheck(
      key: 'idempotency',
      label: 'مفتاح التكرار يطابق المفتاح المصرح به',
      passed: idempotencyOk,
      detail: idempotencyOk
          ? S3PostingSmokeContract.idempotencyKey
          : 'المفتاح في قاعدة البيانات لا يطابق التصريح.',
    ),
  );

  final noOfficialNumber =
      invoice != null &&
      invoice['doc_no'] == null &&
      invoice['posted_at'] == null;
  checks.add(
    S3PrecheckCheck(
      key: 'official_number',
      label: 'لا يوجد رقم رسمي أو أثر ترحيل سابق',
      passed: noOfficialNumber,
      detail: invoice == null
          ? 'لا توجد فاتورة للتحقق.'
          : 'الرقم الرسمي: ${invoice['doc_no'] ?? 'لا يوجد'} — '
                'وقت الترحيل: ${invoice['posted_at'] ?? 'لا يوجد'}',
    ),
  );

  final lineReport = _evaluateLines(
    invoice: invoice,
    lines: lines,
    productsById: productsById,
  );
  checks.add(lineReport.structureCheck);
  checks.add(lineReport.productCheck);

  final stockReport = _evaluateStock(
    lines: lines,
    productsById: productsById,
    stockByProductWarehouse: stockByProductWarehouse,
  );
  checks.add(stockReport.check);

  final permissionOk = salesPostAllowed == true;
  checks.add(
    S3PrecheckCheck(
      key: 'permission',
      label: 'صلاحية sales.post مثبتة من الخادم للمستخدم الحالي',
      passed: permissionOk,
      detail: permissionOk
          ? 'hasad.sales_posting_allowed أعادت true.'
          : salesPostAllowed == false
          ? 'hasad.sales_posting_allowed أعادت false.'
          : 'تعذر إثبات الصلاحية من الخادم.',
    ),
  );

  final target = invoiceOk
      ? S3SmokeTarget(
          companyName: companyName,
          invoiceId: S3PostingSmokeContract.documentId,
          companyId: S3PostingSmokeContract.companyId,
          idempotencyKey: S3PostingSmokeContract.idempotencyKey,
          docDate: docDate,
          net: S3PostingSmokeContract.amountText(invoice['net']) ?? '?',
          tax: S3PostingSmokeContract.amountText(invoice['tax']) ?? '?',
          gross: S3PostingSmokeContract.amountText(invoice['gross']) ?? '?',
          cogsCents: stockReport.cogsCents,
          lines: stockReport.lines,
        )
      : null;

  return S3PrecheckReport(
    checks: checks,
    checkedAt: checkedAt ?? DateTime.now(),
    activeProjectRef: activeProjectRef,
    target: target,
  );
}

String _companyName(Map<String, dynamic>? settings) {
  if (settings == null) return '';
  for (final field in const ['display_name', 'name_ar', 'name_en']) {
    final value = settings[field];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}

class _LineEvaluation {
  const _LineEvaluation({required this.structureCheck, required this.productCheck});
  final S3PrecheckCheck structureCheck;
  final S3PrecheckCheck productCheck;
}

_LineEvaluation _evaluateLines({
  required Map<String, dynamic>? invoice,
  required List<Map<String, dynamic>> lines,
  required Map<String, Map<String, dynamic>> productsById,
}) {
  var structureOk = invoice != null && lines.isNotEmpty;
  var productsOk = invoice != null && lines.isNotEmpty;
  final problems = <String>[];

  final seenLineNumbers = <int>{};
  var netSum = 0;
  var taxSum = 0;
  var grossSum = 0;

  for (final line in lines) {
    final lineNo = int.tryParse('${line['line_no'] ?? ''}');
    final companyId = '${line['company_id'] ?? ''}';
    final documentId = '${line['document_id'] ?? ''}';
    final quantity = S3PostingSmokeContract.quantityUnits4(line['qty']);
    final lineNet = S3PostingSmokeContract.amountCents(line['net']);
    final lineTax = S3PostingSmokeContract.amountCents(line['tax']);
    final lineGross = S3PostingSmokeContract.amountCents(line['gross']);
    final productId = line['product_id'] is String
        ? line['product_id'] as String
        : null;

    if (lineNo == null ||
        lineNo < 1 ||
        !seenLineNumbers.add(lineNo) ||
        companyId != S3PostingSmokeContract.companyId ||
        documentId != S3PostingSmokeContract.documentId) {
      structureOk = false;
      problems.add('بند بمعرّف أو ترقيم غير صالح');
      continue;
    }
    if (quantity == null || quantity <= 0) {
      structureOk = false;
      problems.add('بند $lineNo بكمية غير صالحة');
    }
    if (lineNet == null || lineTax == null || lineGross == null) {
      structureOk = false;
      problems.add('بند $lineNo بمبالغ غير صالحة');
    } else {
      netSum += lineNet;
      taxSum += lineTax;
      grossSum += lineGross;
      if (lineGross != lineNet + lineTax) {
        structureOk = false;
        problems.add('بند $lineNo لا يوازن صافي + ضريبة = إجمالي');
      }
    }

    final product = productId == null ? null : productsById[productId];
    if (product == null ||
        product['company_id'] != S3PostingSmokeContract.companyId ||
        product['is_active'] != true) {
      productsOk = false;
      problems.add('بند $lineNo بصنف غير متاح أو غير مفعّل');
    }
  }

  if (lines.isNotEmpty) {
    final numbers = seenLineNumbers.toList()..sort();
    if (numbers.isEmpty || numbers.first != 1 || numbers.last != lines.length) {
      structureOk = false;
      problems.add('ترقيم البنود غير متصل من 1 إلى ${lines.length}');
    }
  }

  final netCents = S3PostingSmokeContract.amountCents(invoice?['net']);
  final taxCents = S3PostingSmokeContract.amountCents(invoice?['tax']);
  final grossCents = S3PostingSmokeContract.amountCents(invoice?['gross']);
  if (lines.isNotEmpty &&
      (netSum != netCents || taxSum != taxCents || grossSum != grossCents)) {
    structureOk = false;
    problems.add('مجموع البنود لا يطابق إجماليات الفاتورة');
  }

  if (lines.isNotEmpty &&
      lines.any(
        (line) =>
            S3PostingSmokeContract.amountCents(line['tax']) != 0 ||
            S3PostingSmokeContract.amountCents(line['net']) == null ||
            S3PostingSmokeContract.amountCents(line['gross']) == null,
      )) {
    structureOk = false;
  }

  final uniqueProblems = problems.toSet().toList(growable: false);
  return _LineEvaluation(
    structureCheck: S3PrecheckCheck(
      key: 'lines',
      label: 'بنود الفاتورة مكتملة ومتوازنة',
      passed: structureOk && uniqueProblems.isEmpty,
      detail: structureOk && uniqueProblems.isEmpty
          ? '${lines.length} بنداً؛ المجاميع تطابق رأس الفاتورة.'
          : uniqueProblems.isEmpty
          ? 'بنود الفاتورة غير مكتملة.'
          : uniqueProblems.join('؛ '),
    ),
    productCheck: S3PrecheckCheck(
      key: 'products',
      label: 'كل بند يشير إلى صنف مفعّل في نفس الشركة',
      passed: productsOk,
      detail: productsOk
          ? 'كل الأصناف متاحة ومفعّلة.'
          : 'يوجد بند بصنف غير متاح أو غير مفعّل.',
    ),
  );
}

class _StockEvaluation {
  const _StockEvaluation({
    required this.check,
    required this.cogsCents,
    required this.lines,
  });

  final S3PrecheckCheck check;
  final int cogsCents;
  final List<S3SmokeLineEffect> lines;
}

_StockEvaluation _evaluateStock({
  required List<Map<String, dynamic>> lines,
  required Map<String, Map<String, dynamic>> productsById,
  required Map<String, Map<String, dynamic>> stockByProductWarehouse,
}) {
  var ok = lines.isNotEmpty;
  var cogsCents = 0;
  final effects = <S3SmokeLineEffect>[];
  final shortages = <String>[];

  for (final line in lines) {
    final lineNo = int.tryParse('${line['line_no'] ?? ''}') ?? 0;
    final productId = line['product_id'] is String
        ? line['product_id'] as String
        : null;
    final warehouseId = line['warehouse_id'] is String
        ? line['warehouse_id'] as String
        : null;
    final quantityUnits4 = S3PostingSmokeContract.quantityUnits4(line['qty']);
    final product = productId == null ? null : productsById[productId];
    final tracked = product?['track_inventory'] == true;

    var lineCogs = 0;
    String? unitCost;

    if (tracked) {
      final stock = stockByProductWarehouse['$productId|$warehouseId'];
      final availableUnits4 = S3PostingSmokeContract.quantityUnits4(
        stock?['qty'],
      );
      final costCents = S3PostingSmokeContract.amountCents(
        stock?['last_unit_cost'],
      );
      if (warehouseId == null ||
          quantityUnits4 == null ||
          availableUnits4 == null ||
          costCents == null ||
          availableUnits4 < quantityUnits4) {
        ok = false;
        shortages.add(
          'البند $lineNo: المتاح '
          '${stock?['qty'] ?? 'غير متاح'} والمطلوب '
          '${line['qty'] ?? '?'}',
        );
      } else {
        unitCost = InvoiceAmount.fromCents(costCents).toDecimalString();
        lineCogs = S3PostingSmokeContract.roundHalfUp(
          quantityUnits4 * costCents,
          10000,
        );
        cogsCents += lineCogs;
      }
    }

    effects.add(
      S3SmokeLineEffect(
        lineNo: lineNo,
        productId: productId,
        warehouseId: warehouseId,
        quantity: S3PostingSmokeContract.quantityUnits4(line['qty']) == null
            ? '?'
            : InvoiceQuantity.tryParse(
                '${line['qty']}',
              )!.toDecimalString(),
        tracked: tracked,
        unitCost: unitCost,
        cogs: InvoiceAmount.fromCents(lineCogs).toDecimalString(),
      ),
    );
  }

  final trackedCount = effects.where((line) => line.tracked).length;
  return _StockEvaluation(
    check: S3PrecheckCheck(
      key: 'stock',
      label: 'المخزون المتاح يكفي لكل بند مخزني',
      passed: ok,
      detail: ok
          ? '$trackedCount بنداً مخزنياً؛ الأرصدة كافية.'
          : shortages.isEmpty
          ? 'تعذر التحقق من كفاية المخزون.'
          : shortages.join('؛ '),
    ),
    cogsCents: cogsCents,
    lines: effects,
  );
}
