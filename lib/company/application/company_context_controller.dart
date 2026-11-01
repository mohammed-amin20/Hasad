import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hasad_erp_v2/company/domain/company_context.dart';
import 'package:hasad_erp_v2/company/domain/company_context_service.dart';
import 'package:hasad_erp_v2/company/domain/product.dart';

class CompanyContextController extends ChangeNotifier {
  CompanyContextController(this._service);

  final CompanyContextService _service;

  CompanyContextState _state = CompanyContextState.loading;
  CompanyContext? _context;
  String? _message;
  String? _code;
  List<Product> _products = const [];
  bool _productsLoading = false;
  int _requestVersion = 0;
  bool _disposed = false;

  CompanyContextState get state => _state;
  CompanyContext? get context => _context;
  String? get message => _message;
  String? get code => _code;
  List<Product> get products => _products;
  bool get productsLoading => _productsLoading;

  Future<void> loadContext() async {
    final requestVersion = ++_requestVersion;
    _state = CompanyContextState.loading;
    _context = null;
    _products = const [];
    _productsLoading = false;
    _message = null;
    _code = null;
    _notifyIfActive();
    try {
      final context = await _service.getCurrentContext();
      if (!_isCurrent(requestVersion)) {
        return;
      }
      _context = context;
      _state = CompanyContextState.ready;
      _notifyIfActive();
      await _loadProducts(requestVersion);
    } on CompanyContextFailure catch (failure) {
      if (!_isCurrent(requestVersion)) {
        return;
      }
      _message = failure.message;
      _code = failure.code;
      if (failure.code == 'NO_MEMBERSHIP' ||
          failure.code == 'UNAUTHENTICATED') {
        _state = CompanyContextState.noMembership;
      } else if (failure.code == 'DENIED') {
        _state = CompanyContextState.denied;
      } else if (failure.code == 'REVOKED') {
        _state = CompanyContextState.revoked;
      } else if (failure.code == 'UNAPPROVED_BACKEND') {
        _state = CompanyContextState.unavailable;
      } else {
        _state = CompanyContextState.unavailable;
      }
      _notifyIfActive();
    } on Object {
      if (!_isCurrent(requestVersion)) {
        return;
      }
      _message = 'حدث خطأ غير متوقع أثناء تحميل سياق الشركة.';
      _code = 'UNKNOWN';
      _state = CompanyContextState.unavailable;
      _notifyIfActive();
    }
  }

  Future<void> _loadProducts(int requestVersion) async {
    if (_context == null) {
      return;
    }
    _productsLoading = true;
    _notifyIfActive();
    try {
      final products = await _service.getProducts(
        companyId: _context!.companyId,
      );
      if (!_isCurrent(requestVersion)) {
        return;
      }
      if (products.any((product) => product.companyId != _context!.companyId)) {
        throw const CompanyContextFailure(
          'استجابة المنتجات لا تطابق سياق الشركة. تم إيقاف العرض بأمان.',
          code: 'UNEXPECTED_RESPONSE',
        );
      }
      _products = products;
    } on CompanyContextFailure catch (failure) {
      if (!_isCurrent(requestVersion)) {
        return;
      }
      _products = const [];
      _message = failure.message;
      _code = failure.code;
      if (failure.code == 'DENIED') {
        _state = CompanyContextState.denied;
      } else if (failure.code == 'NO_MEMBERSHIP' ||
          failure.code == 'UNAUTHENTICATED') {
        _context = null;
        _state = CompanyContextState.noMembership;
      } else {
        _state = CompanyContextState.unavailable;
      }
    } on Object {
      if (!_isCurrent(requestVersion)) {
        return;
      }
      _products = const [];
      _message = 'حدث خطأ غير متوقع أثناء تحميل المنتجات.';
      _code = 'UNKNOWN';
      _state = CompanyContextState.unavailable;
    } finally {
      if (_isCurrent(requestVersion)) {
        _productsLoading = false;
        _notifyIfActive();
      }
    }
  }

  bool _isCurrent(int requestVersion) =>
      !_disposed && requestVersion == _requestVersion;

  void _notifyIfActive() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestVersion++;
    super.dispose();
  }
}
