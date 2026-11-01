import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/customers/domain/customer.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:hasad_erp_v2/sales/data/sales_repository.dart';
import 'package:hasad_erp_v2/sales/domain/invoice_calculations.dart';
import 'package:hasad_erp_v2/sales/domain/sales_invoice.dart';
import 'package:hasad_erp_v2/sales/presentation/sales_invoices_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  // A 1280x720 window at 100% scaling, and the same window as Windows reports
  // it at 125% scaling. The second one is the regression case that used to hide
  // every save failure below the visible dialog area.
  const desktop = Size(1280, 720);
  const scaledLaptop = Size(1024, 576);

  group('sales invoice editor save feedback', () {
    testWidgets('invalid form shows field and summary errors inside the '
        'visible dialog area on a 125% scaled window', (tester) async {
      final repository = _FakeSalesRepository();
      await _openEditor(tester, repository, size: scaledLaptop);

      await tester.tap(find.text('حفظ المسودة'));
      await tester.pumpAndSettle();

      expect(find.text('اختر العميل.'), findsOneWidget);
      expectVisibleOnScreen(tester, find.text('اختر العميل.'));
      expectVisibleOnScreen(
        tester,
        find.text('راجع الحقول المميزة قبل حفظ المسودة.'),
      );
      expect(repository.saveCalls, 0);
    });

    testWidgets('save button invokes the repository once and closes the '
        'editor on success', (tester) async {
      final repository = _FakeSalesRepository();
      await _openScreen(tester, repository, size: desktop);
      await tester.tap(find.text('إنشاء فاتورة').first);
      await tester.pumpAndSettle();
      await _fillValidDraft(tester);

      await tester.tap(find.text('حفظ المسودة'));
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 1);
      expect(repository.drafts.single.partyId, 'customer-1');
      expect(repository.drafts.single.lines, hasLength(1));
      expect(find.text('إنشاء فاتورة مبيعات'), findsNothing);
    });

    testWidgets('successful save refreshes the invoice list and confirms '
        'persistence', (tester) async {
      final repository = _FakeSalesRepository();
      await _openScreen(tester, repository, size: desktop);
      await tester.tap(find.text('إنشاء فاتورة').first);
      await tester.pumpAndSettle();
      await _fillValidDraft(tester);

      await tester.tap(find.text('حفظ المسودة'));
      await tester.pumpAndSettle();

      expect(find.text('تم حفظ مسودة الفاتورة بنجاح.'), findsOneWidget);
      expect(find.text('مسودة بلا رقم'), findsOneWidget);
    });

    testWidgets('RPC failure stays visible and keeps the editor open', (
      tester,
    ) async {
      final repository = _FakeSalesRepository(
        saveFailure: const SalesFailure(
          'لا توجد صلاحية مفعلة لحفظ مسودة الفاتورة لهذا المستخدم في هذه الشركة.',
          code: 'DENIED',
        ),
      );
      await _openEditor(tester, repository, size: scaledLaptop);
      await _fillValidDraft(tester);

      await tester.tap(find.text('حفظ المسودة'));
      await tester.pumpAndSettle();

      expect(repository.saveCalls, 1);
      expectVisibleOnScreen(
        tester,
        find.text(
          'لا توجد صلاحية مفعلة لحفظ مسودة الفاتورة لهذا المستخدم في هذه الشركة.',
        ),
      );
      expectVisibleOnScreen(tester, find.text('رمز الخطأ: DENIED'));
      expect(find.text('إنشاء فاتورة مبيعات'), findsOneWidget);
    });

    testWidgets('unexpected exception is surfaced instead of being swallowed', (
      tester,
    ) async {
      final repository = _FakeSalesRepository(saveError: StateError('boom'));
      await _openEditor(tester, repository, size: scaledLaptop);
      await _fillValidDraft(tester);

      await tester.tap(find.text('حفظ المسودة'));
      await tester.pumpAndSettle();

      expectVisibleOnScreen(tester, find.textContaining('خطأ غير متوقع'));
      expectVisibleOnScreen(tester, find.text('رمز الخطأ: UNEXPECTED'));
      expect(find.text('إنشاء فاتورة مبيعات'), findsOneWidget);
    });

    testWidgets('duplicate save clicks issue one repository request while '
        'saving', (tester) async {
      final pending = Completer<SalesInvoice>();
      final repository = _FakeSalesRepository(saveCompleter: pending);
      await _openEditor(tester, repository, size: desktop);
      await _fillValidDraft(tester);

      await tester.tap(find.text('حفظ المسودة'));
      await tester.pump();
      expect(find.text('جارٍ حفظ المسودة...'), findsOneWidget);
      await tester.tap(find.text('جارٍ حفظ المسودة...'));
      await tester.pump();
      expect(repository.saveCalls, 1);

      pending.complete(_invoice(id: repository.drafts.single.id));
      await tester.pumpAndSettle();
      expect(find.text('إنشاء فاتورة مبيعات'), findsNothing);
    });

    testWidgets(
      'retrying after a failure reuses the same draft identity so the '
      'server updates instead of inserting twice',
      (tester) async {
        final repository = _FakeSalesRepository(
          saveFailure: const SalesFailure(
            'تعذر الحفظ مؤقتاً.',
            code: 'UNAVAILABLE',
          ),
        );
        await _openEditor(tester, repository, size: desktop);
        await _fillValidDraft(tester);

        await tester.tap(find.text('حفظ المسودة'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('حفظ المسودة'));
        await tester.pumpAndSettle();

        expect(repository.saveCalls, 2);
        final first = repository.drafts[0];
        final second = repository.drafts[1];
        expect(second.id, first.id);
        expect(second.idempotencyKey, first.idempotencyKey);
      },
    );

    testWidgets('a response that does not confirm the saved draft is not '
        'reported as success', (tester) async {
      final repository = _FakeSalesRepository(
        saveInvoice: _invoice(id: 'some-other-invoice'),
      );
      await _openEditor(tester, repository, size: desktop);
      await _fillValidDraft(tester);

      await tester.tap(find.text('حفظ المسودة'));
      await tester.pumpAndSettle();

      expectVisibleOnScreen(tester, find.textContaining('لم يؤكد الخادم'));
      expect(find.text('إنشاء فاتورة مبيعات'), findsOneWidget);
    });

    testWidgets('reference load failure is retryable and visible', (
      tester,
    ) async {
      final repository = _FakeSalesRepository(
        referenceFailure: const SalesFailure(
          'تعذر تحميل أنواع مستندات المبيعات.',
          code: 'UNAVAILABLE',
        ),
      );
      await _openEditor(tester, repository, size: desktop);

      expectVisibleOnScreen(
        tester,
        find.text('تعذر تحميل أنواع مستندات المبيعات.'),
      );
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });

  group('sales draft repository contract', () {
    test('mapSalesDraftFailure keeps an explicit reason and safe code', () {
      final denied = mapSalesDraftFailure(
        const PostgrestException(message: 'PERMISSION_DENIED', code: '42501'),
      );
      expect(denied.code, 'DENIED');
      expect(denied.message, contains('صلاحية'));

      final reference = mapSalesDraftFailure(
        const PostgrestException(
          message: 'DRAFT_REFERENCE_INVALID',
          code: '23514',
        ),
      );
      expect(reference.code, '23514');
      expect(reference.message, contains('السنة المالية'));

      final unknown = mapSalesDraftFailure(
        const PostgrestException(message: 'unexpected', code: 'XX000'),
      );
      expect(unknown.code, 'XX000');
      expect(unknown.message, contains('XX000'));
    });
  });
}

void expectVisibleOnScreen(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget, reason: 'expected exactly one match');
  final rect = tester.getRect(finder);
  final logical = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(
    rect.top,
    greaterThanOrEqualTo(0),
    reason: 'feedback is rendered above the window',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(logical.height),
    reason:
        'feedback is rendered below the visible window (top=${rect.top}, '
        'bottom=${rect.bottom}, height=${logical.height})',
  );
}

