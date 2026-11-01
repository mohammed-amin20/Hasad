import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/sales/dev/s3_posting_smoke_contract.dart';
import 'package:hasad_erp_v2/sales/dev/s3_posting_smoke_screen.dart';
import 'package:hasad_erp_v2/sales/dev/s3_posting_smoke_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('S3 posting smoke contract helpers', () {
    test('extracts the project ref from a Supabase or PostgREST URL', () {
      expect(
        S3PostingSmokeContract.projectRefFromUrl(
          'https://sxasnunzspkuwbxiddqd.supabase.co',
        ),
        'sxasnunzspkuwbxiddqd',
      );
      expect(
        S3PostingSmokeContract.projectRefFromUrl(
          'https://sxasnunzspkuwbxiddqd.supabase.co/rest/v1',
        ),
        'sxasnunzspkuwbxiddqd',
      );
      expect(
        S3PostingSmokeContract.projectRefFromUrl(
          'https://otherref.supabase.co/rest/v1',
        ),
        'otherref',
      );
      expect(S3PostingSmokeContract.projectRefFromUrl(''), isNull);
      expect(S3PostingSmokeContract.projectRefFromUrl('not a url'), isNull);
      expect(
        S3PostingSmokeContract.projectRefFromUrl('https://supabase.co'),
        isNull,
      );
    });

    test('matches Abo Amen by the same settings names as the SQL precheck', () {
      expect(
        S3PostingSmokeContract.isAboAmenSettings({'name_ar': 'أبو أمين'}),
        isTrue,
      );
      expect(
        S3PostingSmokeContract.isAboAmenSettings({'name_en': 'Abo Amen'}),
        isTrue,
      );
      expect(
        S3PostingSmokeContract.isAboAmenSettings({'display_name': '  ABO   AMEN '}),
        isTrue,
      );
      expect(
        S3PostingSmokeContract.isAboAmenSettings({'name_ar': 'شركة أخرى'}),
        isFalse,
      );
      expect(S3PostingSmokeContract.isAboAmenSettings(null), isFalse);
    });

    test('reads only the company_settings columns granted to authenticated', () {
      expect(S3PostingSmokeContract.companySettingsReadColumns, const [
        'company_id',
        'display_name',
        'name_ar',
      ]);
      expect(
        S3PostingSmokeContract.companySettingsReadColumns,
        isNot(contains('name_en')),
      );
      expect(
        S3PostingSmokeContract.companySettingsReadColumns,
        isNot(contains('vat_enabled')),
      );
      expect(
        S3PostingSmokeContract.companySettingsReadColumns,
        isNot(contains('currency')),
      );
    });
  });

  group('S3 posting smoke precheck', () {
    test('passes the authorized ready invoice and computes expected effects', () async {
      final gateway = _FakeGateway();
      final report = await _runReport(gateway);

      expect(report.passed, isTrue, reason: _failures(report));
      expect(report.verdict, S3PostingSmokeContract.expectedPrecheckVerdict);
      expect(report.activeProjectRef, S3PostingSmokeContract.projectRef);
      expect(report.target, isNotNull);
      expect(report.target!.cogs, '7.00');
      expect(report.target!.journalLineCount, 4);
      expect(report.target!.stockedLineCount, 1);
      expect(report.target!.lines.single.unitCost, '3.50');
      expect(report.target!.lines.single.cogs, '7.00');
    });

    test('blocks on a different active project before reading company data', () async {
      final gateway = _FakeGateway()
        ..restUrl = 'https://otherref.supabase.co/rest/v1';
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'project').passed, isFalse);
      expect(gateway.membershipReads, 0);
      expect(gateway.settingsReads, 0);
      expect(gateway.invoiceReads, 0);
      expect(gateway.permissionCalls, 0);
    });

    test('blocks when no real session exists and performs no reads', () async {
      final gateway = _FakeGateway()..userId = null;
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'session').passed, isFalse);
      expect(gateway.membershipReads, 0);
      expect(gateway.invoiceReads, 0);
    });

    test('blocks when the shell is scoped to another company before reads', () async {
      final gateway = _FakeGateway();
      final report = await _runReport(
        gateway,
        selectedCompanyId: '11111111-1111-4111-8111-111111111111',
      );

      expect(report.passed, isFalse);
      expect(_check(report, 'company').passed, isFalse);
      expect(gateway.membershipReads, 0);
      expect(gateway.invoiceReads, 0);
    });

    test('blocks with no active membership in the authorized company', () async {
      final gateway = _FakeGateway()..membership = null;
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'membership').passed, isFalse);
      expect(gateway.settingsReads, 0);
      expect(gateway.invoiceReads, 0);
    });

    test('blocks when the company settings name is not Abo Amen', () async {
      final gateway = _FakeGateway()
        ..settings = {
          'company_id': S3PostingSmokeContract.companyId,
          'name_ar': 'شركة أخرى',
          'name_en': 'Other Company',
          'display_name': null,
          'vat_enabled': false,
          'currency': 'ILS',
        };
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'company').passed, isFalse);
      expect(gateway.invoiceReads, 0);
      expect(gateway.permissionCalls, 0);
    });

    test('blocks when the invoice is no longer a draft', () async {
      final gateway = _FakeGateway()
        ..invoice = {..._invoice(), 'status': 'posted'};
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'invoice_status').passed, isFalse);
    });

    test('blocks when gross or tax no longer match the authorization', () async {
      final grossGateway = _FakeGateway()
        ..invoice = {..._invoice(), 'gross': '10.01', 'net': '10.01'};
      final grossReport = await _runReport(grossGateway);
      expect(grossReport.passed, isFalse);
      expect(_check(grossReport, 'amounts').passed, isFalse);

      final taxGateway = _FakeGateway()
        ..invoice = {..._invoice(), 'tax': '1.00', 'net': '9.00'};
      final taxReport = await _runReport(taxGateway);
      expect(taxReport.passed, isFalse);
      expect(_check(taxReport, 'amounts').passed, isFalse);
    });

    test('blocks when the date is not 2026-10-31', () async {
      final gateway = _FakeGateway()
        ..invoice = {..._invoice(), 'doc_date': '2026-11-01'};
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'doc_date').passed, isFalse);
    });

    test('blocks when the idempotency key differs from the authorization', () async {
      final gateway = _FakeGateway()
        ..invoice = {
          ..._invoice(),
          'idempotency_key': '11111111-1111-4111-8111-111111111111',
        };
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'idempotency').passed, isFalse);
    });

    test('blocks when an official number or posted timestamp already exists', () async {
      final gateway = _FakeGateway()
        ..invoice = {
          ..._invoice(),
          'doc_no': 'SI-2026-0001',
          'posted_at': '2026-10-31T10:00:00Z',
        };
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'official_number').passed, isFalse);
    });

    test('blocks when stock is short for a stocked line', () async {
      final gateway = _FakeGateway()
        ..stock = [
          {..._stock().first, 'qty': '1.0000'},
        ];
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'stock').passed, isFalse);
      expect(_check(report, 'stock').detail, contains('المطلوب 2.0000'));
    });

    test('blocks when a line product is inactive', () async {
      final gateway = _FakeGateway()
        ..products = [
          {..._product().first, 'is_active': false},
        ];
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'products').passed, isFalse);
    });

    test('blocks when the server permission probe returns false', () async {
      final gateway = _FakeGateway()..allowed = false;
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'permission').passed, isFalse);
      expect(_check(report, 'permission').detail, contains('false'));
    });

    test('blocks when the server permission probe fails', () async {
      final gateway = _FakeGateway()
        ..permissionFailure = const S3SmokeFailure(
          'تعذر فحص الصلاحية',
          code: 'DENIED',
        );
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'permission').passed, isFalse);
      expect(_check(report, 'permission').detail, contains('تعذر فحص الصلاحية'));
    });

    test('blocks when lines or totals do not match the invoice header', () async {
      final gateway = _FakeGateway()
        ..lines = [
          {..._line(), 'qty': '3.0000', 'net': '15.00', 'gross': '15.00'},
        ];
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(_check(report, 'lines').passed, isFalse);
    });

    test('reports a read failure without claiming a ready verdict', () async {
      final gateway = _FakeGateway()
        ..readFailure = const S3SmokeFailure(
          'لا توجد صلاحية قراءة',
          code: 'DENIED',
        );
      final report = await _runReport(gateway);

      expect(report.passed, isFalse);
      expect(report.checks.single.key, 'read');
      expect(report.verdict, isNot(S3PostingSmokeContract.expectedPrecheckVerdict));
    });
  });

  group('S3 posting smoke one-shot controller', () {
    test('never posts without a passing precheck and human attestation', () async {
      final gateway = _FakeGateway();
      final controller = _controller(gateway);

      await controller.postOnce();
      expect(gateway.postCalls, 0);

      await controller.runPrecheck();
      expect(controller.report!.passed, isTrue);
      await controller.postOnce();
      expect(gateway.postCalls, 0);

      controller.setAttestation(true);
      await controller.postOnce();
      expect(gateway.postCalls, 1);
      expect(controller.outcome!.documentNo, 'SI-2026-0001');
      expect(controller.attempted, isTrue);
    });

    test('consumes exactly one attempt even if invoked repeatedly', () async {
      final gateway = _FakeGateway();
      final controller = _controller(gateway);
      await controller.runPrecheck();
      controller.setAttestation(true);

      await Future.wait([
        controller.postOnce(),
        controller.postOnce(),
      ]);
      await controller.postOnce();

      expect(gateway.postCalls, 1);
    });

    test('does not post when the precheck failed', () async {
      final gateway = _FakeGateway()..allowed = false;
      final controller = _controller(gateway);
      await controller.runPrecheck();
      controller.setAttestation(true);

      await controller.postOnce();

      expect(controller.report!.passed, isFalse);
      expect(gateway.postCalls, 0);
    });

    test('keeps a known server rejection as a single attempt', () async {
      final gateway = _FakeGateway()
        ..postFailure = const S3SmokeFailure(
          'رفض الخادم الترحيل: المخزون غير كافٍ.',
          code: 'STOCK_INSUFFICIENT',
        );
      final controller = _controller(gateway);
      await controller.runPrecheck();
      controller.setAttestation(true);

      await controller.postOnce();
      await controller.postOnce();

      expect(gateway.postCalls, 1);
      expect(controller.outcome, isNull);
      expect(controller.failure!.code, 'STOCK_INSUFFICIENT');
      expect(controller.attempted, isTrue);
    });

    test('treats an uncertain outcome as final and never retries', () async {
      final gateway = _FakeGateway()
        ..postFailure = const S3SmokeFailure(
          'انتهت المهلة دون رد مؤكد.',
          code: 'TIMEOUT',
          outcomeUncertain: true,
        );
      final controller = _controller(gateway);
      await controller.runPrecheck();
      controller.setAttestation(true);

      await controller.postOnce();
      await controller.postOnce();

      expect(gateway.postCalls, 1);
      expect(controller.failure!.outcomeUncertain, isTrue);
      expect(controller.outcome, isNull);
      expect(controller.attempted, isTrue);
    });

    test('rejects a stale precheck without consuming the single attempt', () async {
      var now = DateTime(2026, 11, 1, 9);
      final gateway = _FakeGateway();
      final controller = _controller(gateway, now: () => now);
      await controller.runPrecheck();
      controller.setAttestation(true);

      now = now.add(const Duration(minutes: 11));
      await controller.postOnce();

      expect(gateway.postCalls, 0);
      expect(controller.failure!.code, 'STALE_PRECHECK');
      expect(controller.attempted, isFalse);

      await controller.runPrecheck();
      controller.setAttestation(true);
      await controller.postOnce();
      expect(gateway.postCalls, 1);
    });
  });

  group('S3 posting smoke screen', () {
    testWidgets('requires the attestation and a second deliberate click', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final gateway = _FakeGateway();
      final now = DateTime(2026, 11, 1, 9);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: S3PostingSmokeScreen(
                  selectedCompanyId: S3PostingSmokeContract.companyId,
                  gateway: gateway,
                  now: () => now,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('s3-smoke-post')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('s3-smoke-precheck')));
      await tester.pumpAndSettle();
      expect(find.textContaining(S3PostingSmokeContract.expectedPrecheckVerdict), findsWidgets);

      await tester.ensureVisible(
        find.byKey(const ValueKey('s3-smoke-attestation')),
      );
      await tester.tap(find.byKey(const ValueKey('s3-smoke-attestation')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const ValueKey('s3-smoke-post')));
      await tester.tap(find.byKey(const ValueKey('s3-smoke-post')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('s3-smoke-post-confirm')), findsOneWidget);
      expect(gateway.postCalls, 0);

      await tester.ensureVisible(
        find.byKey(const ValueKey('s3-smoke-post-confirm')),
      );
      await tester.tap(find.byKey(const ValueKey('s3-smoke-post-confirm')));
      await tester.pumpAndSettle();

      expect(gateway.postCalls, 1);
      expect(find.textContaining('SI-2026-0001'), findsWidgets);
      final postButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('s3-smoke-post')),
      );
      expect(postButton.onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('s3-smoke-post')));
      await tester.pumpAndSettle();
      expect(gateway.postCalls, 1);
      expect(find.byKey(const ValueKey('s3-smoke-post-confirm')), findsNothing);
    });
  });

  group('S3 posting smoke read failure mapping', () {
    const action = 'قراءة إعدادات الشركة';

    test('maps a PostgREST privilege denial to DENIED', () {
      final failure = mapS3ReadFailure(
        const PostgrestException(
          message: 'permission denied for table company_settings',
          code: '42501',
        ),
        action,
      );

      expect(failure.code, 'DENIED');
      expect(failure.outcomeUncertain, isFalse);
    });

    test('does not read a bare HTTP 403 as a missing RLS policy', () {
      final failure = mapS3ReadFailure(
        const PostgrestException(message: 'Forbidden', code: '403'),
        action,
      );

      expect(failure.code, 'HTTP_403');
      expect(failure.message, contains('403'));
      expect(failure.message, contains('RLS'));
      expect(failure.message, isNot(contains('سياسة RLS ناقصة')));
    });

    test('keeps a plain server message and drops an HTML proxy body', () {
      final postgrest = mapS3ReadFailure(
        const PostgrestException(
          message: 'permission denied for table company_settings',
          code: 'PGRST999',
        ),
        action,
      );
      expect(postgrest.code, 'PGRST999');
      expect(postgrest.message, contains('permission denied for table'));

      final html = mapS3ReadFailure(
        const PostgrestException(
          message: '<html><body>blocked</body></html>',
          code: '500',
        ),
        action,
      );
      expect(html.code, '500');
      expect(html.message, isNot(contains('blocked')));
      expect(html.message, isNot(contains('html')));
    });
  });
}

