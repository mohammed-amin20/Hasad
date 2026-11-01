import 'package:hasad_erp_v2/customers/domain/customer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class CustomerRepository {
  Future<List<Customer>> listCustomers({required String companyId});
  Future<Customer> createCustomer(CustomerDraft draft);
  Future<Customer> updateCustomer(CustomerDraft draft);
}

class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _columns =
      'id,company_id,code,name_ar,name_en,party_type,is_customer,is_supplier,'
      'tax_id,phone,email,address,payment_terms_days,is_active';

  @override
  Future<List<Customer>> listCustomers({required String companyId}) async {
    try {
      final rows = await _client
          .schema('hasad')
          .from('parties')
          .select(_columns)
          .eq('company_id', companyId)
          .eq('is_customer', true)
          .order('code');
      return rows.map((row) => Customer.fromJson(row)).toList(growable: false);
    } on PostgrestException catch (error) {
      throw _mapFailure(error);
    } on FormatException {
      throw const CustomerFailure(
        'تعذر قراءة بيانات العملاء من قاعدة البيانات.',
        code: 'INVALID_RESPONSE',
      );
    } on Object {
      throw const CustomerFailure('تعذر تحميل العملاء. حاول مرة أخرى.');
    }
  }

  @override
  Future<Customer> createCustomer(CustomerDraft draft) async {
    try {
      final row = await _client
          .schema('hasad')
          .from('parties')
          .insert(draft.toInsertJson())
          .select(_columns)
          .single();
      return Customer.fromJson(row);
    } on PostgrestException catch (error) {
      throw _mapFailure(error);
    } on FormatException {
      throw const CustomerFailure(
        'تعذر قراءة بيانات العميل المحفوظ.',
        code: 'INVALID_RESPONSE',
      );
    } on Object {
      throw const CustomerFailure('تعذر حفظ العميل. حاول مرة أخرى.');
    }
  }

  @override
  Future<Customer> updateCustomer(CustomerDraft draft) async {
    try {
      final row = await _client
          .schema('hasad')
          .from('parties')
          .update(draft.toUpdateJson())
          .eq('company_id', draft.companyId)
          .eq('id', draft.id)
          .eq('is_customer', true)
          .select(_columns)
          .single();
      return Customer.fromJson(row);
    } on PostgrestException catch (error) {
      throw _mapFailure(error);
    } on FormatException {
      throw const CustomerFailure(
        'تعذر قراءة بيانات العميل بعد التحديث.',
        code: 'INVALID_RESPONSE',
      );
    } on Object {
      throw const CustomerFailure('تعذر تحديث العميل. حاول مرة أخرى.');
    }
  }

  CustomerFailure _mapFailure(PostgrestException error) => switch (error.code) {
    '42501' => const CustomerFailure(
      'ليست لديك صلاحية لإدارة عملاء هذه الشركة.',
      code: 'DENIED',
    ),
    '23505' => const CustomerFailure(
      'رمز العميل مستخدم مسبقاً في هذه الشركة.',
      code: 'DUPLICATE_CODE',
    ),
    '23514' || '22003' => const CustomerFailure(
      'تحقق من بيانات العميل والقيم المدخلة.',
      code: 'VALIDATION',
    ),
    'PGRST116' => const CustomerFailure(
      'العميل غير موجود أو لم يعد متاحاً في هذه الشركة.',
      code: 'NOT_FOUND',
    ),
    _ => const CustomerFailure('تعذر إكمال العملية. حاول مرة أخرى.'),
  };
}

class CustomerFailure implements Exception {
  const CustomerFailure(this.message, {this.code});

  final String message;
  final String? code;
}