Future<void> _openEditor(
  WidgetTester tester,
  SalesRepository repository, {
  Size size = const Size(1280, 720),
}) async {
  await _applySize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<SalesInvoice>(
                context: context,
                builder: (_) => SalesInvoiceEditorDialog(
                  companyId: 'company-1',
                  repository: repository,
                ),
              ),
              child: const Text('فتح'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('فتح'));
  await tester.pumpAndSettle();
}

Future<void> _openScreen(
  WidgetTester tester,
  SalesRepository repository, {
  Size size = const Size(1280, 720),
}) async {
  await _applySize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SalesInvoicesScreen(
            companyId: 'company-1',
            repository: repository,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _applySize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _fillValidDraft(WidgetTester tester) async {
  await tester.tap(_dropdown<Customer>());
  await tester.pumpAndSettle();
  await tester.tap(find.text('C-1 — العميل').last);
  await tester.pumpAndSettle();
  await tester.tap(_dropdown<Product>());
  await tester.pumpAndSettle();
  await tester.tap(find.text('P-1 — صنف').last);
  await tester.pumpAndSettle();
  await tester.tap(_dropdown<Warehouse>());
  await tester.pumpAndSettle();
  await tester.tap(find.text('المستودع الرئيسي').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(1), '10.00');
  await tester.pump();
}

Finder _dropdown<T>() =>
    find.byWidgetPredicate((widget) => widget is DropdownButtonFormField<T>);

class _FakeSalesRepository implements SalesRepository {
  _FakeSalesRepository({
    this.saveFailure,
    this.saveError,
    this.saveCompleter,
    this.saveInvoice,
    this.referenceFailure,
  });

  final SalesFailure? saveFailure;
  final Object? saveError;
  final Completer<SalesInvoice>? saveCompleter;
  final SalesInvoice? saveInvoice;
  final SalesFailure? referenceFailure;

  final List<SalesInvoice> _invoices = [];
  final List<SalesInvoiceDraft> drafts = [];
  int saveCalls = 0;

  @override
  bool get isPostingAvailable => false;

  @override
  Future<List<SalesInvoice>> listInvoices({required String companyId}) async =>
      _invoices;

  @override
  Future<List<SalesInvoiceLine>> listLines({
    required String companyId,
    required String documentId,
  }) async => const [];

  @override
  Future<SalesReferenceData> loadReferences({required String companyId}) async {
    if (referenceFailure case final failure?) throw failure;
    return SalesReferenceData(
      customers: const [
        Customer(
          id: 'customer-1',
          companyId: 'company-1',
          code: 'C-1',
          nameAr: 'العميل',
          partyType: 'company',
          isCustomer: true,
          isSupplier: false,
          isActive: true,
        ),
      ],
      products: const [
        Product(
          id: 'product-1',
          companyId: 'company-1',
          code: 'P-1',
          nameAr: 'صنف',
          baseUomId: 'uom-1',
          trackInventory: true,
          isActive: true,
        ),
      ],
      warehouses: const [
        Warehouse(
          id: 'warehouse-1',
          companyId: 'company-1',
          code: 'W-1',
          nameAr: 'المستودع الرئيسي',
          isActive: true,
        ),
      ],
      documentTypes: const [
        SalesDocumentType(
          id: 'type-1',
          companyId: 'company-1',
          code: 'SI',
          nameAr: 'فاتورة مبيعات',
          issuance: 'posting',
          isActive: true,
        ),
      ],
      fiscalYears: [
        FiscalYearOption(
          id: 'year-1',
          companyId: 'company-1',
          startDate: DateTime(2026),
          endDate: DateTime(2026, 12, 31),
          status: 'open',
        ),
      ],
    );
  }

  @override
  Future<SalesInvoice> saveDraftAtomically(SalesInvoiceDraft draft) async {
    saveCalls++;
    drafts.add(draft);
    if (saveFailure case final failure?) throw failure;
    if (saveError case final error?) throw error;
    final invoice =
        saveCompleter?.future ??
        Future<SalesInvoice>.value(saveInvoice ?? _invoice(id: draft.id));
    final resolved = await invoice;
    _invoices.add(resolved);
    return resolved;
  }

  @override
  Future<SalesPostingResult> postInvoice(SalesInvoice invoice) {
    throw salesPostingUnavailable();
  }
}

SalesInvoice _invoice({String id = 'invoice-1'}) => SalesInvoice(
  id: id,
  companyId: 'company-1',
  partyId: 'customer-1',
  docDate: DateTime(2026, 10, 31),
  status: SalesInvoiceStatus.draft,
  vatMode: VatMode.exclusive,
  documentTypeId: 'type-1',
  fiscalYearId: 'year-1',
  net: InvoiceAmount.tryParse('10.00')!,
  tax: InvoiceAmount.zero(),
  gross: InvoiceAmount.tryParse('10.00')!,
  idempotencyKey: 'posting-key-$id',
);