S3PostingSmokeController _controller(
  _FakeGateway gateway, {
  String? selectedCompanyId,
  DateTime Function()? now,
}) => S3PostingSmokeController(
  gateway,
  selectedCompanyId:
      selectedCompanyId ?? S3PostingSmokeContract.companyId,
  now: now ?? () => DateTime(2026, 11, 1, 9),
);

Future<S3PrecheckReport> _runReport(
  _FakeGateway gateway, {
  String? selectedCompanyId,
}) async {
  final controller = _controller(
    gateway,
    selectedCompanyId: selectedCompanyId,
  );
  await controller.runPrecheck();
  return controller.report!;
}

S3PrecheckCheck _check(S3PrecheckReport report, String key) =>
    report.checks.firstWhere((check) => check.key == key);

String _failures(S3PrecheckReport report) => report.failures
    .map((check) => '${check.key}: ${check.detail}')
    .join(' | ');

Map<String, dynamic> _invoice() => {
  'id': S3PostingSmokeContract.documentId,
  'company_id': S3PostingSmokeContract.companyId,
  'doc_kind': 'invoice',
  'status': 'draft',
  'party_id': 'party-1',
  'doc_date': '2026-10-31',
  'vat_mode': 'exclusive',
  'doc_type_id': 'doctype-1',
  'fiscal_year_id': 'fy-1',
  'doc_no': null,
  'idempotency_key': S3PostingSmokeContract.idempotencyKey,
  'net': '10.00',
  'tax': '0.00',
  'gross': '10.00',
  'posted_at': null,
};

