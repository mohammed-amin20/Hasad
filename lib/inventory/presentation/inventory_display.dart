import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';

double? parseInventoryNumber(String? input) {
  if (input == null) return null;
  var text = input.trim();
  if (text.isEmpty) return null;
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
  for (var index = 0; index < 10; index++) {
    text = text
        .replaceAll(arabicDigits[index], '$index')
        .replaceAll(persianDigits[index], '$index');
  }
  text = text.replaceAll('٫', '.').replaceAll(' ', '').replaceAll('\u00A0', '');
  if (text.contains(',') && text.contains('.')) {
    text = text.replaceAll(',', '');
  } else {
    text = text.replaceAll(',', '.');
  }
  return double.tryParse(text);
}

String formatInventoryQty(double value) {
  final fixed = value.toStringAsFixed(4);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String formatInventoryMoney(double value) {
  final fixed = value.toStringAsFixed(2);
  final negative = fixed.startsWith('-');
  final parts = (negative ? fixed.substring(1) : fixed).split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return '${negative ? '-' : ''}${buffer.toString()}.${parts[1]}';
}

String formatInventoryDateTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}/$month/$day $hour:$minute';
}

String stockMovementTypeLabel(String type) => switch (type) {
  'purchase_receipt' => 'استلام مشتريات',
  'sales_issue' => 'صرف مبيعات',
  'sales_return' => 'مرتجع مبيعات',
  'purchase_return' => 'مرتجع مشتريات',
  'transfer_out' => 'تحويل صادر',
  'transfer_in' => 'تحويل وارد',
  'count_adjustment' => 'تسوية جرد',
  'opening' => 'رصيد افتتاحي',
  _ => type,
};

IconData stockMovementTypeIcon(String type) => switch (type) {
  'purchase_receipt' => Icons.south_west_rounded,
  'sales_issue' => Icons.north_east_rounded,
  'transfer_out' => Icons.compare_arrows_rounded,
  'transfer_in' => Icons.compare_arrows_rounded,
  'sales_return' => Icons.assignment_return_outlined,
  'purchase_return' => Icons.assignment_returned_outlined,
  'opening' => Icons.flag_outlined,
  _ => Icons.tune_rounded,
};

Color stockMovementTypeColor(String type) => switch (type) {
  'purchase_receipt' || 'transfer_in' || 'sales_return' => HasadPalette.success,
  'sales_issue' || 'transfer_out' || 'purchase_return' => HasadPalette.danger,
  'opening' => HasadPalette.amberDark,
  _ => HasadPalette.warning,
};
