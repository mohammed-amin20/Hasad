import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hasad_erp_v2/auth/domain/auth_service.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._authService) : _session = _authService.currentSession;

  final AuthService _authService;
  StreamSubscription<AuthSession?>? _subscription;
  AuthSession? _session;
  bool _isRestoring = true;

  AuthSession? get session => _session;

  bool get isRestoring => _isRestoring;

  String? get unavailableReason => _authService.unavailableReason;

  void restoreSession() {
    _subscription ??= _authService.sessionChanges.listen((session) {
      _session = session;
      notifyListeners();
    });
    _isRestoring = false;
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    await _authService.signIn(email: email, password: password);
    _session = _authService.currentSession;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _session = _authService.currentSession;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
