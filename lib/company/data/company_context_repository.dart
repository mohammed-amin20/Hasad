import 'package:hasad_erp_v2/company/domain/company_context.dart';
import 'package:hasad_erp_v2/company/domain/company_context_service.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompanyContextRepository implements CompanyContextService {
  CompanyContextRepository(this._gateway);

  final CompanyContextGateway _gateway;

  @override
  Future<CompanyContext> getCurrentContext() => _gateway.fetchWhoami();

  @override
  Future<List<Product>> getProducts({required String companyId}) =>
      _gateway.fetchProducts(companyId: companyId);
}

abstract class CompanyContextDataClient {
  bool get hasAuthenticatedSession;
  String? get currentUserId;

  Future<Object?> fetchActiveMembership({required String userId});
  Future<Object?> fetchActiveCompany({required String companyId});
  Future<Object?> fetchCompanySettings({required String companyId});
  Future<Object?> fetchProducts({required String companyId});
}

class CompanyContextApiGateway implements CompanyContextGateway {
  CompanyContextApiGateway({this.dataClient});

  CompanyContextDataClient? dataClient;

  CompanyContextDataClient get _client => dataClient ??=
      _SupabaseCompanyContextDataClient(Supabase.instance.client);

  @override
  Future<CompanyContext> fetchWhoami() async {
    try {
      _requireAuthenticatedSession();
      final userId = _client.currentUserId;
      if (userId == null || userId.isEmpty) {
        throw const CompanyContextFailure(
          'انتهت جلسة الدخول أو لم تعد صالحة. سجل الدخول مرة أخرى.',
          code: 'UNAUTHENTICATED',
        );
      }

      final membershipResponse = await _client.fetchActiveMembership(
        userId: userId,
      );
      if (membershipResponse == null) {
        throw const CompanyContextFailure(
          'لا توجد عضوية شركة نشطة لهذا المستخدم.',
          code: 'NO_MEMBERSHIP',
        );
      }
      if (membershipResponse is! Map) {
        throw const CompanyContextFailure(
          'استجابة سياق الشركة غير صالحة. تم إيقاف الوصول بأمان.',
          code: 'UNEXPECTED_RESPONSE',
        );
      }
      final membership = Map<String, dynamic>.from(membershipResponse);
      final companyId = _requiredText(membership, 'company_id');
      final isOwner = membership['is_owner'];
      if (isOwner is! bool) {
        throw const CompanyContextFailure(
          'استجابة سياق الشركة غير صالحة. تم إيقاف الوصول بأمان.',
          code: 'UNEXPECTED_RESPONSE',
        );
      }

      final companyResponse = await _client.fetchActiveCompany(
        companyId: companyId,
      );
      if (companyResponse == null) {
        throw const CompanyContextFailure(
          'لا توجد عضوية شركة نشطة لهذا المستخدم.',
          code: 'NO_MEMBERSHIP',
        );
      }
      if (companyResponse is! Map) {
        throw const CompanyContextFailure(
          'استجابة سياق الشركة غير صالحة. تم إيقاف الوصول بأمان.',
          code: 'UNEXPECTED_RESPONSE',
        );
      }

      final settingsResponse = await _client.fetchCompanySettings(
        companyId: companyId,
      );
      if (settingsResponse != null && settingsResponse is! Map) {
        throw const CompanyContextFailure(
          'استجابة إعدادات الشركة غير صالحة. تم إيقاف الوصول بأمان.',
          code: 'UNEXPECTED_RESPONSE',
        );
      }
      final settings = settingsResponse == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(settingsResponse as Map);

      return CompanyContext(
        companyId: companyId,
        companyName: _companyName(settings),
        isOwner: isOwner,
        roleCode: null,
      );
    } on CompanyContextFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrestFailure(error, action: 'company context');
    } on Object {
      throw const CompanyContextFailure(
        'تعذر الاتصال بخدمة الشركة. لم يتم عرض أي بيانات محفوظة.',
        code: 'NETWORK_OR_UNAVAILABLE',
      );
    }
  }

  @override
  Future<List<Product>> fetchProducts({required String companyId}) async {
    try {
      _requireAuthenticatedSession();
      final response = await _client.fetchProducts(companyId: companyId);
      if (response is! List) {
        throw const CompanyContextFailure(
          'استجابة قائمة المنتجات غير صالحة. تم إيقاف العرض بأمان.',
          code: 'UNEXPECTED_RESPONSE',
        );
      }
      return response.map(_productFromResponse).toList(growable: false);
    } on CompanyContextFailure {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrestFailure(error, action: 'products');
    } on Object {
      throw const CompanyContextFailure(
        'تعذر تحميل المنتجات. لم يتم عرض أي بيانات محفوظة.',
        code: 'NETWORK_OR_UNAVAILABLE',
      );
    }
  }

  void _requireAuthenticatedSession() {
    if (!_client.hasAuthenticatedSession) {
      throw const CompanyContextFailure(
        'انتهت جلسة الدخول أو لم تعد صالحة. سجل الدخول مرة أخرى.',
        code: 'UNAUTHENTICATED',
      );
    }
  }

  String _companyName(Map<String, dynamic> settings) {
    final displayName = _nullableText(settings, 'display_name');
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName;
    }
    final nameAr = _nullableText(settings, 'name_ar');
    if (nameAr != null && nameAr.trim().isNotEmpty) {
      return nameAr;
    }
    return 'الشركة الحالية';
  }

  Product _productFromResponse(Object? response) {
    if (response is! Map) {
      throw const CompanyContextFailure(
        'استجابة قائمة المنتجات غير صالحة. تم إيقاف العرض بأمان.',
        code: 'UNEXPECTED_RESPONSE',
      );
    }
    final data = Map<String, dynamic>.from(response);
    return Product(
      id: _requiredText(data, 'id'),
      companyId: _requiredText(data, 'company_id'),
      code: _requiredText(data, 'code'),
      nameAr: _requiredText(data, 'name_ar'),
      nameEn: _nullableText(data, 'name_en'),
      barcode: _nullableText(data, 'barcode'),
      categoryId: _nullableText(data, 'category_id'),
      baseUomId: _nullableText(data, 'base_uom_id'),
      trackInventory: _requiredBool(data, 'track_inventory'),
      isActive: _requiredBool(data, 'is_active'),
    );
  }

  String _requiredText(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      throw const CompanyContextFailure(
        'استجابة الخدمة غير صالحة. تم إيقاف الوصول بأمان.',
        code: 'UNEXPECTED_RESPONSE',
      );
    }
    return value;
  }

  String? _nullableText(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw const CompanyContextFailure(
        'استجابة الخدمة غير صالحة. تم إيقاف الوصول بأمان.',
        code: 'UNEXPECTED_RESPONSE',
      );
    }
    return value;
  }

  bool _requiredBool(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! bool) {
      throw const CompanyContextFailure(
        'استجابة الخدمة غير صالحة. تم إيقاف الوصول بأمان.',
        code: 'UNEXPECTED_RESPONSE',
      );
    }
    return value;
  }

  CompanyContextFailure _mapPostgrestFailure(
    PostgrestException error, {
    required String action,
  }) {
    switch (error.code) {
      case '28000':
        return const CompanyContextFailure(
          'انتهت جلسة الدخول أو لم تعد صالحة. سجل الدخول مرة أخرى.',
          code: 'UNAUTHENTICATED',
          serverCode: '28000',
        );
      case '42501':
        return const CompanyContextFailure(
          'لا تملك الصلاحية المطلوبة لهذا الإجراء.',
          code: 'DENIED',
          serverCode: '42501',
        );
      case 'PGRST106':
      case '3F000':
        return const CompanyContextFailure(
          'لم يتم تفعيل وصول بيانات الشركة بعد.',
          code: 'BACKEND_NOT_CONFIGURED',
        );
      default:
        return CompanyContextFailure(
          'تعذر إكمال طلب $action بأمان.',
          code: 'DATA_UNAVAILABLE',
          serverCode: error.code,
        );
    }
  }
}

class _SupabaseCompanyContextDataClient implements CompanyContextDataClient {
  _SupabaseCompanyContextDataClient(this._client);

  final SupabaseClient _client;

  @override
  bool get hasAuthenticatedSession => _client.auth.currentSession != null;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<Object?> fetchActiveMembership({required String userId}) => _client
      .schema('hasad')
      .from('company_memberships')
      .select('company_id,is_owner')
      .eq('user_id', userId)
      .eq('status', 'active')
      .maybeSingle();

  @override
  Future<Object?> fetchActiveCompany({required String companyId}) => _client
      .schema('hasad')
      .from('companies')
      .select('id')
      .eq('id', companyId)
      .eq('status', 'active')
      .maybeSingle();

  @override
  Future<Object?> fetchCompanySettings({required String companyId}) => _client
      .schema('hasad')
      .from('company_settings')
      .select('company_id,display_name,name_ar')
      .eq('company_id', companyId)
      .maybeSingle();

  @override
  Future<Object?> fetchProducts({required String companyId}) => _client
      .schema('hasad')
      .from('products')
      .select(
        'id,company_id,code,name_ar,name_en,barcode,category_id,base_uom_id,track_inventory,is_active',
      )
      .eq('company_id', companyId)
      .order('code');
}
