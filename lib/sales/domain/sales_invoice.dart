import 'package:hasad_erp_v2/sales/domain/invoice_calculations.dart';

enum SalesInvoiceStatus { draft, posted, cancelled }

SalesInvoiceStatus salesInvoiceStatusFromDb(String value) => switch (value) {
  'draft' => SalesInvoiceStatus.draft,
  'posted' => SalesInvoiceStatus.posted,
  'cancelled' => SalesInvoiceStatus.cancelled,
  _ => throw FormatException('Unknown sales invoice status: $value'),
};

String salesInvoiceStatusLabel(SalesInvoiceStatus status) => switch (status) {
  SalesInvoiceStatus.draft => 'مسودة',
  SalesInvoiceStatus.posted => 'مرحّلة',
  SalesInvoiceStatus.cancelled => 'ملغاة',
};

bool canTransitionInvoiceStatus(
  SalesInvoiceStatus from,
  SalesInvoiceStatus to,
) => switch ((from, to)) {
  (SalesInvoiceStatus.draft, SalesInvoiceStatus.posted) ||
  (SalesInvoiceStatus.draft, SalesInvoiceStatus.cancelled) => true,
  _ => false,
};

void requireSalesCompanyScope(Iterable<String> companyIds, String companyId) {
  if (companyIds.any((value) => value != companyId)) {
    throw const SalesCompanyScopeFailure();
  }
}

class SalesCompanyScopeFailure implements Exception {
  const SalesCompanyScopeFailure();
}

class SalesInvoice {
  const SalesInvoice({
    required this.id,
    required this.companyId,
    required this.partyId,
    required this.docDate,
    required this.status,
    required this.vatMode,
    required this.documentTypeId,
    required this.fiscalYearId,
    required this.net,
    required this.tax,
    required this.gross,
    required this.idempotencyKey,
    this.documentNo,
    this.postedAt,
  });

  final String id;
  final String companyId;
  final String partyId;
  final DateTime docDate;
  final SalesInvoiceStatus status;
  final VatMode vatMode;
  final String documentTypeId;
  final String fiscalYearId;
  final InvoiceAmount net;
  final InvoiceAmount tax;
  final InvoiceAmount gross;

  /// Server-generated with the draft and reused for the one atomic posting
  /// request. Flutter never generates a replacement key at posting time.
  final String idempotencyKey;
  final String? documentNo;
  final DateTime? postedAt;

  factory SalesInvoice.fromJson(Map<String, dynamic> json) => SalesInvoice(
    id: _required(json, 'id'),
    companyId: _required(json, 'company_id'),
    partyId: _required(json, 'party_id'),
    docDate: DateTime.parse(_required(json, 'doc_date')),
    status: salesInvoiceStatusFromDb(_required(json, 'status')),
    vatMode: _required(json, 'vat_mode') == 'inclusive'
        ? VatMode.inclusive
        : VatMode.exclusive,
    documentTypeId: _required(json, 'doc_type_id'),
    fiscalYearId: _required(json, 'fiscal_year_id'),
    net: _amount(json['net']),
    tax: _amount(json['tax']),
    gross: _amount(json['gross']),
    idempotencyKey: _required(json, 'idempotency_key'),
    documentNo: _nullable(json['doc_no']),
    postedAt: json['posted_at'] == null
        ? null
        : DateTime.tryParse('${json['posted_at']}'),
  );
}

/// Confirmed result of the sole server-side posting operation.
class SalesPostingResult {
  const SalesPostingResult({
    required this.invoice,
    required this.journalEntryId,
    required this.journalEntryNo,
    required this.replayed,
  });

  final SalesInvoice invoice;
  final String journalEntryId;
  final String journalEntryNo;
  final bool replayed;

  factory SalesPostingResult.fromJson(Map<String, dynamic> json) {
    final document = json['document'];
    if (document is! Map) {
      throw const FormatException('Missing posted document');
    }
    final replayed = json['replayed'];
    if (replayed is! bool) {
      throw const FormatException('Invalid posting replay marker');
    }
    return SalesPostingResult(
      invoice: SalesInvoice.fromJson(Map<String, dynamic>.from(document)),
      journalEntryId: _required(json, 'journal_entry_id'),
      journalEntryNo: _required(json, 'journal_entry_no'),
      replayed: replayed,
    );
  }
}

class SalesInvoiceLine {
  const SalesInvoiceLine({
    required this.id,
    required this.companyId,
    required this.documentId,
    required this.lineNo,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.net,
    required this.tax,
    required this.gross,
    this.productId,
    this.warehouseId,
    this.taxRateMillis,
  });

  final String id;
  final String companyId;
  final String documentId;
  final int lineNo;
  final InvoiceQuantity quantity;
  final InvoiceAmount unitPrice;
  final InvoiceAmount discount;
  final InvoiceAmount net;
  final InvoiceAmount tax;
  final InvoiceAmount gross;
  final String? productId;
  final String? warehouseId;
  final int? taxRateMillis;

