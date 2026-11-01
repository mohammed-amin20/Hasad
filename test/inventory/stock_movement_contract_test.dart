import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:hasad_erp_v2/inventory/presentation/stock_movement_validation.dart';

void main() {
  group('stock movement quantity validation', () {
    test('requires a finite positive quantity with at most four decimals', () {
      expect(validateStockQuantityInput('0.0001'), isNull);
      expect(validateStockQuantityInput('0'), isNotNull);
      expect(validateStockQuantityInput('-1'), isNotNull);
      expect(validateStockQuantityInput('1.00001'), isNotNull);
      expect(validateStockQuantityInput('invalid'), isNotNull);
    });

    test('receipt cost is explicit, finite, nonnegative and four-place', () {
      expect(validateStockCostInput('0'), isNull);
      expect(validateStockCostInput('12.3456'), isNull);
      expect(validateStockCostInput(''), isNotNull);
      expect(validateStockCostInput('-0.01'), isNotNull);
      expect(validateStockCostInput('1.00001'), isNotNull);
    });

    test('issue and transfer allow the exact available boundary only', () {
      expect(validateStockAvailableQuantity('5', 5), isNull);
      expect(validateStockAvailableQuantity('5.0001', 5), isNotNull);
      expect(validateStockAvailableQuantity('0', 5), isNotNull);
      expect(validateStockAvailableQuantity('1', -1), isNotNull);
    });
  });

  group('company scoping', () {
    test(
      'requires product and warehouse to belong to active company scope',
      () {
        expect(
          stockSelectionMatchesCompany(
            companyId: 'company-a',
            productCompanyId: 'company-a',
            warehouseCompanyId: 'company-a',
          ),
          isTrue,
        );
        expect(
          stockSelectionMatchesCompany(
            companyId: 'company-a',
            productCompanyId: 'company-b',
            warehouseCompanyId: 'company-a',
          ),
          isFalse,
        );
        expect(
          stockSelectionMatchesCompany(
            companyId: 'company-a',
            productCompanyId: 'company-a',
            warehouseCompanyId: 'company-b',
          ),
          isFalse,
        );
      },
    );
  });

  group('duplicate submission and server error handling', () {
    test(
      'ignores a second submission while the first confirmation/post is open',
      () async {
        final guard = StockMovementSubmissionGuard();
        final completion = Completer<void>();
        var submitCount = 0;

        final first = guard.run(() {
          submitCount++;
          return completion.future;
        });
        await Future<void>.delayed(Duration.zero);
        await guard.run(() async => submitCount++);

        expect(submitCount, 1);
        expect(guard.isRunning, isTrue);

        completion.complete();
        await first;
        expect(guard.isRunning, isFalse);
      },
    );

    test(
      'classifies typed backend errors without exposing raw server text',
      () {
        expect(
          classifyStockPostingError('P0001', 'STOCK_INSUFFICIENT'),
          'STOCK_INSUFFICIENT',
        );
        expect(
          classifyStockPostingError('P0001', 'QTY_PRECISION'),
          'QTY_PRECISION',
        );
        expect(
          classifyStockPostingError('P0001', 'COST_PRECISION'),
          'COST_PRECISION',
        );
        expect(
          classifyStockPostingError('P0001', 'IDEMPOTENCY_CONFLICT'),
          'IDEMPOTENCY_CONFLICT',
        );
        expect(
          classifyStockPostingError('42501', 'permission denied'),
          'DENIED',
        );
        expect(
          classifyStockPostingError(
            'PGRST202',
            'missing function',
            missingBackend: true,
          ),
          'BACKEND_NOT_CONFIGURED',
        );
      },
    );
  });
}
