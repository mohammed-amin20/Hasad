import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/inventory/presentation/inventory_display.dart';

void main() {
  group('parseInventoryNumber', () {
    test('accepts Latin, Arabic, and Persian digits', () {
      expect(parseInventoryNumber('12.5'), 12.5);
      expect(parseInventoryNumber('١٢.٥'), 12.5);
      expect(parseInventoryNumber('۱۲.۵'), 12.5);
    });

    test('accepts Arabic decimal separator and comma forms', () {
      expect(parseInventoryNumber('12٫75'), 12.75);
      expect(parseInventoryNumber('1,250.75'), 1250.75);
      expect(parseInventoryNumber('12,75'), 12.75);
      expect(parseInventoryNumber(' 1 200 '), 1200);
    });

    test('returns null for blank or invalid input', () {
      expect(parseInventoryNumber(null), isNull);
      expect(parseInventoryNumber('   '), isNull);
      expect(parseInventoryNumber('abc'), isNull);
      expect(parseInventoryNumber('1.2.3'), isNull);
    });
  });

  group('formatInventoryQty', () {
    test('trims trailing zeros without losing precision', () {
      expect(formatInventoryQty(10), '10');
      expect(formatInventoryQty(10.5), '10.5');
      expect(formatInventoryQty(10.2500), '10.25');
      expect(formatInventoryQty(0.0001), '0.0001');
      expect(formatInventoryQty(0), '0');
    });
  });

  group('formatInventoryMoney', () {
    test('always shows two decimals and groups thousands', () {
      expect(formatInventoryMoney(0), '0.00');
      expect(formatInventoryMoney(12.5), '12.50');
      expect(formatInventoryMoney(1234567.891), '1,234,567.89');
      expect(formatInventoryMoney(-1250.5), '-1,250.50');
    });
  });

  group('formatInventoryDateTime', () {
    test('formats a local date-time with zero padding', () {
      final value = DateTime(2026, 1, 5, 7, 9);
      expect(formatInventoryDateTime(value), '2026/01/05 07:09');
    });
  });

  group('movement display labels', () {
    test('maps documented movement types to Arabic labels', () {
      expect(stockMovementTypeLabel('purchase_receipt'), 'استلام مشتريات');
      expect(stockMovementTypeLabel('sales_issue'), 'صرف مبيعات');
      expect(stockMovementTypeLabel('transfer_out'), 'تحويل صادر');
      expect(stockMovementTypeLabel('transfer_in'), 'تحويل وارد');
      expect(stockMovementTypeLabel('opening'), 'رصيد افتتاحي');
    });

    test('keeps unknown movement types visible instead of hiding them', () {
      expect(stockMovementTypeLabel('custom_movement'), 'custom_movement');
    });
  });
}
