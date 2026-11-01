import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/company/application/company_context_controller.dart';
import 'package:hasad_erp_v2/company/data/company_context_repository.dart';
import 'package:hasad_erp_v2/company/domain/company_context.dart';
import 'package:hasad_erp_v2/company/domain/company_context_service.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('loads the current active company through direct table reads', () async {
    final client = _FakeDataClient(
      membership: {'company_id': 'company-a', 'is_owner': true},
      company: {'id': 'company-a'},
      settings: {'company_id': 'company-a', 'display_name': 'أبو أمين'},
    );
    final gateway = CompanyContextApiGateway(dataClient: client);

    final context = await gateway.fetchWhoami();

    expect(client.calls, [
      'membership:current-user',
      'company:company-a',
      'settings:company-a',
    ]);
    expect(context.companyId, 'company-a');
    expect(context.companyName, 'أبو أمين');
    expect(context.isOwner, isTrue);
  });

  test(
    'uses a safe fallback name when active company settings are absent',
    () async {
      final gateway = CompanyContextApiGateway(
        dataClient: _FakeDataClient(
          membership: {'company_id': 'company-a', 'is_owner': true},
          company: {'id': 'company-a'},
        ),
      );

      final context = await gateway.fetchWhoami();

      expect(context.companyName, 'الشركة الحالية');
    },
  );

  test(
    'does not make direct table requests without an authenticated session',
    () async {
      final client = _FakeDataClient(authenticated: false);
      final gateway = CompanyContextApiGateway(dataClient: client);

      await expectLater(
        gateway.fetchWhoami(),
        throwsA(
          isA<CompanyContextFailure>().having(
            (failure) => failure.code,
            'code',
            'UNAUTHENTICATED',
          ),
        ),
      );
      expect(client.calls, isEmpty);
    },
  );

  test(
    'maps direct Data API permission failures without exposing details',
    () async {
      final gateway = CompanyContextApiGateway(
        dataClient: _FakeDataClient(
          error: const PostgrestException(message: 'DENIED', code: '42501'),
        ),
      );

      await expectLater(
        gateway.fetchWhoami(),
        throwsA(
          isA<CompanyContextFailure>().having(
            (failure) => failure.code,
            'code',
            'DENIED',
          ),
        ),
      );
    },
  );

  test(
    'parses products returned from the caller company table query',
    () async {
      final client = _FakeDataClient(
        products: [
          {
            'id': 'product-a',
            'company_id': 'company-a',
            'code': 'A-01',
            'name_ar': 'منتج أ',
            'name_en': null,
            'barcode': null,
            'category_id': null,
            'base_uom_id': 'uom-a',
            'track_inventory': true,
            'is_active': true,
          },
        ],
      );
      final gateway = CompanyContextApiGateway(dataClient: client);

      final products = await gateway.fetchProducts(companyId: 'company-a');

      expect(client.calls, ['products:company-a']);
      expect(products.single.companyId, 'company-a');
      expect(products.single.code, 'A-01');
    },
  );

  test(
    'clears previous-company products when a later bootstrap fails',
    () async {
      final service = _SequencedService();
      final controller = CompanyContextController(service);

      await controller.loadContext();
      expect(controller.products, hasLength(1));

      service.failNextContextLoad = true;
      await controller.loadContext();

      expect(controller.context, isNull);
      expect(controller.products, isEmpty);
      expect(controller.state, CompanyContextState.noMembership);
    },
  );
}

class _FakeDataClient implements CompanyContextDataClient {
  _FakeDataClient({
    this.authenticated = true,
    this.membership,
    this.company,
    this.settings,
    this.products,
    this.error,
  });

  final bool authenticated;
  @override
  String? get currentUserId => 'current-user';
  final Object? membership;
  final Object? company;
  final Object? settings;
  final Object? products;
  final Object? error;
  final List<String> calls = [];

  @override
  bool get hasAuthenticatedSession => authenticated;

  @override
  Future<Object?> fetchActiveMembership({required String userId}) =>
      _response('membership:$userId', membership);

  @override
  Future<Object?> fetchActiveCompany({required String companyId}) =>
      _response('company:$companyId', company);

  @override
  Future<Object?> fetchCompanySettings({required String companyId}) =>
      _response('settings:$companyId', settings);

  @override
  Future<Object?> fetchProducts({required String companyId}) =>
      _response('products:$companyId', products);

  Future<Object?> _response(String call, Object? response) async {
    calls.add(call);
    if (error case final error?) {
      throw error;
    }
    return response;
  }
}

class _SequencedService implements CompanyContextService {
  bool failNextContextLoad = false;

  @override
  Future<CompanyContext> getCurrentContext() async {
    if (failNextContextLoad) {
      throw const CompanyContextFailure('لا توجد عضوية', code: 'NO_MEMBERSHIP');
    }
    return const CompanyContext(
      companyId: 'company-a',
      companyName: 'شركة أ',
      isOwner: true,
      roleCode: null,
    );
  }

  @override
  Future<List<Product>> getProducts({required String companyId}) async =>
      const [
        Product(
          id: 'product-a',
          companyId: 'company-a',
          code: 'A-01',
          nameAr: 'منتج أ',
        ),
      ];
}
