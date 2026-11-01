/// Per-RPC diagnostic result for the safe RPC connectivity check.
///
/// Deliberately carries no payload data: only the RPC name, a coarse outcome,
/// the sanitized PostgREST/PostgreSQL error code and a fixed failure category.
/// Never add company ids, user ids, emails, tokens or row data here.
///
/// The installed PostgREST client (postgrest 2.9.1) does not expose the HTTP
/// status code on [PostgrestException], so no status is recorded rather than
/// guessing one. The error code is the authoritative server signal.
enum RpcDiagnosticOutcome { pass, denied, error, notRun }

class RpcDiagnosticResult {
  const RpcDiagnosticResult({
    required this.rpc,
    required this.outcome,
    this.postgrestCode,
    this.category,
  });

  factory RpcDiagnosticResult.pass(String rpc) =>
      RpcDiagnosticResult(rpc: rpc, outcome: RpcDiagnosticOutcome.pass);

  factory RpcDiagnosticResult.notRun(String rpc) =>
      RpcDiagnosticResult(rpc: rpc, outcome: RpcDiagnosticOutcome.notRun);

  factory RpcDiagnosticResult.error(
    String rpc, {
    required String category,
    String? postgrestCode,
  }) => RpcDiagnosticResult(
    rpc: rpc,
    outcome: RpcDiagnosticOutcome.error,
    postgrestCode: postgrestCode,
    category: category,
  );

  /// Classifies a server failure from its sanitized code only.
  factory RpcDiagnosticResult.fromPostgrestCode(String rpc, String? code) {
    final safeCode = _sanitizeCode(code);
    if (safeCode == '42501') {
      return RpcDiagnosticResult(
        rpc: rpc,
        outcome: RpcDiagnosticOutcome.denied,
        postgrestCode: safeCode,
        category: 'INSUFFICIENT_PRIVILEGE',
      );
    }
    return RpcDiagnosticResult.error(
      rpc,
      postgrestCode: safeCode,
      category: _categoryForCode(safeCode),
    );
  }

  final String rpc;
  final RpcDiagnosticOutcome outcome;
  final String? postgrestCode;
  final String? category;

  bool get isPass => outcome == RpcDiagnosticOutcome.pass;

  /// Sanitized single line, safe to display and to copy into a report.
  String get summary {
    final buffer = StringBuffer('$rpc=${_outcomeLabel(outcome)}');
    if (postgrestCode case final code? when code.isNotEmpty) {
      buffer.write(' code=$code');
    }
    if (category case final category?) {
      buffer.write(' category=$category');
    }
    return buffer.toString();
  }
}

String? _sanitizeCode(String? code) =>
    code != null && RegExp(r'^[A-Z0-9]{5,7}$').hasMatch(code) ? code : null;

String _outcomeLabel(RpcDiagnosticOutcome outcome) => switch (outcome) {
  RpcDiagnosticOutcome.pass => 'PASS',
  RpcDiagnosticOutcome.denied => 'DENIED',
  RpcDiagnosticOutcome.error => 'ERROR',
  RpcDiagnosticOutcome.notRun => 'NOT_RUN',
};

String _categoryForCode(String? code) => switch (code) {
  '28000' => 'UNAUTHENTICATED',
  'P0001' => 'NO_MEMBERSHIP',
  '3F000' => 'INVALID_SCHEMA',
  '42P01' => 'UNDEFINED_TABLE',
  '42P17' => 'INVALID_OBJECT_DEFINITION',
  'PGRST106' => 'SCHEMA_NOT_EXPOSED',
  'PGRST202' => 'RPC_NOT_FOUND',
  'PGRST301' => 'INVALID_JWT',
  null => 'RPC_FAILED',
  _ => 'RPC_FAILED',
};
