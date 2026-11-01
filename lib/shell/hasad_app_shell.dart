import 'package:flutter/material.dart';
import 'package:hasad_erp_v2/auth/application/auth_controller.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';
import 'package:hasad_erp_v2/company/application/company_context_controller.dart';
import 'package:hasad_erp_v2/company/domain/company_context.dart';
import 'package:hasad_erp_v2/customers/presentation/customers_screen.dart';
import 'package:hasad_erp_v2/design/hasad_components.dart';
import 'package:hasad_erp_v2/design/hasad_logo.dart';
import 'package:hasad_erp_v2/design/hasad_theme.dart';
import 'package:hasad_erp_v2/inventory/presentation/product_management_screen.dart';
import 'package:hasad_erp_v2/inventory/presentation/master_data_screen.dart';
import 'package:hasad_erp_v2/inventory/presentation/stock_balances_screen.dart';
import 'package:hasad_erp_v2/inventory/presentation/stock_movements_screen.dart';
import 'package:hasad_erp_v2/inventory/presentation/warehouse_management_screen.dart';
import 'package:hasad_erp_v2/sales/dev/s3_posting_smoke_contract.dart';
import 'package:hasad_erp_v2/sales/dev/s3_posting_smoke_screen.dart';
import 'package:hasad_erp_v2/sales/presentation/sales_invoices_screen.dart';

class HasadAppShell extends StatefulWidget {
  const HasadAppShell({
    super.key,
    required this.authController,
    required this.session,
    required this.controller,
  });

  final AuthController authController;
  final AuthSession session;
  final CompanyContextController controller;

  @override
  State<HasadAppShell> createState() => _HasadAppShellState();
}

class _HasadAppShellState extends State<HasadAppShell> {
  var _collapsed = false;
  var _selectedId = 'dashboard';

  void _select(String id) => setState(() => _selectedId = id);

  @override
  Widget build(BuildContext context) {
    final company = widget.controller.context!;
    final selected = _visibleItems.firstWhere((item) => item.id == _selectedId);
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    title: selected.label,
                    company: company,
                    onToggleSidebar: () =>
                        setState(() => _collapsed = !_collapsed),
                    onSignOut: widget.authController.signOut,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey(_selectedId),
                        child: _PageBody(
                          selectedId: _selectedId,
                          company: company,
                          controller: widget.controller,
                          onNavigate: _select,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            HasadSidebar(
              collapsed: _collapsed,
              selectedId: _selectedId,
              onSelected: _select,
              companyName: company.companyName,
            ),
          ],
        ),
      ),
    );
  }
}

class HasadSidebar extends StatelessWidget {
  const HasadSidebar({
    super.key,
    required this.collapsed,
    required this.selectedId,
    required this.onSelected,
    required this.companyName,
  });

