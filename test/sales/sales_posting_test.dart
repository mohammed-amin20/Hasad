import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/sales/data/sales_repository.dart';
import 'package:hasad_erp_v2/sales/domain/invoice_calculations.dart';
import 'package:hasad_erp_v2/sales/domain/sales_invoice.dart';
import 'package:hasad_erp_v2/sales/presentation/sales_invoices_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  group('sales invoice posting', () {
    test(
      'maps server stock failure without suggesting a client-side retry',
      () {
        final failure = mapSalesPostingFailure(
          const PostgrestException(
            message: 'STOCK_INSUFFICIENT',
            code: '23514',
          ),
        );

        expect(failure.code, 'STOCK_INSUFFICIENT');
        expect(failure.message, contains('لم يُخصم أي مخزون'));
      },
    );

    testWidgets('draft shows an explicit unavailable explanation until S3 is '
        'approved and deployed', (tester) async {
      final repository = _PostingRepository(postingAvailable: false);
      await _openScreen(tester, repository);

      await tester.tap(find.byTooltip('التفاصيل'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sales-details-post')), findsNothing);
      expect(
        find.textContaining('ترحيل هذه المسودة غير متاح هنا'),
        findsOneWidget,
      );
      expect(repository.postCalls, 0);
    });

    testWidgets('available posting asks for confirmation and sends exactly one '
        'atomic repository request', (tester) async {
      final pending = Completer<SalesPostingResult>();
      final repository = _PostingRepository(
        postingAvailable: true,
        postCompleter: pending,
      );
      await _openScreen(tester, repository);

      await tester.tap(find.byTooltip('التفاصيل'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-details-post')));
      await tester.pumpAndSettle();

      expect(find.text('تأكيد ترحيل الفاتورة'), findsOneWidget);
      // The details dialog and its confirmation both summarize the gross total.
      expect(find.text('الإجمالي: 10.00'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('sales-post-confirm')));
      await tester.pump();
      expect(repository.postCalls, 1);
      expect(find.text('جارٍ الترحيل...'), findsOneWidget);

      pending.complete(_postingResult(_draftInvoice()));
      await tester.pumpAndSettle();

      expect(repository.postCalls, 1);
      expect(
        find.textContaining('تم ترحيل الفاتورة بالرقم الرسمي 0001'),
        findsOneWidget,
      );
      expect(find.text('0001'), findsOneWidget);
    });
  });
}

Future<void> _openScreen(
  WidgetTester tester,
  SalesRepository repository,
) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

class _PostingRepository implements SalesRepository {
  _PostingRepository({required this.postingAvailable, this.postCompleter})
    : _invoices = [_draftInvoice()];

  final bool postingAvailable;
  final Completer<SalesPostingResult>? postCompleter;
  final List<SalesInvoice> _invoices;
  int postCalls = 0;

  @override
  bool get isPostingAvailable => postingAvailable;

  @override
  Future<List<SalesInvoice>> listInvoices({required String companyId}) async =>
      List.unmodifiable(_invoices);

  @override
  Future<List<SalesInvoiceLine>> listLines({
    required String companyId,
    required String documentId,
  }) async => const [];

  @override
  Future<SalesReferenceData> loadReferences({
    required String companyId,
  }) async => const SalesReferenceData(
    customers: [],
    products: [],
    warehouses: [],
    documentTypes: [],
    fiscalYears: [],
  );

  @override
  Future<SalesInvoice> saveDraftAtomically(SalesInvoiceDraft draft) =>
      throw UnimplementedError();

  @override
  Future<SalesPostingResult> postInvoice(SalesInvoice invoice) async {
    postCalls++;
    final result =
        await (postCompleter?.future ?? Future.value(_postingResult(invoice)));
    _invoices
      ..clear()
      ..add(result.invoice);
    return result;
  }
}

SalesInvoice _draftInvoice() => SalesInvoice(
  id: 'invoice-1',
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
  idempotencyKey: 'posting-key-1',
);

SalesPostingResult _postingResult(SalesInvoice draft) => SalesPostingResult(
  invoice: SalesInvoice(
    id: draft.id,
    companyId: draft.companyId,
    partyId: draft.partyId,
    docDate: draft.docDate,
    status: SalesInvoiceStatus.posted,
    vatMode: draft.vatMode,
    documentTypeId: draft.documentTypeId,
    fiscalYearId: draft.fiscalYearId,
    net: draft.net,
    tax: draft.tax,
    gross: draft.gross,
    idempotencyKey: draft.idempotencyKey,
    documentNo: '0001',
    postedAt: DateTime(2026, 10, 31),
  ),
  journalEntryId: 'journal-1',
  journalEntryNo: 'JE-0001',
  replayed: false,
);
