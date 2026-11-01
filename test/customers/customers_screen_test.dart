import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/customers/data/customer_repository.dart';
import 'package:hasad_erp_v2/customers/domain/customer.dart';
import 'package:hasad_erp_v2/customers/presentation/customers_screen.dart';

void main() {
  testWidgets('loads company-scoped customers and filters by search', (
    tester,
  ) async {
    final repository = _FakeCustomerRepository([
      _customer(id: 'one', code: 'C-001', name: 'شركة النخيل'),
      _customer(id: 'two', code: 'C-002', name: 'مؤسسة الندى'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomersScreen(
              companyId: 'company-1',
              repository: repository,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.lastCompanyId, 'company-1');
    expect(find.text('شركة النخيل'), findsOneWidget);
    expect(find.text('مؤسسة الندى'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'النخيل');
    await tester.pumpAndSettle();
    expect(find.text('شركة النخيل'), findsOneWidget);
    expect(find.text('مؤسسة الندى'), findsNothing);
  });

  testWidgets('does not display a row returned for another company', (
    tester,
  ) async {
    final repository = _FakeCustomerRepository([
      _customer(
        id: 'foreign',
        code: 'FOREIGN',
        name: 'بيانات خارج الشركة',
        companyId: 'company-2',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomersScreen(
              companyId: 'company-1',
              repository: repository,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('بيانات خارج الشركة'), findsNothing);
    expect(find.textContaining('خارج سياق الشركة'), findsOneWidget);
  });
}

Customer _customer({
  required String id,
  required String code,
  required String name,
  String companyId = 'company-1',
}) => Customer(
  id: id,
  companyId: companyId,
  code: code,
  nameAr: name,
  partyType: 'company',
  isCustomer: true,
  isSupplier: false,
  isActive: true,
);

class _FakeCustomerRepository implements CustomerRepository {
  _FakeCustomerRepository(this.rows);

  final List<Customer> rows;
  String? lastCompanyId;

  @override
  Future<List<Customer>> listCustomers({required String companyId}) async {
    lastCompanyId = companyId;
    return rows;
  }

  @override
  Future<Customer> createCustomer(CustomerDraft draft) =>
      throw UnimplementedError();

  @override
  Future<Customer> updateCustomer(CustomerDraft draft) =>
      throw UnimplementedError();
}
