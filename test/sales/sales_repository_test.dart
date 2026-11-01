import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/sales/data/sales_repository.dart';
import 'package:hasad_erp_v2/sales/domain/invoice_calculations.dart';
import 'package:hasad_erp_v2/sales/domain/sales_invoice.dart';

void main() {
  test('missing atomic draft operation fails closed', () {
    final error = draftPersistenceUnavailable();
    expect(error.code, 'DRAFT_PERSISTENCE_UNAVAILABLE');
  });

  test(
    'draft RPC payload carries one idempotency key and server-checkable totals',
    () {
      final draft = SalesInvoiceDraft(
        id: '00000000-0000-0000-0000-000000000001',
        companyId: 'company',
        partyId: 'party',
        docDate: DateTime(2026, 10, 31),
        vatMode: VatMode.exclusive,
        documentTypeId: 'type',
        fiscalYearId: 'year',
        idempotencyKey: '00000000-0000-0000-0000-000000000002',
        lines: [
          SalesInvoiceDraftLine(
            id: '00000000-0000-0000-0000-000000000003',
            productId: 'product',
            warehouseId: 'warehouse',
            quantity: InvoiceQuantity.tryParse('2')!,
            unitPrice: InvoiceAmount.tryParse('10.00')!,
            discount: InvoiceAmount.tryParse('1.00')!,
            taxRateMillis: 18000,
          ),
        ],
      );
      final payload = draft.toRpcParams();
      expect(payload['p_idempotency_key'], draft.idempotencyKey);
      expect(payload['p_lines'], isA<List<Map<String, Object?>>>());
      final line = (payload['p_lines'] as List).single as Map<String, Object?>;
      expect(line['net'], '19.00');
      expect(line['tax'], '3.42');
      expect(line['gross'], '22.42');
    },
  );

  test(
    'maps duplicate idempotency/database responses without raw server text',
    () {
      final failure = mapSalesFailureCode('23505', 'حفظ الفاتورة');
      expect(failure.code, 'DUPLICATE');
      expect(failure.message, contains('مكرر'));
    },
  );

  test('maps a denied reference read to its exact Arabic resource action', () {
    final failure = mapSalesFailureCode(
      '42501',
      'تحميل أنواع مستندات المبيعات',
    );
    expect(failure.code, 'DENIED');
    expect(failure.message, contains('أنواع مستندات المبيعات'));
  });

  test('status parser permits only hosted schema statuses', () {
    expect(salesInvoiceStatusFromDb('draft'), SalesInvoiceStatus.draft);
    expect(salesInvoiceStatusFromDb('posted'), SalesInvoiceStatus.posted);
    expect(() => salesInvoiceStatusFromDb('open'), throwsFormatException);
  });

  test('tenant scope rejects a response from another company', () {
    expect(
      () => requireSalesCompanyScope(['company-a', 'company-b'], 'company-a'),
      throwsA(isA<SalesCompanyScopeFailure>()),
    );
  });

  test('only a draft can transition to posted or cancelled', () {
    expect(
      canTransitionInvoiceStatus(
        SalesInvoiceStatus.draft,
        SalesInvoiceStatus.posted,
      ),
      isTrue,
    );
    expect(
      canTransitionInvoiceStatus(
        SalesInvoiceStatus.posted,
        SalesInvoiceStatus.cancelled,
      ),
      isFalse,
    );
  });
}
