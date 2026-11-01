String? validateCustomerCode(String? value) =>
    value == null || value.trim().isEmpty ? 'أدخل رمز العميل.' : null;

String? validateCustomerName(String? value) =>
    value == null || value.trim().isEmpty ? 'أدخل اسم العميل بالعربية.' : null;

String? validatePaymentTerms(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  final days = int.tryParse(text);
  if (days == null || days < 0) return 'أدخل عدد أيام صحيحاً غير سالب.';
  return null;
}
