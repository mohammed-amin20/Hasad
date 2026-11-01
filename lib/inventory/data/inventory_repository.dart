import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

abstract class InventoryRepository {
  Future<List<UnitOfMeasure>> listUnits({required String companyId});
  Future<List<ProductCategory>> listCategories({required String companyId});
  Future<UnitOfMeasure> createUnit(UnitOfMeasureDraft draft);
  Future<UnitOfMeasure> updateUnit(UnitOfMeasureDraft draft);
  Future<ProductCategory> createCategory(ProductCategoryDraft draft);
  Future<ProductCategory> updateCategory(ProductCategoryDraft draft);
  Future<List<Warehouse>> listWarehouses({required String companyId});
  Future<Warehouse> createWarehouse(WarehouseDraft draft);
  Future<Warehouse> updateWarehouse(WarehouseDraft draft);
  Future<List<StockBalance>> listStockBalances({required String companyId});
  Future<List<StockMovement>> listStockMovements({required String companyId});
  Future<bool> supportsStockPosting({required String companyId});
  Future<StockMovement> postStockReceipt(StockReceiptDraft draft);
  Future<StockMovement> postStockIssue(StockIssueDraft draft);
  Future<void> postStockTransfer(StockTransferDraft draft);
  Future<Product> createProduct(ProductDraft draft);
  Future<Product> updateProduct(ProductDraft draft);
}

