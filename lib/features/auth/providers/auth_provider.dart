import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/modelos/user_role.dart';
import '../../../core/network/api_config.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unauthenticated;
  UserRole? _role;
  String? _userName;
  String? _userEmail;
  String? _userPhone;
  String? _userId;
  String? _accessToken;
  String? _refreshToken;

  AuthStatus get status => _status;
  UserRole? get role => _role;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  String? get userPhone => _userPhone;
  String? get userId => _userId;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isBusiness => _role?.isBusiness ?? false;

  Future<void> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/login'),
            headers: const {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'email': email.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      dynamic decodedResponse;
      try {
        decodedResponse = jsonDecode(response.body);
      } on FormatException {
        decodedResponse = null;
      }

      if (response.statusCode != 200 || decodedResponse is! Map<String, dynamic>) {
        final message = decodedResponse is Map<String, dynamic>
            ? decodedResponse['message'] as String?
            : null;
        throw AuthException(message ?? 'No se pudo iniciar sesión');
      }

      final user = decodedResponse['user'];
      if (user is! Map<String, dynamic>) {
        throw const AuthException('El servidor devolvió una respuesta inválida');
      }

      _userId = user['id'] as String?;
      _userName = user['name'] as String?;
      _userEmail = user['email'] as String?;
      _userPhone = user['phone'] as String?;
      _role = UserRole.fromString(user['role'] as String? ?? 'client');
      _accessToken = decodedResponse['token'] as String?;
      _refreshToken = decodedResponse['refreshToken'] as String?;
      _status = AuthStatus.authenticated;
      notifyListeners();
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException('El servidor tardó demasiado en responder');
    } on http.ClientException {
      throw const AuthException('No fue posible conectar con el servidor');
    } catch (_) {
      throw const AuthException('Ocurrió un error al iniciar sesión');
    }
  }

  Future<void> logout() async {
    _status = AuthStatus.unauthenticated;
    _role = null;
    _userEmail = null;
    _userPhone = null;
    _userName = null;
    _userId = null;
    _accessToken = null;
    _refreshToken = null;
    notifyListeners();
  }

  /// Cambiar entre modo cliente y negocio (como Uber)
  void switchMode(UserRole newRole) {
    if (_role == null) return;
    _role = newRole;
    notifyListeners();
  }
}

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);
}