Map<String, dynamic> _line() => {
  'id': 'line-1',
  'company_id': S3PostingSmokeContract.companyId,
  'document_id': S3PostingSmokeContract.documentId,
  'line_no': 1,
  'product_id': 'product-1',
  'warehouse_id': 'warehouse-1',
  'qty': '2.0000',
  'unit_price': '5.00',
  'discount_amount': '0.00',
  'tax_rate': '0.00',
  'net': '10.00',
  'tax': '0.00',
  'gross': '10.00',
};

List<Map<String, dynamic>> _product() => [
  {
    'id': 'product-1',
    'company_id': S3PostingSmokeContract.companyId,
    'track_inventory': true,
    'is_active': true,
  },
];

List<Map<String, dynamic>> _stock() => [
  {
    'company_id': S3PostingSmokeContract.companyId,
    'product_id': 'product-1',
    'warehouse_id': 'warehouse-1',
    'qty': '5.0000',
    'last_unit_cost': '3.50',
  },
];

class _FakeGateway implements S3PostingSmokeGateway {
  String restUrl =
      'https://${S3PostingSmokeContract.projectRef}.supabase.co/rest/v1';
  String? userId = 'user-1';
  String? userEmail = 'owner@example.test';
  Map<String, dynamic>? membership = {
    'company_id': S3PostingSmokeContract.companyId,
    'user_id': 'user-1',
    'is_owner': true,
    'status': 'active',
  };
  Map<String, dynamic>? settings = {
    'company_id': S3PostingSmokeContract.companyId,
    'name_ar': 'أبو أمين',
    'name_en': 'Abo Amen',
    'display_name': null,
    'vat_enabled': false,
    'currency': 'ILS',
  };
  Map<String, dynamic>? invoice = _invoice();
  List<Map<String, dynamic>> lines = [_line()];
  List<Map<String, dynamic>> products = _product();
  List<Map<String, dynamic>> stock = _stock();
  bool? allowed = true;
  S3SmokeFailure? permissionFailure;
  S3SmokeFailure? readFailure;
  S3SmokeFailure? postFailure;
  S3PostingOutcome outcome = const S3PostingOutcome(
    documentNo: 'SI-2026-0001',
    journalEntryNo: 'JE-2026-0001',
    replayed: false,
  );