  final bool collapsed;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final String companyName;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    width: collapsed ? 82 : 276,
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    color: HasadPalette.navyDeep,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          child: collapsed
              ? const HasadBrandLockup(compact: true, onDark: true)
              : const HasadBrandLockup(onDark: true),
        ),
        if (!collapsed)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.business_outlined,
                  color: Color(0xFFFFC46B),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
            children: [
              for (final section in _visibleSections) ...[
                if (!collapsed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 7),
                    child: Text(
                      section.title,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                for (final item in section.items)
                  _SideItem(
                    item: item,
                    selected: item.id == selectedId,
                    collapsed: collapsed,
                    onTap: () => onSelected(item.id),
                  ),
              ],
            ],
          ),
        ),
        if (!collapsed)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'حصاد ERP • بيئة تدريبية',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
            ),
          ),
      ],
    ),
  );
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });
  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Tooltip(
      message: collapsed ? item.label : '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('nav-${item.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            height: 44,
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFB45309) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  item.icon,
                  color: selected ? Colors.white : const Color(0xFFCBD5E1),
                  size: 20,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFFE2E8F0),
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HasadTopBar extends StatelessWidget {
  const HasadTopBar({
    super.key,
    required this.title,
    required this.company,
    required this.onToggleSidebar,
    required this.onSignOut,
  });
  final String title;
  final CompanyContext company;
  final VoidCallback onToggleSidebar;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => _TopBar(
    title: title,
    company: company,
    onToggleSidebar: onToggleSidebar,
    onSignOut: onSignOut,
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.company,
    required this.onToggleSidebar,
    required this.onSignOut,
  });
  final String title;
  final CompanyContext company;
  final VoidCallback onToggleSidebar;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: HasadPalette.border)),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: 'طي القائمة',
          onPressed: onToggleSidebar,
          icon: const Icon(Icons.menu_open_rounded),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Tooltip(
          message: 'التنبيهات',
          child: IconButton(
            onPressed: () => HasadNotification.show(
              context,
              'لا توجد تنبيهات متصلة بالبيانات حالياً.',
            ),
            icon: const Badge(
              smallSize: 7,
              child: Icon(Icons.notifications_none_rounded),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'حسابي',
          onSelected: (value) async {
            if (value == 'signout') await onSignOut();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'signout', child: Text('تسجيل الخروج')),
          ],
          child: CircleAvatar(
            backgroundColor: const Color(0xFFFFF3E1),
            foregroundColor: HasadPalette.amberDark,
            child: Text(
              company.companyName.isEmpty
                  ? 'ح'
                  : company.companyName.characters.first,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.selectedId,
    required this.company,
    required this.controller,
    required this.onNavigate,
  });
  final String selectedId;
  final CompanyContext company;
  final CompanyContextController controller;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final content = switch (selectedId) {
      'dashboard' => _Dashboard(
        company: company,
        controller: controller,
        onNavigate: onNavigate,
      ),
      'products' => ProductManagementScreen(controller: controller),
      'uoms' => MasterDataScreen(
        companyId: company.companyId,
        type: MasterDataType.unit,
      ),
      'categories' => MasterDataScreen(
        companyId: company.companyId,
        type: MasterDataType.category,
      ),
      'warehouses' => WarehouseManagementScreen(companyId: company.companyId),
      'stock_levels' => StockBalancesScreen(controller: controller),
      'stock_moves' => StockMovementsScreen(controller: controller),
      'customers' => CustomersScreen(companyId: company.companyId),
      'sales_invoices' => SalesInvoicesScreen(companyId: company.companyId),
      'sales_create' => SalesInvoicesScreen(
        companyId: company.companyId,
        openEditor: true,
      ),
      'dev_s3_smoke' => S3PostingSmokeScreen(
        selectedCompanyId: company.companyId,
      ),
      'about' => const _AboutPage(),
      _ => _UnavailablePage(
        item: _visibleItems.firstWhere((item) => item.id == selectedId),
      ),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: content,
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.company,
    required this.controller,
    required this.onNavigate,
  });
  final CompanyContext company;
  final CompanyContextController controller;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      HasadPageHeader(
        title: 'مرحباً بك في ${company.companyName}',
        subtitle: 'نظرة سريعة على بيانات شركتك المتاحة حالياً.',
        trailing: HasadStatusBadge(
          label: company.isOwner ? 'حساب مالك' : 'حساب مستخدم',
          color: HasadPalette.success,
        ),
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, constraints) {
          final count = constraints.maxWidth > 1050
              ? 4
              : constraints.maxWidth > 700
              ? 2
              : 1;
          final cards = [
            HasadMetricCard(
              label: 'الأصناف',
              value: '${controller.products.length}',
              note: 'قيمة فعلية من قائمة الأصناف',
              icon: Icons.inventory_2_outlined,
            ),
            const HasadMetricCard(
              label: 'المبيعات',
              value: 'غير متاح',
              note: 'بانتظار ربط بيانات المبيعات',
              icon: Icons.receipt_long_outlined,
            ),
            const HasadMetricCard(
              label: 'المشتريات',
              value: 'غير متاح',
              note: 'بانتظار ربط بيانات المشتريات',
              icon: Icons.shopping_bag_outlined,
            ),
            const HasadMetricCard(
              label: 'التنبيهات',
              value: 'غير متاح',
              note: 'بانتظار مصدر تنبيهات حقيقي',
              icon: Icons.notifications_active_outlined,
            ),
          ];
          return GridView.count(
            crossAxisCount: count,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: count == 1 ? 3.5 : 2.15,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: cards,
          );
        },
      ),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            SizedBox(
              width: constraints.maxWidth > 900
                  ? (constraints.maxWidth - 18) * .62
                  : constraints.maxWidth,
              child: HasadCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إجراءات سريعة',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        HasadPrimaryButton(
                          label: 'عرض الأصناف',
                          icon: Icons.inventory_2_outlined,
                          onPressed: () => onNavigate('products'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => HasadDialog.show(
                            context,
                            title: 'قيد التطوير',
                            message: 'إنشاء الأصناف يتطلب صلاحيات كتابة مستقلة ولم يتم تفعيله بعد.',
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة صنف'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: constraints.maxWidth > 900
                  ? (constraints.maxWidth - 18) * .38
                  : constraints.maxWidth,
              child: HasadCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'النشاط الأخير',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'سيظهر النشاط هنا عند ربط مصدر بيانات فعلي.',
                      style: TextStyle(color: HasadPalette.muted),
                    ),
                    const SizedBox(height: 18),
                    const HasadEmptyState(
                      icon: Icons.history_toggle_off_outlined,
                      title: 'لا يوجد نشاط معروض',
                      message: 'لا يتم عرض بيانات تجريبية في حصاد.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _UnavailablePage extends StatelessWidget {
  const _UnavailablePage({required this.item});
  final _NavItem item;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      HasadPageHeader(
        title: item.label,
        subtitle: 'واجهة جاهزة ضمن هيكل حصاد الموحد.',
      ),
      const SizedBox(height: 24),
      HasadCard(
        child: SizedBox(
          height: 390,
          child: HasadEmptyState(
            icon: item.icon,
            title: 'هذه الوظيفة قيد التطوير',
            message: 'تم تجهيز هذه الشاشة للتنقل وتجربة الاستخدام. ستُربط بالبيانات الحقيقية فقط بعد توفر صلاحيات وعمليات خلفية معتمدة.',
          ),
        ),
      ),
    ],
  );
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const HasadPageHeader(
        title: 'معلومات النظام',
        subtitle: 'حصاد ERP — بيئة تطوير وتدريب.',
      ),
      const SizedBox(height: 24),
      HasadCard(
        child: Row(
          children: [
            const HasadLogo(size: 92),
            const SizedBox(width: 22),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حصاد ERP',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'نظام عربي متكامل لإدارة الأعمال، مصمم لواجهة سطح مكتب عملية ومتدرجة الربط بالبيانات الفعلية.',
                    style: TextStyle(color: HasadPalette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _NavSection {
  const _NavSection(this.title, this.items);
  final String title;
  final List<_NavItem> items;
}

class _NavItem {
  const _NavItem(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const _sections = [
  _NavSection('الرئيسية', [
    _NavItem('dashboard', 'لوحة التحكم', Icons.dashboard_outlined),
  ]),
  _NavSection('المبيعات', [
    _NavItem('sales_invoices', 'فواتير المبيعات', Icons.receipt_long_outlined),
    _NavItem('sales_create', 'إنشاء فاتورة', Icons.add_chart_outlined),
    _NavItem('quotes', 'عروض الأسعار', Icons.request_quote_outlined),
    _NavItem(
      'sales_returns',
      'مرتجعات المبيعات',
      Icons.assignment_return_outlined,
    ),
    _NavItem('customers', 'العملاء', Icons.people_outline),
    _NavItem('receipts', 'سندات القبض', Icons.payments_outlined),
  ]),
  _NavSection('المشتريات', [
    _NavItem(
      'purchase_invoices',
      'فواتير المشتريات',
      Icons.shopping_bag_outlined,
    ),
    _NavItem(
      'purchase_create',
      'إنشاء فاتورة شراء',
      Icons.add_shopping_cart_outlined,
    ),
    _NavItem(
      'purchase_orders',
      'طلبات الشراء',
      Icons.playlist_add_check_outlined,
    ),
    _NavItem(
      'purchase_returns',
      'مرتجعات المشتريات',
      Icons.assignment_returned_outlined,
    ),
    _NavItem('suppliers', 'الموردون', Icons.groups_outlined),
    _NavItem(
      'disbursements',
      'سندات الصرف',
      Icons.account_balance_wallet_outlined,
    ),
  ]),
  _NavSection('المخزون', [
    _NavItem('products', 'الأصناف', Icons.inventory_2_outlined),
    _NavItem('categories', 'التصنيفات', Icons.category_outlined),
    _NavItem('uoms', 'وحدات القياس', Icons.straighten_outlined),
    _NavItem('warehouses', 'المستودعات', Icons.warehouse_outlined),
    _NavItem('stock_levels', 'أرصدة المخزون', Icons.stacked_bar_chart_outlined),
    _NavItem('stock_moves', 'حركات المخزون', Icons.swap_horiz_outlined),
    _NavItem('stock_count', 'الجرد', Icons.fact_check_outlined),
    _NavItem(
      'transfers',
      'التحويلات بين المستودعات',
      Icons.compare_arrows_outlined,
    ),
  ]),
  _NavSection('المالية', [
    _NavItem('cash', 'الصندوق', Icons.account_balance_wallet_outlined),
    _NavItem('accounts', 'الحسابات', Icons.account_tree_outlined),
    _NavItem('journals', 'القيود اليومية', Icons.menu_book_outlined),
    _NavItem('expenses', 'المصروفات', Icons.request_page_outlined),
    _NavItem('receivables', 'الذمم المدينة', Icons.trending_up_outlined),
    _NavItem('payables', 'الذمم الدائنة', Icons.trending_down_outlined),
  ]),
  _NavSection('التقارير', [
    _NavItem('sales_reports', 'تقارير المبيعات', Icons.bar_chart_outlined),
    _NavItem(
      'purchase_reports',
      'تقارير المشتريات',
      Icons.query_stats_outlined,
    ),
    _NavItem('inventory_reports', 'تقارير المخزون', Icons.inventory_outlined),
    _NavItem('profit_reports', 'تقارير الأرباح', Icons.insights_outlined),
    _NavItem(
      'party_reports',
      'تقارير العملاء والموردين',
      Icons.assessment_outlined,
    ),
  ]),
  _NavSection('الإدارة', [
    _NavItem(
      'company_settings',
      'إعدادات الشركة',
      Icons.business_center_outlined,
    ),
    _NavItem('users', 'المستخدمون والصلاحيات', Icons.manage_accounts_outlined),
    _NavItem('general_settings', 'الإعدادات العامة', Icons.tune_outlined),
    _NavItem('about', 'معلومات النظام', Icons.info_outline),
  ]),
];

/// The DEV posting diagnostic is compiled in only when the owner opts in and
/// the app is configured for the authorized DEV project. No other build sees
/// the navigation entry or can route to the screen.
List<_NavSection> get _visibleSections {
  if (!S3PostingSmokeContract.isEnabled) return _sections;
  return [
    ..._sections,
    const _NavSection('تشخيص DEV', [
      _NavItem(
        'dev_s3_smoke',
        'ترحيل S3 لمرة واحدة',
        Icons.science_outlined,
      ),
    ]),
  ];
}

final _visibleItems = _visibleSections
    .expand((section) => section.items)
    .toList(growable: false);