  factory SalesInvoiceLine.fromJson(Map<String, dynamic> json) =>
      SalesInvoiceLine(
        id: _required(json, 'id'),
        companyId: _required(json, 'company_id'),
        documentId: _required(json, 'document_id'),
        lineNo: int.parse('${json['line_no']}'),
        quantity: InvoiceQuantity.tryParse('${json['qty']}')!,
        unitPrice: InvoiceAmount.tryParse('${json['unit_price']}')!,
        discount: InvoiceAmount.tryParse('${json['discount_amount']}')!,
        net: _amount(json['net']),
        tax: _amount(json['tax']),
        gross: _amount(json['gross']),
        productId: _nullable(json['product_id']),
        warehouseId: _nullable(json['warehouse_id']),
        taxRateMillis: _taxRate(json['tax_rate']),
      );
}

class SalesDocumentType {
  const SalesDocumentType({
    required this.id,
    required this.companyId,
    required this.code,
    required this.nameAr,
    required this.issuance,
    required this.isActive,
  });
  final String id;
  final String companyId;
  final String code;
  final String nameAr;
  final String issuance;
  final bool isActive;
  factory SalesDocumentType.fromJson(Map<String, dynamic> json) =>
      SalesDocumentType(
        id: _required(json, 'id'),
        companyId: _required(json, 'company_id'),
        code: _required(json, 'code'),
        nameAr: _required(json, 'name_ar'),
        issuance: _required(json, 'issuance'),
        isActive: json['is_active'] == true,
      );
}

class FiscalYearOption {
  const FiscalYearOption({
    required this.id,
    required this.companyId,
    required this.startDate,
    required this.endDate,
    required this.status,
  });
  final String id;
  final String companyId;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  factory FiscalYearOption.fromJson(Map<String, dynamic> json) =>
      FiscalYearOption(
        id: _required(json, 'id'),
        companyId: _required(json, 'company_id'),
        startDate: DateTime.parse(_required(json, 'start_date')),
        endDate: DateTime.parse(_required(json, 'end_date')),
        status: _required(json, 'status'),
      );
}

class SalesInvoiceDraft {
  const SalesInvoiceDraft({
    required this.id,
    required this.companyId,
    required this.partyId,
    required this.docDate,
    required this.vatMode,
    required this.documentTypeId,
    required this.fiscalYearId,
    required this.idempotencyKey,
    required this.lines,
  });
  final String id;
  final String companyId;
  final String partyId;
  final DateTime docDate;
  final VatMode vatMode;
  final String documentTypeId;
  final String fiscalYearId;
  final String idempotencyKey;
  final List<SalesInvoiceDraftLine> lines;

  Map<String, Object?> toRpcParams() {
    final linePayload = <Map<String, Object?>>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final totals = calculateInvoiceLine(
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        discount: line.discount,
        taxRateMillis: line.taxRateMillis,
        vatMode: vatMode,
      );
      linePayload.add({
        'id': line.id,
        'line_no': index + 1,
        'product_id': line.productId,
        'warehouse_id': line.warehouseId,
        'qty': line.quantity.toDecimalString(),
        'unit_price': line.unitPrice.toDecimalString(),
        'discount_amount': line.discount.toDecimalString(),
        'tax_rate': _taxRateString(line.taxRateMillis),
        'net': totals.net.toDecimalString(),
        'tax': totals.tax.toDecimalString(),
        'gross': totals.gross.toDecimalString(),
      });
    }
    return {
      'p_document_id': id,
      'p_company_id': companyId,
      'p_party_id': partyId,
      'p_doc_date': docDate.toIso8601String().substring(0, 10),
      'p_vat_mode': vatMode == VatMode.inclusive ? 'inclusive' : 'exclusive',
      'p_document_type_id': documentTypeId,
      'p_fiscal_year_id': fiscalYearId,
      'p_idempotency_key': idempotencyKey,
      'p_lines': linePayload,
    };
  }
}

class SalesInvoiceDraftLine {
  const SalesInvoiceDraftLine({
    required this.id,
    required this.productId,
    required this.warehouseId,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRateMillis,
  });
  final String id;
  final String productId;
  final String? warehouseId;
  final InvoiceQuantity quantity;
  final InvoiceAmount unitPrice;
  final InvoiceAmount discount;
  final int taxRateMillis;
}

String _required(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('Missing $key');
  return value;
}

String? _nullable(Object? value) =>
    value is String && value.isNotEmpty ? value : null;
InvoiceAmount _amount(Object? value) =>
    InvoiceAmount.tryParse('$value') ??
    (throw FormatException('Invalid money value'));
int? _taxRate(Object? value) =>
    value == null ? null : parseTaxRateMillis('$value');
String _taxRateString(int millis) =>
    '${millis ~/ 1000}.${(millis % 1000).toString().padLeft(3, '0')}';
