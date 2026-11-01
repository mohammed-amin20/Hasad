import 'package:hasad_erp_v2/inventory/presentation/inventory_display.dart';

String? validateStockQuantityInput(String? value) {
  final quantity = parseInventoryNumber(value);
  if (quantity == null || !quantity.isFinite) return 'أدخل كمية صالحة.';
  if (quantity <= 0) return 'الكمية يجب أن تكون أكبر من صفر.';
  if (_fractionalDigits(value!) > 4) return 'الحد الأقصى لأربع منازل عشرية.';
  return null;
}

String? validateStockCostInput(String? value) {
  final cost = parseInventoryNumber(value);
  if (cost == null || !cost.isFinite) return 'أدخل تكلفة صالحة.';
  if (cost < 0) return 'التكلفة لا تكون سالبة.';
  if (_fractionalDigits(value!) > 4) return 'الحد الأقصى لأربع منازل عشرية.';
  return null;
}

String? validateStockAvailableQuantity(String? value, double available) {
  final quantityError = validateStockQuantityInput(value);
  if (quantityError != null) return quantityError;
  if (!available.isFinite || available < 0) return 'الرصيد المتاح غير صالح.';
  final quantity = parseInventoryNumber(value)!;
  if (quantity > available) return 'الكمية تتجاوز الرصيد المتاح.';
  return null;
}

bool stockSelectionMatchesCompany({
  required String companyId,
  required String productCompanyId,
  required String warehouseCompanyId,
}) =>
    companyId.isNotEmpty &&
    productCompanyId == companyId &&
    warehouseCompanyId == companyId;

int _fractionalDigits(String value) {
  final separators = RegExp(r'[.،٫,]|ظ«').allMatches(value);
  final separator = separators.isEmpty ? null : separators.last;
  if (separator == null) return 0;
  return value.length - separator.end;
}

class StockMovementSubmissionGuard {
  bool _running = false;

  bool get isRunning => _running;

  Future<void> run(Future<void> Function() submit) async {
    if (_running) return;
    _running = true;
    try {
      await submit();
    } finally {
      _running = false;
    }
  }
}