class SupabaseInventoryRepository implements InventoryRepository {
  SupabaseInventoryRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<UnitOfMeasure>> listUnits({required String companyId}) async {
    try {
      final response = await _client
          .schema('hasad')
          .from('units_of_measure')
          .select('id,company_id,code,name_ar,is_base,is_active')
          .eq('company_id', companyId)
          .order('is_base', ascending: false)
          .order('code');
      return response.map(_unitFromResponse).toList(growable: false);
    } on InventoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapFailure(error, action: 'تحميل وحدات القياس');
    } on Object {
      throw const InventoryFailure('تعذر تحميل وحدات القياس.');
    }
  }

  @override
  Future<List<ProductCategory>> listCategories({
    required String companyId,
  }) async => _listMaster(
    table: 'product_categories',
    companyId: companyId,
    mapper: _categoryFromResponse,
  );

  Future<List<T>> _listMaster<T>({
    required String table,
    required String companyId,
    required T Function(Object?) mapper,
  }) async {
    try {
      final response = await _client
          .schema('hasad')
          .from(table)
          .select('id,company_id,code,name_ar,is_active')
          .eq('company_id', companyId)
          .order('code');
      return response.map(mapper).toList(growable: false);
    } on PostgrestException catch (error) {
      throw _mapFailure(error, action: 'تحميل البيانات');
    } on Object {
      throw const InventoryFailure('تعذر تحميل البيانات.');
    }
  }

  @override
  Future<UnitOfMeasure> createUnit(UnitOfMeasureDraft draft) => _persistMaster(
    table: 'units_of_measure',
    payload: draft.toJson(),
    create: true,
    mapper: _unitFromResponse,
  );
  @override
  Future<UnitOfMeasure> updateUnit(UnitOfMeasureDraft draft) => _persistMaster(
    table: 'units_of_measure',
    payload: draft.toJson(),
    create: false,
    mapper: _unitFromResponse,
  );
  @override
  Future<ProductCategory> createCategory(ProductCategoryDraft draft) =>
      _persistMaster(
        table: 'product_categories',
        payload: draft.toJson(),
        create: true,
        mapper: _categoryFromResponse,
      );
  @override
  Future<ProductCategory> updateCategory(ProductCategoryDraft draft) =>
      _persistMaster(
        table: 'product_categories',
        payload: draft.toJson(),
        create: false,
        mapper: _categoryFromResponse,
      );

  Future<T> _persistMaster<T>({
    required String table,
    required Map<String, Object?> payload,
    required bool create,
    required T Function(Object?) mapper,
    String duplicateMessage = 'رمز الصنف أو الباركود مستخدم بالفعل.',
    String deniedMessage = 'لا تملك الصلاحية المطلوبة لهذا الإجراء.',
  }) async {
    try {
      final response = create
          ? await _client
                .schema('hasad')
                .from(table)
                .insert(payload)
                .select()
                .single()
          : await _client
                .schema('hasad')
                .from(table)
                .update({...payload}..remove('company_id'))
                .eq('id', payload['id']!)
                .eq('company_id', payload['company_id']!)
                .select()
                .single();
      return mapper(response);
    } on PostgrestException catch (error) {
      throw _mapFailure(
        error,
        action: create ? 'الحفظ' : 'التحديث',
        duplicateMessage: duplicateMessage,
        deniedMessage: deniedMessage,
      );
    } on Object {
      throw const InventoryFailure('تعذر حفظ البيانات.');
    }
  }

  @override
  Future<List<Warehouse>> listWarehouses({required String companyId}) async {
    try {
      final response = await _client
          .schema('hasad')
          .from('warehouses')
          .select('id,company_id,code,name_ar,is_active')
          .eq('company_id', companyId)
          .order('code');
      return response.map(_warehouseFromResponse).toList(growable: false);
    } on PostgrestException catch (error) {
      throw _mapFailure(
        error,
        action: 'تحميل المستودعات',
        deniedMessage: 'لم يتم تفعيل صلاحية إدارة المستودعات بعد.',
      );
    } on Object {
      throw const InventoryFailure('تعذر تحميل المستودعات.');
    }
  }

  @override
  Future<Warehouse> createWarehouse(WarehouseDraft draft) => _persistMaster(
    table: 'warehouses',
    payload: draft.toJson(),
    create: true,
    mapper: _warehouseFromResponse,
    duplicateMessage: 'رمز المستودع مستخدم بالفعل في شركتك.',
    deniedMessage: 'لم يتم تفعيل صلاحية تعديل المستودعات بعد.',
  );

  @override
  Future<Warehouse> updateWarehouse(WarehouseDraft draft) => _persistMaster(
    table: 'warehouses',
    payload: draft.toJson(),
    create: false,
    mapper: _warehouseFromResponse,
    duplicateMessage: 'رمز المستودع مستخدم بالفعل في شركتك.',
    deniedMessage: 'لم يتم تفعيل صلاحية تعديل المستودعات بعد.',
  );

  @override
  Future<List<StockBalance>> listStockBalances({
    required String companyId,
  }) async {
    try {
      final response = await _client
          .schema('hasad')
          .from('stock_levels')
          .select('company_id,product_id,warehouse_id,qty,last_unit_cost')
          .eq('company_id', companyId)
          .order('product_id');
      return response.map(_stockBalanceFromResponse).toList(growable: false);
    } on PostgrestException catch (error) {
      throw _mapFailure(
        error,
        action: 'تحميل أرصدة المخزون',
        deniedMessage: 'لم يتم تفعيل صلاحية قراءة أرصدة المخزون بعد.',
      );
    } on Object {
      throw const InventoryFailure('تعذر تحميل أرصدة المخزون.');
    }
  }

  @override
  Future<List<StockMovement>> listStockMovements({
    required String companyId,
  }) async {
    try {
      final response = await _client
          .schema('hasad')
          .from('stock_movements')
          .select(
            'id,company_id,product_id,warehouse_id,movement_type,direction,'
            'qty,unit_cost,value,seq,source_document_type,source_document_id,'
            'journal_line_id,posted_at',
          )
          .eq('company_id', companyId)
          .order('posted_at', ascending: false)
          .order('seq', ascending: false);
      return response.map(_movementFromResponse).toList(growable: false);
    } on InventoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapStockFailure(error, action: 'تحميل حركات المخزون');
    } on Object {
      throw const InventoryFailure('تعذر تحميل حركات المخزون.');
    }
  }

  @override
  Future<bool> supportsStockPosting({required String companyId}) async {
    // Safe capability probe: qty=0 is rejected by the posting function before
    // any stock write. A missing function means posting is not activated yet.
    try {
      await _client
          .schema('hasad')
          .rpc(
            'post_stock_receipt',
            params: {
              'p_movement_id': const Uuid().v4(),
              'p_company_id': companyId,
              'p_warehouse_id': '00000000-0000-0000-0000-000000000000',
              'p_product_id': '00000000-0000-0000-0000-000000000000',
              'p_qty': 0,
              'p_unit_cost': 0,
            },
          );
      return true;
    } on PostgrestException catch (error) {
      // The only expected response is the function's own QTY_INVALID raise.
      // Missing function, permission denial, expired session, or schema
      // exposure problems must keep posting disabled.
      return error.code == 'P0001';
    } on Object {
      return false;
    }
  }

  @override
  Future<StockMovement> postStockReceipt(StockReceiptDraft draft) async {
    try {
      final response = await _client
          .schema('hasad')
          .rpc(
            'post_stock_receipt',
            params: {
              'p_movement_id': draft.id,
              'p_company_id': draft.companyId,
              'p_warehouse_id': draft.warehouseId,
              'p_product_id': draft.productId,
              'p_qty': draft.qty,
              'p_unit_cost': draft.unitCost,
            },
          );
      return _movementFromResponse(response);
    } on InventoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapStockFailure(error, action: 'ترحيل الاستلام');
    } on Object {
      throw const InventoryFailure('تعذر ترحيل حركة الاستلام.');
    }
  }

  @override
  Future<StockMovement> postStockIssue(StockIssueDraft draft) async {
    try {
      final response = await _client
          .schema('hasad')
          .rpc(
            'post_stock_issue',
            params: {
              'p_movement_id': draft.id,
              'p_company_id': draft.companyId,
              'p_warehouse_id': draft.warehouseId,
              'p_product_id': draft.productId,
              'p_qty': draft.qty,
            },
          );
      return _movementFromResponse(response);
    } on InventoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapStockFailure(error, action: 'ترحيل الصرف');
    } on Object {
      throw const InventoryFailure('تعذر ترحيل حركة الصرف.');
    }
  }

  @override
  Future<void> postStockTransfer(StockTransferDraft draft) async {
    try {
      await _client
          .schema('hasad')
          .rpc(
            'post_stock_transfer',
            params: {
              'p_out_movement_id': draft.outMovementId,
              'p_in_movement_id': draft.inMovementId,
              'p_company_id': draft.companyId,
              'p_source_warehouse_id': draft.sourceWarehouseId,
              'p_destination_warehouse_id': draft.destinationWarehouseId,
              'p_product_id': draft.productId,
              'p_qty': draft.qty,
            },
          );
    } on InventoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapStockFailure(error, action: 'ترحيل التحويل');
    } on Object {
      throw const InventoryFailure('تعذر ترحيل التحويل بين المستودعات.');
    }
  }

  @override
  Future<Product> createProduct(ProductDraft draft) =>
      _persist(draft, create: true);

  @override
  Future<Product> updateProduct(ProductDraft draft) =>
      _persist(draft, create: false);

  Future<Product> _persist(ProductDraft draft, {required bool create}) async {
    final payload = <String, Object?>{
      'id': draft.id,
      'company_id': draft.companyId,
      'code': draft.code.trim(),
      'name_ar': draft.nameAr.trim(),
      'name_en': _nullIfBlank(draft.nameEn),
      'barcode': _nullIfBlank(draft.barcode),
      'base_uom_id': draft.baseUomId,
      'track_inventory': draft.trackInventory,
      'is_active': draft.isActive,
    };
    if (draft.categoryId case final categoryId?) {
      payload['category_id'] = categoryId;
    }
    try {
      final response = create
          ? await _client
                .schema('hasad')
                .from('products')
                .insert(payload)
                .select()
                .single()
          : await _client
                .schema('hasad')
                .from('products')
                .update({...payload}..remove('company_id'))
                .eq('id', draft.id)
                .eq('company_id', draft.companyId)
                .select()
                .single();
      return _productFromResponse(response);
    } on InventoryFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (create) {
        _logProductCreateFailure(error);
      }
      throw _mapFailure(error, action: create ? 'إنشاء الصنف' : 'تحديث الصنف');
    } on Object {
      throw InventoryFailure(
        create ? 'تعذر إنشاء الصنف.' : 'تعذر تحديث الصنف.',
      );
    }
  }

  UnitOfMeasure _unitFromResponse(Object? response) {
    if (response is! Map) {
      throw const InventoryFailure('استجابة وحدات القياس غير صالحة.');
    }
    final value = Map<String, dynamic>.from(response);
    return UnitOfMeasure(
      id: _text(value, 'id'),
      companyId: _text(value, 'company_id'),
      code: _text(value, 'code'),
      nameAr: _text(value, 'name_ar'),
      isBase: _bool(value, 'is_base'),
      isActive: _bool(value, 'is_active'),
    );
  }

  ProductCategory _categoryFromResponse(Object? response) {
    if (response is! Map) {
      throw const InventoryFailure('استجابة التصنيف غير صالحة.');
    }
    final value = Map<String, dynamic>.from(response);
    return ProductCategory(
      id: _text(value, 'id'),
      companyId: _text(value, 'company_id'),
      code: _text(value, 'code'),
      nameAr: _text(value, 'name_ar'),
      isActive: _bool(value, 'is_active'),
    );
  }

  Warehouse _warehouseFromResponse(Object? response) {
    if (response is! Map) {
      throw const InventoryFailure('استجابة المستودع غير صالحة.');
    }
    final value = Map<String, dynamic>.from(response);
    return Warehouse(
      id: _text(value, 'id'),
      companyId: _text(value, 'company_id'),
      code: _text(value, 'code'),
      nameAr: _text(value, 'name_ar'),
      isActive: _bool(value, 'is_active'),
    );
  }

  StockBalance _stockBalanceFromResponse(Object? response) {
    if (response is! Map) {
      throw const InventoryFailure('استجابة أرصدة المخزون غير صالحة.');
    }
    final value = Map<String, dynamic>.from(response);
    return StockBalance(
      companyId: _text(value, 'company_id'),
      productId: _text(value, 'product_id'),
      warehouseId: _text(value, 'warehouse_id'),
      qty: _number(value, 'qty'),
      lastUnitCost: _number(value, 'last_unit_cost'),
    );
  }

  StockMovement _movementFromResponse(Object? response) {
    if (response is! Map) {
      throw const InventoryFailure('استجابة حركات المخزون غير صالحة.');
    }
    final value = Map<String, dynamic>.from(response);
    final postedAt = DateTime.tryParse(_text(value, 'posted_at'));
    if (postedAt == null) {
      throw const InventoryFailure('استجابة حركات المخزون غير صالحة.');
    }
    return StockMovement(
      id: _text(value, 'id'),
      companyId: _text(value, 'company_id'),
      productId: _text(value, 'product_id'),
      warehouseId: _text(value, 'warehouse_id'),
      movementType: _text(value, 'movement_type'),
      direction: _text(value, 'direction'),
      qty: _number(value, 'qty'),
      unitCost: _number(value, 'unit_cost'),
      value: _number(value, 'value'),
      seq: _integer(value, 'seq'),
      postedAt: postedAt,
      sourceDocumentType: _nullableText(value, 'source_document_type'),
      sourceDocumentId: _nullableText(value, 'source_document_id'),
      journalLineId: _nullableText(value, 'journal_line_id'),
    );
  }

  Product _productFromResponse(Object? response) {
    if (response is! Map) {
      throw const InventoryFailure('استجابة الصنف غير صالحة.');
    }
    final value = Map<String, dynamic>.from(response);
    return Product(
      id: _text(value, 'id'),
      companyId: _text(value, 'company_id'),
      code: _text(value, 'code'),
      nameAr: _text(value, 'name_ar'),
      nameEn: _nullableText(value, 'name_en'),
      barcode: _nullableText(value, 'barcode'),
      categoryId: _nullableText(value, 'category_id'),
      baseUomId: _nullableText(value, 'base_uom_id'),
      trackInventory: _bool(value, 'track_inventory'),
      isActive: _bool(value, 'is_active'),
    );
  }

  String _text(Map<String, dynamic> value, String field) {
    final item = value[field];
    if (item is! String || item.trim().isEmpty) {
      throw const InventoryFailure('استجابة الصنف غير صالحة.');
    }
    return item;
  }

  String? _nullableText(Map<String, dynamic> value, String field) =>
      value[field] == null ? null : _text(value, field);
  bool _bool(Map<String, dynamic> value, String field) {
    final item = value[field];
    if (item is! bool) {
      throw const InventoryFailure('استجابة الصنف غير صالحة.');
    }
    return item;
  }

  double _number(Map<String, dynamic> value, String field) {
    final item = value[field];
    if (item is num) return item.toDouble();
    if (item is String) {
      final parsed = double.tryParse(item);
      if (parsed != null) return parsed;
    }
    throw const InventoryFailure('استجابة أرصدة المخزون غير صالحة.');
  }

  int _integer(Map<String, dynamic> value, String field) {
    final item = value[field];
    if (item is int) return item;
    if (item is num) return item.toInt();
    if (item is String) {
      final parsed = int.tryParse(item);
      if (parsed != null) return parsed;
    }
    throw const InventoryFailure('استجابة حركات المخزون غير صالحة.');
  }

  bool _isMissingStockBackend(PostgrestException error) => switch (error.code) {
    'PGRST202' || 'PGRST203' || 'PGRST106' || '3F000' || '42883' => true,
    _ => false,
  };

  String? _nullIfBlank(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  void _logProductCreateFailure(PostgrestException error) {
    final message = error.message
        .replaceAll(
          RegExp(r'\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b'),
          '<uuid>',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    debugPrint(
      'Inventory failure: operation=create_product table=hasad.products '
      'code=${error.code ?? 'unknown'} message=$message',
    );
  }

  InventoryFailure _mapStockFailure(
    PostgrestException error, {
    required String action,
  }) {
    final message = error.message;
    final classifiedCode = classifyStockPostingError(
      error.code,
      message,
      missingBackend: _isMissingStockBackend(error),
    );
    if (message.contains('STOCK_INSUFFICIENT')) {
      return const InventoryFailure(
        'الكمية المتاحة غير كافية لإتمام الحركة.',
        code: 'STOCK_INSUFFICIENT',
      );
    }
    if (message.contains('PRODUCT_NOT_AVAILABLE')) {
      return const InventoryFailure(
        'الصنف غير متاح أو غير مخزني في شركتك.',
        code: 'PRODUCT_NOT_AVAILABLE',
      );
    }
    if (message.contains('WAREHOUSE_NOT_AVAILABLE')) {
      return const InventoryFailure(
        'المستودع غير متاح أو غير نشط.',
        code: 'WAREHOUSE_NOT_AVAILABLE',
      );
    }
    if (message.contains('SAME_WAREHOUSE')) {
      return const InventoryFailure(
        'لا يمكن التحويل إلى نفس المستودع المصدر.',
        code: 'SAME_WAREHOUSE',
      );
    }
    if (message.contains('QTY_INVALID')) {
      return const InventoryFailure(
        'الكمية يجب أن تكون أكبر من صفر.',
        code: 'QTY_INVALID',
      );
    }
    if (message.contains('QTY_PRECISION')) {
      return const InventoryFailure(
        'ط§ظ„ظƒظ…ظٹط© ظ„ط§ ظٹط¬ظˆط² ط£ظ† طھطھط¬ط§ظˆط² ط£ط±ط¨ط¹ ظ…ظ†ط§ط²ظ„ ط¹ط´ط±ظٹط©.',
        code: 'QTY_PRECISION',
      );
    }
    if (message.contains('COST_INVALID')) {
      return const InventoryFailure(
        'تكلفة الوحدة غير صالحة.',
        code: 'COST_INVALID',
      );
    }
    if (message.contains('COST_PRECISION')) {
      return const InventoryFailure(
        'طھظƒظ„ظپط© ط§ظ„ظˆط­ط¯ط© ظ„ط§ ظٹط¬ظˆط² ط£ظ† طھطھط¬ط§ظˆط² ط£ط±ط¨ط¹ ظ…ظ†ط§ط²ظ„ ط¹ط´ط±ظٹط©.',
        code: 'COST_PRECISION',
      );
    }
    if (message.contains('IDEMPOTENCY_CONFLICT')) {
      return const InventoryFailure(
        'تم اكتشاف طلب مكرر أو مختلف بنفس المعرّف. لم تُغيَّر الأرصدة.',
        code: 'IDEMPOTENCY_CONFLICT',
      );
    }
    if (message.contains('INVALID_ARGUMENT')) {
      return const InventoryFailure(
        'بيانات الحركة غير مكتملة.',
        code: 'INVALID_ARGUMENT',
      );
    }
    if (message.contains('UNAUTHENTICATED') || message.contains('FORBIDDEN')) {
      return const InventoryFailure(
        'لا تملك صلاحية ترحيل حركات المخزون لهذه الشركة.',
        code: 'DENIED',
      );
    }
    if (classifiedCode == 'BACKEND_NOT_CONFIGURED') {
      return const InventoryFailure(
        'لم يتم تفعيل ترحيل حركات المخزون بعد.',
        code: 'BACKEND_NOT_CONFIGURED',
      );
    }
    return switch (classifiedCode) {
      'DENIED' when action == 'تحميل حركات المخزون' => const InventoryFailure(
        'لم يتم تفعيل صلاحية قراءة حركات المخزون بعد.',
        code: 'DENIED',
      ),
      'DENIED' => const InventoryFailure(
        'لا تملك صلاحية تنفيذ عملية الترحيل.',
        code: 'DENIED',
      ),
      'DUPLICATE' => const InventoryFailure(
        'تم اكتشاف حركة مكررة. لم تُغيَّر الأرصدة.',
        code: 'DUPLICATE',
      ),
      'VALIDATION' => const InventoryFailure(
        'بيانات الحركة غير صالحة.',
        code: 'VALIDATION',
      ),
      _ => InventoryFailure('تعذر $action بأمان.', code: classifiedCode),
    };
  }

  InventoryFailure _mapFailure(
    PostgrestException error, {
    required String action,
    String duplicateMessage = 'رمز الصنف أو الباركود مستخدم بالفعل.',
    String deniedMessage = 'لا تملك الصلاحية المطلوبة لهذا الإجراء.',
  }) => switch (error.code) {
    '23505' => InventoryFailure(duplicateMessage, code: 'DUPLICATE'),
    '23503' => const InventoryFailure(
      'وحدة القياس المحددة غير متاحة لشركتك.',
      code: 'REFERENCE_INVALID',
    ),
    '42501' => InventoryFailure(deniedMessage, code: 'DENIED'),
    'PGRST106' || '3F000' => const InventoryFailure(
      'لم يتم تفعيل وصول بيانات المخزون بعد.',
      code: 'BACKEND_NOT_CONFIGURED',
    ),
    _ => InventoryFailure('تعذر $action بأمان.', code: error.code),
  };
}
