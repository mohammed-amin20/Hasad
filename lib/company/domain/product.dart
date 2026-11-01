class Product {
  const Product({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    this.nameEn,
    this.barcode,
    this.categoryId,
    this.baseUomId,
    this.trackInventory = true,
    this.isActive = true,
  });

  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final String? nameEn;
  final String? barcode;
  final String? categoryId;
  final String? baseUomId;
  final bool trackInventory;
  final bool isActive;
}