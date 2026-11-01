import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/company/application/company_context_controller.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/inventory/data/inventory_repository.dart';
import 'package:hasad_erp_v2/inventory/domain/inventory_models.dart';

class StockBalancesScreen extends StatefulWidget {
  const StockBalancesScreen({super.key, required this.controller});
  final CompanyContextController controller;
  @override
  State<StockBalancesScreen> createState() => _StockBalancesScreenState();
}

class _StockBalancesScreenState extends State<StockBalancesScreen> {
  final _repository = SupabaseInventoryRepository();
  List<Warehouse> _warehouses = const [];
  List<StockBalance> _balances = const [];
  bool _loading = true;
  String? _error;
  String? _warehouseId;
  String? _productId;

  @override
  void initState() {
    super.initState();
    _load();
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
    });
    try {
      final warehouses = await _repository.listWarehouses(companyId: companyId);
      final balances = await _repository.listStockBalances(
        companyId: companyId,
      );
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _balances = balances;
      });
    } on InventoryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetFilters() => setState(() {
    _warehouseId = null;
    _productId = null;
  });

  @override
  Widget build(BuildContext context) {
    final products = widget.controller.products;
    final productsById = {for (final product in products) product.id: product};
    final warehousesById = {
      for (final warehouse in _warehouses) warehouse.id: warehouse,
    };
    final filtered = _balances
        .where(
          (balance) =>
              (_warehouseId == null || balance.warehouseId == _warehouseId) &&
              (_productId == null || balance.productId == _productId),
        )
        .toList();
    filtered.sort(
      (first, second) =>
          _productLabel(
            productsById[first.productId],
            first.productId,
          ).compareTo(
            _productLabel(productsById[second.productId], second.productId),
          ),
    );
    final hasFilters = _warehouseId != null || _productId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HasadPageHeader(
          title: 'أرصدة المخزون',
          subtitle: 'أرصدة فعلية للقراءة فقط من مستودعات الشركة الحالية.',
          trailing: HasadPrimaryButton(
            label: 'تحديث',
            icon: Icons.refresh,
            onPressed: _loading ? null : _load,
          ),
        ),
        const SizedBox(height: 24),
        HasadCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: HasadPalette.warning),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'لا يتم تعديل الأرصدة مباشرة من هذه الشاشة. تُحدَّث الكميات فقط من خلال حركات المخزون المعتمدة.',
                  style: TextStyle(color: HasadPalette.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        HasadCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String?>(
                    value: _warehouseId,
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
                        : (value) => setState(() => _warehouseId = value),
                  ),
                  DropdownButton<String?>(
                    value: _productId,
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
                        : (value) => setState(() => _productId = value),
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
              if (_loading)
                const HasadLoadingState(label: 'جارٍ تحميل أرصدة المخزون...')
              else if (_error != null)
                HasadErrorState(message: _error!, onRetry: _load)
              else if (_balances.isEmpty)
                const HasadEmptyState(
                  icon: Icons.stacked_bar_chart_outlined,
                  title: 'لا توجد أرصدة مخزون',
                  message: 'لم تُسجل أي كميات فعلية بعد. تُحدَّث الأرصدة من خلال حركات المخزون المعتمدة.',
                )
              else if (filtered.isEmpty)
                HasadEmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'لا توجد نتائج مطابقة',
                  message: 'جرّب اختيار مستودع أو صنف آخر.',
                  action: TextButton(
                    onPressed: _resetFilters,
                    child: const Text('مسح عوامل التصفية'),
                  ),
                )
              else
                HasadDataTable(
                  columns: const [
                    DataColumn(label: Text('الصنف')),
                    DataColumn(label: Text('المستودع')),
                    DataColumn(label: Text('الكمية')),
                    DataColumn(label: Text('آخر تكلفة وحدة')),
                  ],
                  rows: filtered
                      .map(
                        (balance) => DataRow(
                          cells: [
                            DataCell(
                              Text(
                                _productLabel(
                                  productsById[balance.productId],
                                  balance.productId,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                _warehouseLabel(
                                  warehousesById[balance.warehouseId],
                                  balance.warehouseId,
                                ),
                              ),
                            ),
                            DataCell(Text(_formatQuantity(balance.qty))),
                            DataCell(
                              Text(_formatQuantity(balance.lastUnitCost)),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _productLabel(Product? product, String productId) => product == null
      ? 'صنف ${productId.substring(0, productId.length < 8 ? productId.length : 8)}'
      : '${product.nameAr} (${product.code})';

  String _warehouseLabel(Warehouse? warehouse, String warehouseId) =>
      warehouse == null
      ? 'مستودع ${warehouseId.substring(0, warehouseId.length < 8 ? warehouseId.length : 8)}'
      : '${warehouse.nameAr} (${warehouse.code})';

  String _formatQuantity(double value) {
    final fixed = value.toStringAsFixed(4);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
