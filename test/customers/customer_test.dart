import 'package:flutter_test/flutter_test.dart';
import 'package:hasad_erp_v2/customers/domain/customer.dart';
import 'package:hasad_erp_v2/customers/domain/customer_validation.dart';

void main() {
  group('customer validation', () {
    test('requires customer code and Arabic name', () {
      expect(validateCustomerCode('  '), isNotNull);
      expect(validateCustomerCode('C-1'), isNull);
      expect(validateCustomerName(null), isNotNull);
      expect(validateCustomerName('العميل'), isNull);
    });

    test('payment terms are optional nonnegative whole days', () {
      expect(validatePaymentTerms(''), isNull);
      expect(validatePaymentTerms('0'), isNull);
      expect(validatePaymentTerms('30'), isNull);
      expect(validatePaymentTerms('-1'), isNotNull);
      expect(validatePaymentTerms('2.5'), isNotNull);
    });
  });

  test('customer drafts match the parties API shape and retain no balance', () {
    const draft = CustomerDraft(
      id: 'party-id',
      companyId: 'company-id',
      code: ' C-1 ',
      nameAr: ' عميل ',
      partyType: 'individual',
      isSupplier: true,
      isActive: true,
      phone: ' 123 ',
      paymentTermsDays: 30,
    );

    expect(draft.toInsertJson(), {
      'id': 'party-id',
      'company_id': 'company-id',
      'code': 'C-1',
      'name_ar': 'عميل',
      'name_en': null,
      'party_type': 'individual',
      'is_customer': true,
      'is_supplier': true,
      'tax_id': null,
      'phone': '123',
      'email': null,
      'address': null,
      'payment_terms_days': 30,
      'is_active': true,
    });
    expect(draft.toUpdateJson().containsKey('company_id'), isFalse);
    expect(draft.toUpdateJson().containsKey('balance'), isFalse);
  });

  test('customer parser rejects an invalid required schema value', () {
    expect(() => Customer.fromJson({'id': 'id'}), throwsFormatException);
  });
}
