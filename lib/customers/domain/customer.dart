class Customer {
  const Customer({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.partyType,
    required this.isCustomer,
    required this.isSupplier,
    required this.isActive,
    this.nameEn,
    this.taxId,
    this.phone,
    this.email,
    this.address,
    this.paymentTermsDays,
  });

  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final String? nameEn;
  final String partyType;
  final bool isCustomer;
  final bool isSupplier;
  final String? taxId;
  final String? phone;
  final String? email;
  final String? address;
  final int? paymentTermsDays;
  final bool isActive;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: _requiredString(json, 'id'),
    companyId: _requiredString(json, 'company_id'),
    code: _requiredString(json, 'code'),
    nameAr: _requiredString(json, 'name_ar'),
    nameEn: _optionalString(json, 'name_en'),
    partyType: _requiredString(json, 'party_type'),
    isCustomer: json['is_customer'] as bool? ?? false,
    isSupplier: json['is_supplier'] as bool? ?? false,
    taxId: _optionalString(json, 'tax_id'),
    phone: _optionalString(json, 'phone'),
    email: _optionalString(json, 'email'),
    address: _optionalString(json, 'address'),
    paymentTermsDays: (json['payment_terms_days'] as num?)?.toInt(),
    isActive: json['is_active'] as bool? ?? false,
  );

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Invalid customer field: $key');
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('Invalid customer field: $key');
  }
}

class CustomerDraft {
  const CustomerDraft({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.partyType,
    required this.isSupplier,
    required this.isActive,
    this.nameEn,
    this.taxId,
    this.phone,
    this.email,
    this.address,
    this.paymentTermsDays,
  });

  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final String? nameEn;
  final String partyType;
  final bool isSupplier;
  final String? taxId;
  final String? phone;
  final String? email;
  final String? address;
  final int? paymentTermsDays;
  final bool isActive;

  Map<String, Object?> toInsertJson() => {
    'id': id,
    'company_id': companyId,
    ...toUpdateJson(),
    'is_customer': true,
  };

  Map<String, Object?> toUpdateJson() => {
    'code': code.trim(),
    'name_ar': nameAr.trim(),
    'name_en': _nullable(nameEn),
    'party_type': partyType,
    'is_customer': true,
    'is_supplier': isSupplier,
    'tax_id': _nullable(taxId),
    'phone': _nullable(phone),
    'email': _nullable(email),
    'address': _nullable(address),
    'payment_terms_days': paymentTermsDays,
    'is_active': isActive,
  };

  static String? _nullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
