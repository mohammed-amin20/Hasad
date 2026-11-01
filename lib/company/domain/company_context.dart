class CompanyContext {
  const CompanyContext({
    required this.companyId,
    required this.companyName,
    required this.isOwner,
    required this.roleCode,
  });

  final String companyId;
  final String companyName;
  final bool isOwner;
  final String? roleCode;
}

class CompanyContextFailure implements Exception {
  const CompanyContextFailure(this.message, {this.code, this.serverCode});

  final String message;
  final String? code;
  final String? serverCode;
}

enum CompanyContextState {
  loading,
  unavailable,
  noMembership,
  denied,
  revoked,
  ready,
}
