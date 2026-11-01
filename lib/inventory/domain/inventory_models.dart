import 'package:hasad_erp_v2/company/domain/product.dart';

class UnitOfMeasure {
  const UnitOfMeasure({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.isBase,
    required this.isActive,
  });

  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final bool isBase;
  final bool isActive;
}

class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.isActive,
  });
  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final bool isActive;
}

class UnitOfMeasureDraft {
  const UnitOfMeasureDraft({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.isBase,
    required this.isActive,
  });
  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final bool isBase;
  final bool isActive;
  Map<String, Object> toJson() => {
    'id': id,
    'company_id': companyId,
    'code': code.trim(),
    'name_ar': nameAr.trim(),
    'is_base': isBase,
    'is_active': isActive,
  };
}

class ProductCategoryDraft {
  const ProductCategoryDraft({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.isActive,
  });
  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final bool isActive;
  Map<String, Object> toJson() => {
    'id': id,
    'company_id': companyId,
    'code': code.trim(),
    'name_ar': nameAr.trim(),
    'is_active': isActive,
  };
}

class Warehouse {
  const Warehouse({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.isActive,
  });
  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final bool isActive;
}

class WarehouseDraft {
  const WarehouseDraft({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.isActive,
  });
  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final bool isActive;
  Map<String, Object> toJson() => {
    'id': id,
    'company_id': companyId,
    'code': code.trim(),
    'name_ar': nameAr.trim(),
    'is_active': isActive,
  };
}

class StockBalance {
  const StockBalance({
    required this.companyId,
    required this.productId,
    required this.warehouseId,
    required this.qty,
    required this.lastUnitCost,
  });
  final String companyId;
  final String productId;
  final String warehouseId;
  final double qty;
  final double lastUnitCost;
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.companyId,
    required this.productId,
    required this.warehouseId,
    required this.movementType,
    required this.direction,
    required this.qty,
    required this.unitCost,
    required this.value,
    required this.seq,
    required this.postedAt,
    this.sourceDocumentType,
    this.sourceDocumentId,
    this.journalLineId,
  });
  final String id;
  final String companyId;
  final String productId;
  final String warehouseId;
  final String movementType;
  final String direction;
  final double qty;
  final double unitCost;
  final double value;
  final int seq;
  final DateTime postedAt;
  final String? sourceDocumentType;
  final String? sourceDocumentId;
  final String? journalLineId;
}

class StockReceiptDraft {
  const StockReceiptDraft({
    required this.id,
    required this.companyId,
    required this.warehouseId,
    required this.productId,
    required this.qty,
    required this.unitCost,
  });
  final String id;
  final String companyId;
  final String warehouseId;
  final String productId;
  final double qty;
  final double unitCost;
}

class StockIssueDraft {
  const StockIssueDraft({
    required this.id,
    required this.companyId,
    required this.warehouseId,
    required this.productId,
    required this.qty,
  });
  final String id;
  final String companyId;
  final String warehouseId;
  final String productId;
  final double qty;
}

class StockTransferDraft {
  const StockTransferDraft({
    required this.outMovementId,
    required this.inMovementId,
    required this.companyId,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.productId,
    required this.qty,
  });
  final String outMovementId;
  final String inMovementId;
  final String companyId;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final String productId;
  final double qty;
}

class ProductDraft {
  const ProductDraft({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.baseUomId,
    required this.trackInventory,
    required this.isActive,
    this.nameEn,
    this.barcode,
    this.categoryId,
  });

  factory ProductDraft.fromProduct(Product product) => ProductDraft(
    id: product.id,
    companyId: product.companyId,
    code: product.code,
    nameAr: product.nameAr,
    nameEn: product.nameEn,
    barcode: product.barcode,
    categoryId: product.categoryId,
    baseUomId: product.baseUomId ?? '',
    trackInventory: product.trackInventory,
    isActive: product.isActive,
  );

  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final String? nameEn;
  final String? barcode;
  final String? categoryId;
  final String baseUomId;
  final bool trackInventory;
  final bool isActive;
}

class InventoryFailure implements Exception {
  const InventoryFailure(this.message, {this.code});
  final String message;
  final String? code;
}

String classifyStockPostingError(
  String? sqlState,
  String message, {
  bool missingBackend = false,
}) {
  const messageCodes = [
    'STOCK_INSUFFICIENT',
    'PRODUCT_NOT_AVAILABLE',
    'WAREHOUSE_NOT_AVAILABLE',
    'SAME_WAREHOUSE',
    'QTY_INVALID',
    'QTY_PRECISION',
    'COST_INVALID',
    'COST_PRECISION',
    'IDEMPOTENCY_CONFLICT',
    'INVALID_ARGUMENT',
    'UNAUTHENTICATED',
    'FORBIDDEN',
  ];
  for (final code in messageCodes) {
    if (message.contains(code)) return code;
  }
  if (missingBackend) return 'BACKEND_NOT_CONFIGURED';
  return switch (sqlState) {
    '42501' => 'DENIED',
    '23505' => 'DUPLICATE',
    '23514' || '22003' => 'VALIDATION',
    _ => sqlState ?? 'UNKNOWN',
  };
}