  int membershipReads = 0;
  int settingsReads = 0;
  int invoiceReads = 0;
  int lineReads = 0;
  int productReads = 0;
  int stockReads = 0;
  int permissionCalls = 0;
  int postCalls = 0;

  @override
  String get activeRestUrl => restUrl;

  @override
  String? get currentUserId => userId;

  @override
  String? get currentUserEmail => userEmail;

  @override
  Future<Map<String, dynamic>?> fetchMembership({
    required String userId,
    required String companyId,
  }) async {
    _throwReadFailure();
    membershipReads++;
    return membership;
  }

  @override
  Future<Map<String, dynamic>?> fetchCompanySettings({
    required String companyId,
  }) async {
    _throwReadFailure();
    settingsReads++;
    return settings;
  }

  @override
  Future<Map<String, dynamic>?> fetchInvoice({
    required String companyId,
    required String documentId,
  }) async {
    _throwReadFailure();
    invoiceReads++;
    return invoice;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchLines({
    required String companyId,
    required String documentId,
  }) async {
    _throwReadFailure();
    lineReads++;
    return lines;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchProducts({
    required String companyId,
    required List<String> productIds,
  }) async {
    _throwReadFailure();
    productReads++;
    return products
        .where((product) => productIds.contains(product['id']))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStockLevels({
    required String companyId,
    required List<String> productIds,
  }) async {
    _throwReadFailure();
    stockReads++;
    return stock
        .where((row) => productIds.contains(row['product_id']))
        .toList(growable: false);
  }

  @override
  Future<bool> salesPostAllowed({required String companyId}) async {
    _throwReadFailure();
    permissionCalls++;
    final failure = permissionFailure;
    if (failure != null) throw failure;
    return allowed ?? false;
  }

  @override
  Future<S3PostingOutcome> postSalesInvoice({
    required String companyId,
    required String documentId,
    required String idempotencyKey,
  }) async {
    postCalls++;
    final failure = postFailure;
    if (failure != null) throw failure;
    return outcome;
  }

  void _throwReadFailure() {
    final failure = readFailure;
    if (failure != null) throw failure;
  }
}
