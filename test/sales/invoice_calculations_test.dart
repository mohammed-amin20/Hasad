import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/sales/domain/invoice_calculations.dart';

void main() {
  InvoiceQuantity qty(String value) => InvoiceQuantity.tryParse(value)!;
  InvoiceAmount money(String value) => InvoiceAmount.tryParse(value)!;

  test('exclusive invoice line applies fixed discount and HALF_UP tax', () {
    final result = calculateInvoiceLine(
      quantity: qty('3'),
      unitPrice: money('19.99'),
      discount: money('1.00'),
      taxRateMillis: 18000,
      vatMode: VatMode.exclusive,
    );
    expect(result.net.toString(), '58.97');
    expect(result.tax.toString(), '10.61');
    expect(result.gross.toString(), '69.58');
  });

  test('inclusive invoice line conserves entered gross amount', () {
    final result = calculateInvoiceLine(
      quantity: qty('1'),
      unitPrice: money('104.97'),
      discount: InvoiceAmount.zero(),
      taxRateMillis: 18000,
      vatMode: VatMode.inclusive,
    );
    expect(result.net.toString(), '88.96');
    expect(result.tax.toString(), '16.01');
    expect(result.gross.toString(), '104.97');
  });

  test('sums line totals without binary floating-point loss', () {
    final first = calculateInvoiceLine(
      quantity: qty('0.3333'),
      unitPrice: money('10.00'),
      discount: InvoiceAmount.zero(),
      taxRateMillis: 0,
      vatMode: VatMode.exclusive,
    );
    final total = sumInvoiceTotals([first, first, first]);
    expect(total.net.toString(), '9.99');
    expect(total.gross.toString(), '9.99');
  });

  test('validates quantity, money and tax input shapes', () {
    expect(validateQuantity('0'), isNotNull);
    expect(validateQuantity('1.0001'), isNull);
    expect(validateUnitPrice('12.345'), isNotNull);
    expect(validateDiscount('-1'), isNotNull);
    expect(parseTaxRateMillis('18.125'), 18125);
    expect(parseTaxRateMillis('bad'), isNull);
  });
}
