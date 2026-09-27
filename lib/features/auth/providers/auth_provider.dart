import 'package:flutter/foundation.dart';

import '../../../core/modelos/user_role.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unauthenticated;
  UserRole? _role;
  String? _userName;
  String? _userEmail;

  AuthStatus get status => _status;
  UserRole? get role => _role;
  String? get userName => _userName;
  String? get userEmail => _userEmail;

  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isBusiness => _role?.isBusiness ?? false;

  /// Simula login. Reemplazar con llamada HTTP al backend.
  Future<void> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    _userEmail = email;
    _userName = email.split('@').first;
    _role = role;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> logout() async {
    _status = AuthStatus.unauthenticated;
    _role = null;
    _userEmail = null;
    _userName = null;
    notifyListeners();
  }

  /// Cambiar entre modo cliente y negocio (como Uber)
  void switchMode(UserRole newRole) {
    if (_role == null) return;
    _role = newRole;
    notifyListeners();
  }
}