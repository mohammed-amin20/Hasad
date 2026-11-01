import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/company/application/company_context_controller.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/inventory/data/inventory_repository.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';
import 'package:hasad_erp_v2/inventory/presentation/inventory_display.dart';
import 'package:hasad_erp_v2/inventory/presentation/stock_movement_dialogs.dart';

class StockMovementsScreen extends StatefulWidget {
  const StockMovementsScreen({super.key, required this.controller});
  final CompanyContextController controller;

  @override
  State<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends State<StockMovementsScreen> {
  static const _pageSize = 20;

  final _repository = SupabaseInventoryRepository();
  final _searchController = TextEditingController();
  List<Warehouse> _warehouses = const [];
  List<StockBalance> _balances = const [];
  List<StockMovement> _movements = const [];
  bool _loading = true;
  bool _postingAvailable = false;
  String? _error;
  String? _movementsError;
  String? _typeFilter;
  String? _warehouseFilter;
  String? _productFilter;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final companyId = widget.controller.context?.companyId;
    if (companyId == null) {
      setState(() {
        _loading = false;
        _error = 'سياق الشركة غير جاهز بعد.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _movementsError = null;
    });
    try {
      final warehouses = await _repository.listWarehouses(companyId: companyId);
      final balances = await _repository.listStockBalances(
        companyId: companyId,
      );
      List<StockMovement> movements = const [];
      String? movementsError;
      try {
        movements = await _repository.listStockMovements(companyId: companyId);
      } on InventoryFailure catch (error) {
        movementsError = error.message;
      }
      final postingAvailable = await _repository.supportsStockPosting(
        companyId: companyId,
      );
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _balances = balances;
        _movements = movements;
        _movementsError = movementsError;
        _postingAvailable = postingAvailable;
      });
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Warehouse> get _activeWarehouses =>
      _warehouses.where((warehouse) => warehouse.isActive).toList();

  List<Product> get _activeProducts => widget.controller.products
      .where((product) => product.isActive && product.trackInventory)
      .toList(growable: false);

  Future<void> _openReceipt() async {
    final products = _activeProducts;
    final warehouses = _activeWarehouses;
    if (products.isEmpty || warehouses.isEmpty) {
      HasadNotification.show(
        context,
        'أضف صنفًا مخزنيًا نشطًا ومستودعًا نشطًا قبل تسجيل الاستلام.',
      );
      return;
    }
    final posted = await showDialog<bool>(
      context: context,
      builder: (context) => StockReceiptDialog(
        companyId: widget.controller.context!.companyId,
        repository: _repository,
        warehouses: warehouses,
        products: products,
      ),
    );
    if (posted == true && mounted) {
      HasadNotification.show(context, 'تم ترحيل حركة الاستلام بنجاح.');
      await _load();
    }
  }

  Future<void> _openIssue() async {
    final products = _activeProducts;
    final warehouses = _activeWarehouses;
    if (products.isEmpty || warehouses.isEmpty) {
      HasadNotification.show(
        context,
        'أضف صنفًا مخزنيًا نشطًا ومستودعًا نشطًا قبل تسجيل الصرف.',
      );
      return;
    }
    final posted = await showDialog<bool>(
      context: context,
      builder: (context) => StockIssueDialog(
        companyId: widget.controller.context!.companyId,
        repository: _repository,
        warehouses: warehouses,
        products: products,
        balances: _balances,
      ),
    );
    if (posted == true && mounted) {
      HasadNotification.show(context, 'تم ترحيل حركة الصرف بنجاح.');
      await _load();
    }
  }

  Future<void> _openTransfer() async {
    final products = _activeProducts;
    final warehouses = _activeWarehouses;
    if (products.isEmpty || warehouses.length < 2) {
      HasadNotification.show(
        context,
        'يتطلب التحويل صنفًا مخزنيًا نشطًا ومستودعين نشطين على الأقل.',
      );
      return;
    }
    final posted = await showDialog<bool>(
      context: context,
      builder: (context) => StockTransferDialog(
        companyId: widget.controller.context!.companyId,
        repository: _repository,
        warehouses: warehouses,
        products: products,
        balances: _balances,
      ),
    );
    if (posted == true && mounted) {
      HasadNotification.show(context, 'تم ترحيل التحويل بين المستودعين.');
      await _load();
    }
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _typeFilter = null;
      _warehouseFilter = null;
      _productFilter = null;
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.controller.products;
    final productsById = {for (final product in products) product.id: product};
    final warehousesById = {
      for (final warehouse in _warehouses) warehouse.id: warehouse,
    };
    final filtered = _filteredMovements(productsById, warehousesById);
    final totalPages = filtered.isEmpty
        ? 1
        : ((filtered.length - 1) ~/ _pageSize) + 1;
    final page = _page.clamp(0, totalPages - 1);
    final pageItems = filtered
        .skip(page * _pageSize)
        .take(_pageSize)
        .toList(growable: false);
    final today = DateTime.now();
    final todayCount = _movements.where((movement) {
      final local = movement.postedAt.toLocal();
      return local.year == today.year &&
          local.month == today.month &&
          local.day == today.day;
    }).length;
    final distinctProducts = _movements
        .map((movement) => movement.productId)
        .toSet()
        .length;
    final latest = _movements.isEmpty ? null : _movements.first.postedAt;
    final hasFilters =
        _searchController.text.trim().isNotEmpty ||
        _typeFilter != null ||
        _warehouseFilter != null ||
        _productFilter != null;
    final movementTypes =
        _movements.map((movement) => movement.movementType).toSet().toList()
          ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HasadPageHeader(
          title: 'حركات المخزون',
          subtitle:
              'لوحة حقيقية للاستلام والصرف والتحويل، مع سجل كامل من قاعدة '
              'البيانات.',
          trailing: HasadPrimaryButton(
            label: 'تحديث',
            icon: Icons.refresh,
            onPressed: _loading ? null : _load,
          ),
        ),
        const SizedBox(height: 24),
        if (_loading)
          const SizedBox(
            height: 420,
            child: HasadLoadingState(label: 'جارٍ تحميل حركات المخزون...'),
          )
        else if (_error != null)
          SizedBox(
            height: 420,
            child: HasadErrorState(message: _error!, onRetry: _load),
          )
        else ...[
          _PostingBanner(
            available: _postingAvailable,
            onRefresh: _loading ? null : _load,
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth > 980
                  ? (constraints.maxWidth - 32) / 3
                  : constraints.maxWidth > 620
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: HasadMetricCard(
                      label: 'إجمالي الحركات',
                      value: _movementsError == null
                          ? '${_movements.length}'
                          : '—',
                      note: latest == null
                          ? 'لا توجد حركات مسجلة'
                          : 'آخر ترحيل: ${formatInventoryDateTime(latest)}',
                      icon: Icons.swap_horiz_rounded,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: HasadMetricCard(
                      label: 'حركات اليوم',
                      value: _movementsError == null ? '$todayCount' : '—',
                      note: 'حسب تاريخ الترحيل المحلي',
                      icon: Icons.today_outlined,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: HasadMetricCard(
                      label: 'أصناف متحركة',
                      value: _movementsError == null
                          ? '$distinctProducts'
                          : '—',
                      note: 'عدد الأصناف ذات الحركات المسجلة',
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          HasadCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                HasadPrimaryButton(
                  label: 'استلام مخزون',
                  icon: Icons.move_to_inbox_outlined,
                  onPressed: _postingAvailable ? _openReceipt : null,
                ),
                OutlinedButton.icon(
                  onPressed: _postingAvailable ? _openIssue : null,
                  icon: const Icon(Icons.outbox_outlined),
                  label: const Text('صرف مخزون'),
                ),
                OutlinedButton.icon(
                  onPressed: _postingAvailable && _activeWarehouses.length > 1
                      ? _openTransfer
                      : null,
                  icon: const Icon(Icons.compare_arrows_rounded),
                  label: const Text('تحويل بين المستودعات'),
                ),
                if (_activeWarehouses.length < 2)
                  const Text(
                    'يتطلب التحويل مستودعين نشطين على الأقل.',
                    style: TextStyle(color: HasadPalette.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          HasadCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سجل الحركات',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'كل سطر يمثل حركة مخزون فعلية مرحّلة. السجل للقراءة فقط.',
                  style: TextStyle(color: HasadPalette.muted),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 300,
                      child: HasadSearchField(
                        controller: _searchController,
                        hint: 'بحث بالصنف أو المستودع أو النوع',
                        onChanged: (_) => setState(() => _page = 0),
                      ),
                    ),
                    DropdownButton<String?>(
                      value: _typeFilter,
                      hint: const Text('كل الأنواع'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('كل الأنواع'),
                        ),
                        ...movementTypes.map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(stockMovementTypeLabel(type)),
                          ),
                        ),
                      ],
                      onChanged: _loading
                          ? null
                          : (value) => setState(() {
                              _typeFilter = value;
                              _page = 0;
                            }),
                    ),
                    DropdownButton<String?>(
                      value: _warehouseFilter,
                      hint: const Text('كل المستودعات'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('كل المستودعات'),
                        ),
                        ..._warehouses.map(
                          (warehouse) => DropdownMenuItem(
                            value: warehouse.id,
                            child: Text(
                              '${warehouse.nameAr} (${warehouse.code})',
                            ),
                          ),
                        ),
                      ],
                      onChanged: _loading
                          ? null
                          : (value) => setState(() {
                              _warehouseFilter = value;
                              _page = 0;
                            }),
                    ),
                    DropdownButton<String?>(
                      value: _productFilter,
                      hint: const Text('كل الأصناف'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('كل الأصناف'),
                        ),
                        ...products.map(
                          (product) => DropdownMenuItem(
                            value: product.id,
                            child: Text('${product.nameAr} (${product.code})'),
                          ),
                        ),
                      ],
                      onChanged: _loading
                          ? null
                          : (value) => setState(() {
                              _productFilter = value;
                              _page = 0;
                            }),
                    ),
                    if (hasFilters)
                      TextButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(Icons.filter_alt_off_outlined),
                        label: const Text('مسح عوامل التصفية'),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_movementsError != null)
                  HasadErrorState(message: _movementsError!, onRetry: _load)
                else if (_movements.isEmpty)
                  const HasadEmptyState(
                    icon: Icons.swap_horiz_outlined,
                    title: 'لا توجد حركات مخزون',
                    message:
                        'لم تُرحَّل أي حركة بعد. سجّل استلامًا أو صرفًا لتظهر '
                        'الحركة هنا فور نجاح المعاملة على الخادم.',
                  )
                else if (filtered.isEmpty)
                  HasadEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'لا توجد نتائج مطابقة',
                    message: 'جرّب تغيير البحث أو عوامل التصفية.',
                    action: TextButton(
                      onPressed: _resetFilters,
                      child: const Text('مسح عوامل التصفية'),
                    ),
                  )
                else ...[
                  HasadDataTable(
                    columns: const [
                      DataColumn(label: Text('التاريخ')),
                      DataColumn(label: Text('النوع')),
                      DataColumn(label: Text('الصنف')),
                      DataColumn(label: Text('المستودع')),
                      DataColumn(label: Text('الكمية')),
                      DataColumn(label: Text('تكلفة الوحدة')),
                      DataColumn(label: Text('القيمة')),
                      DataColumn(label: Text('المرجع')),
                    ],
                    rows: pageItems
                        .map(
                          (movement) => DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  formatInventoryDateTime(movement.postedAt),
                                ),
                              ),
                              DataCell(
                                _MovementTypeBadge(type: movement.movementType),
                              ),
                              DataCell(
                                Text(
                                  _productLabel(
                                    productsById[movement.productId],
                                    movement.productId,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  _warehouseLabel(
                                    warehousesById[movement.warehouseId],
                                    movement.warehouseId,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${movement.direction == 'in' ? '+' : '−'}'
                                  '${formatInventoryQty(movement.qty)}',
                                  style: TextStyle(
                                    color: movement.direction == 'in'
                                        ? HasadPalette.success
                                        : HasadPalette.danger,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(formatInventoryMoney(movement.unitCost)),
                              ),
                              DataCell(
                                Text(formatInventoryMoney(movement.value)),
                              ),
                              DataCell(Text(_referenceLabel(movement))),
                            ],
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'إجمالي ${filtered.length} حركة • صفحة ${page + 1} '
                          'من $totalPages',
                          style: const TextStyle(
                            color: HasadPalette.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: page > 0
                            ? () => setState(() => _page = page - 1)
                            : null,
                        child: const Text('السابق'),
                      ),
                      TextButton(
                        onPressed: page + 1 < totalPages
                            ? () => setState(() => _page = page + 1)
                            : null,
                        child: const Text('التالي'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<StockMovement> _filteredMovements(
    Map<String, Product> productsById,
    Map<String, Warehouse> warehousesById,
  ) {
    final search = _searchController.text.trim().toLowerCase();
    return _movements
        .where((movement) {
          if (_typeFilter != null && movement.movementType != _typeFilter) {
            return false;
          }
          if (_warehouseFilter != null &&
              movement.warehouseId != _warehouseFilter) {
            return false;
          }
          if (_productFilter != null && movement.productId != _productFilter) {
            return false;
          }
          if (search.isEmpty) return true;
          final haystack = [
            _productLabel(productsById[movement.productId], movement.productId),
            _warehouseLabel(
              warehousesById[movement.warehouseId],
              movement.warehouseId,
            ),
            stockMovementTypeLabel(movement.movementType),
            _referenceLabel(movement),
            formatInventoryDateTime(movement.postedAt),
          ].join(' ').toLowerCase();
          return haystack.contains(search);
        })
        .toList(growable: false);
  }
}

class _PostingBanner extends StatelessWidget {
  const _PostingBanner({required this.available, required this.onRefresh});
  final bool available;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => HasadCard(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          available ? Icons.verified_outlined : Icons.lock_clock_outlined,
          color: available ? HasadPalette.success : HasadPalette.warning,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                available
                    ? 'ترحيل حركات المخزون مفعّل'
                    : 'ترحيل حركات المخزون غير مفعّل بعد',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                available
                    ? 'تُنفَّذ الحركات في معاملة ذرية واحدة على الخادم، ولا '
                          'تُكتب الأرصدة مباشرة من التطبيق.'
                    : 'الشاشة جاهزة، لكن أزرار الترحيل تبقى معطّلة حتى اعتماد '
                          'وتفعيل عملية الترحيل الذرية على بيئة DEV.',
                style: const TextStyle(
                  color: HasadPalette.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (!available)
          TextButton(onPressed: onRefresh, child: const Text('إعادة الفحص')),
      ],
    ),
  );
}

class _MovementTypeBadge extends StatelessWidget {
  const _MovementTypeBadge({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final color = stockMovementTypeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stockMovementTypeIcon(type), size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            stockMovementTypeLabel(type),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

String _productLabel(Product? product, String productId) => product == null
    ? 'صنف ${productId.substring(0, productId.length < 8 ? productId.length : 8)}'
    : '${product.nameAr} (${product.code})';

String _warehouseLabel(Warehouse? warehouse, String warehouseId) =>
    warehouse == null
    ? 'مستودع ${warehouseId.substring(0, warehouseId.length < 8 ? warehouseId.length : 8)}'
    : '${warehouse.nameAr} (${warehouse.code})';

String _referenceLabel(StockMovement movement) {
  final type = movement.sourceDocumentType;
  if (type == null || type.trim().isEmpty) return '—';
  final label = switch (type) {
    'sales_invoice' => 'فاتورة مبيعات',
    'purchase_invoice' => 'فاتورة مشتريات',
    'stock_transfer' => 'تحويل مخزون',
    'manual' => 'إدخال يدوي',
    _ => type,
  };
  final id = movement.sourceDocumentId;
  if (id == null) return label;
  final shortId = id.substring(0, id.length < 8 ? id.length : 8);
  return '$label • $shortId';
}
