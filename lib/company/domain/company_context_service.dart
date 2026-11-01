import 'package:hasad_erp_v2/company/domain/company_context.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';

abstract class CompanyContextGateway {
  Future<CompanyContext> fetchWhoami();
  Future<List<Product>> fetchProducts({required String companyId});
}

abstract class CompanyContextService {
  Future<CompanyContext> getCurrentContext();
  Future<List<Product>> getProducts({required String companyId});
}
