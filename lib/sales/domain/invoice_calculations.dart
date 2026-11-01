/// Fixed-scale invoice arithmetic. Amounts are stored as integer hundredths
/// (ILS cents) and quantity/unit-price inputs as four-decimal integers, so UI
/// totals never depend on binary floating-point arithmetic.
enum VatMode { exclusive, inclusive }

class InvoiceAmount {
  const InvoiceAmount._(this.cents);

  factory InvoiceAmount.zero() => const InvoiceAmount._(0);

  factory InvoiceAmount.fromCents(int cents) => InvoiceAmount._(cents);

  final int cents;

  static InvoiceAmount? tryParse(String value) {
    final match = RegExp(r'^\s*(\d+)(?:\.(\d{1,2}))?\s*$').firstMatch(value);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return InvoiceAmount._(whole * 100 + (int.tryParse(fraction) ?? 0));
  }

  String toDecimalString() =>
      '${cents ~/ 100}.${(cents % 100).abs().toString().padLeft(2, '0')}';
  @override
  String toString() => toDecimalString();
}

class InvoiceQuantity {
  const InvoiceQuantity._(this.units4);
  final int units4;

  static InvoiceQuantity? tryParse(String value) {
    final match = RegExp(r'^\s*(\d+)(?:\.(\d{1,4}))?\s*$').firstMatch(value);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fraction = (match.group(2) ?? '').padRight(4, '0');
    return InvoiceQuantity._(whole * 10000 + (int.tryParse(fraction) ?? 0));
  }

  String toDecimalString() =>
      '${units4 ~/ 10000}.${(units4 % 10000).toString().padLeft(4, '0')}';
}

class InvoiceLineTotals {
  const InvoiceLineTotals({
    required this.net,
    required this.tax,
    required this.gross,
  });
  final InvoiceAmount net;
  final InvoiceAmount tax;
  final InvoiceAmount gross;
}

class InvoiceTotals {
  const InvoiceTotals({
    required this.net,
    required this.tax,
    required this.gross,
  });
  final InvoiceAmount net;
  final InvoiceAmount tax;
  final InvoiceAmount gross;
}

/// Tax rate is an optional percentage with up to three decimal places, matching
/// `numeric(6,3)`. The value is a preview input only; server posting must
/// resolve and snapshot the effective tax rate.
int? parseTaxRateMillis(String value) {
  if (value.trim().isEmpty) return 0;
  final match = RegExp(r'^\s*(\d+)(?:\.(\d{1,3}))?\s*$').firstMatch(value);
  if (match == null) return null;
  final whole = int.tryParse(match.group(1)!);
  if (whole == null) return null;
  return whole * 1000 +
      (int.tryParse((match.group(2) ?? '').padRight(3, '0')) ?? 0);
}

InvoiceLineTotals calculateInvoiceLine({
  required InvoiceQuantity quantity,
  required InvoiceAmount unitPrice,
  required InvoiceAmount discount,
  required int taxRateMillis,
  required VatMode vatMode,
}) {
  // quantity × price gives an eight-decimal product. Convert to cents using
  // HALF_UP, then apply the fixed monetary discount.
  final beforeDiscount = _roundHalfUp(quantity.units4 * unitPrice.cents, 10000);
  final enteredAmount = (beforeDiscount - discount.cents).clamp(0, 1 << 62);
  if (vatMode == VatMode.exclusive) {
    final tax = _roundHalfUp(enteredAmount * taxRateMillis, 100000);
    return InvoiceLineTotals(
      net: InvoiceAmount.fromCents(enteredAmount),
      tax: InvoiceAmount.fromCents(tax),
      gross: InvoiceAmount.fromCents(enteredAmount + tax),
    );
  }
  final divisor = 100000 + taxRateMillis;
  final net = _roundHalfUp(enteredAmount * 100000, divisor);
  return InvoiceLineTotals(
    net: InvoiceAmount.fromCents(net),
    tax: InvoiceAmount.fromCents(enteredAmount - net),
    gross: InvoiceAmount.fromCents(enteredAmount),
  );
}

InvoiceTotals sumInvoiceTotals(Iterable<InvoiceLineTotals> lines) {
  var net = 0;
  var tax = 0;
  var gross = 0;
  for (final line in lines) {
    net += line.net.cents;
    tax += line.tax.cents;
    gross += line.gross.cents;
  }
  return InvoiceTotals(
    net: InvoiceAmount.fromCents(net),
    tax: InvoiceAmount.fromCents(tax),
    gross: InvoiceAmount.fromCents(gross),
  );
}

int _roundHalfUp(int numerator, int denominator) =>
    (numerator + denominator ~/ 2) ~/ denominator;

String? validateQuantity(String? value) {
  final quantity = value == null ? null : InvoiceQuantity.tryParse(value);
  return quantity == null || quantity.units4 <= 0
      ? 'أدخل كمية أكبر من صفر.'
      : null;
}

String? validateUnitPrice(String? value) {
  final amount = value == null ? null : InvoiceAmount.tryParse(value);
  return amount == null ? 'أدخل سعر وحدة صحيحاً حتى منزلتين عشريتين.' : null;
}

String? validateDiscount(String? value) {
  final amount = value == null ? null : InvoiceAmount.tryParse(value);
  return amount == null ? 'أدخل خصماً صحيحاً أو اتركه صفراً.' : null;
}
