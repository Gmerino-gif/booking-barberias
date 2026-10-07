import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/modelos/user_role.dart';
import '../../../core/network/api_config.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const _accessTokenKey = 'auth.accessToken';
  static const _refreshTokenKey = 'auth.refreshToken';
  static const _userKey = 'auth.user';

  AuthStatus _status = AuthStatus.unknown;
  UserRole? _role;
  String? _userName;
  String? _userEmail;
  String? _userPhone;
  String? _userId;
  String? _accessToken;
  String? _refreshToken;
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  int _sessionGeneration = 0;

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

  Future<void> restoreSession() async {
    try {
      _accessToken = await _secureStorage.read(key: _accessTokenKey);
      _refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      final storedUser = await _secureStorage.read(key: _userKey);
      if (_accessToken == null ||
          _accessToken!.isEmpty ||
          _refreshToken == null ||
          _refreshToken!.isEmpty) {
        await logout();
        return;
      }
      if (storedUser != null) {
        final decoded = jsonDecode(storedUser);
        if (decoded is Map<String, dynamic>) _setUser(decoded);
      }
      _status = AuthStatus.authenticated;
      notifyListeners();
      if (_isAccessTokenExpired(_accessToken!)) {
        await _refreshAccessToken();
      } else {
        _scheduleRefresh();
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
      _clearMemory();
      notifyListeners();
    }
  }

  Future<void> login({required String email, required String password}) async {
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

      if (response.statusCode != 200 ||
          decodedResponse is! Map<String, dynamic>) {
        final message = decodedResponse is Map<String, dynamic>
            ? decodedResponse['message'] as String?
            : null;
        throw AuthException(message ?? 'No se pudo iniciar sesión');
      }

      final user = decodedResponse['user'];
      final accessToken = decodedResponse['token'];
      final refreshToken = decodedResponse['refreshToken'];
      if (user is! Map<String, dynamic> ||
          accessToken is! String ||
          refreshToken is! String) {
        throw const AuthException(
          'El servidor devolvió una respuesta inválida',
        );
      }

      _setUser(user);
      _accessToken = accessToken;
      _refreshToken = refreshToken;
      _sessionGeneration++;
      _status = AuthStatus.authenticated;
      await _saveSession();
      _scheduleRefresh();
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

  Future<bool> _refreshAccessToken() async {
    if (_isRefreshing) return false;
    final currentRefreshToken = _refreshToken;
    if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
      await logout();
      return false;
    }

    _isRefreshing = true;
    final generation = _sessionGeneration;
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/refresh'),
            headers: const {'Content-Type': 'application/json; charset=UTF-8'},
            body: jsonEncode({'refreshToken': currentRefreshToken}),
          )
          .timeout(const Duration(seconds: 15));
      if (generation != _sessionGeneration) return false;
      final decoded = jsonDecode(response.body);
      final renewedToken = decoded is Map<String, dynamic>
          ? decoded['accessToken']
          : null;
      if (response.statusCode == 401) {
        await logout();
        return false;
      }
      if (response.statusCode != 200 ||
          renewedToken is! String ||
          renewedToken.isEmpty) {
        _retryRefreshSoon();
        return false;
      }
      _accessToken = renewedToken;
      await _saveSession();
      _scheduleRefresh();
      notifyListeners();
      return true;
    } on TimeoutException {
      _retryRefreshSoon();
      return false;
    } on http.ClientException {
      _retryRefreshSoon();
      return false;
    } catch (_) {
      _retryRefreshSoon();
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  void _retryRefreshSoon() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      const Duration(minutes: 1),
      () => unawaited(_refreshAccessToken()),
    );
  }

  bool _isAccessTokenExpired(String token) {
    final expiration = _tokenExpiration(token);
    return expiration != null &&
        !expiration.isAfter(DateTime.now().add(const Duration(seconds: 10)));
  }

  DateTime? _tokenExpiration(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final expiration = payload is Map<String, dynamic>
          ? payload['exp']
          : null;
      return expiration is num
          ? DateTime.fromMillisecondsSinceEpoch(expiration.toInt() * 1000)
          : null;
    } catch (_) {
      return null;
    }
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final token = _accessToken;
    if (token == null) return;
    final expiration = _tokenExpiration(token);
    if (expiration == null) return;
    final delay =
        expiration.difference(DateTime.now()) - const Duration(minutes: 2);
    _refreshTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(_refreshAccessToken()),
    );
  }

  void _setUser(Map<String, dynamic> user) {
    _userId = user['id'] as String?;
    _userName = user['name'] as String?;
    _userEmail = user['email'] as String?;
    _userPhone = user['phone'] as String?;
    _role = UserRole.fromString(user['role'] as String? ?? 'client');
  }

  Map<String, dynamic> _userJson() => {
    'id': _userId,
    'name': _userName,
    'email': _userEmail,
    'phone': _userPhone,
    'role': _role?.name,
  };

  Future<void> _saveSession() async {
    try {
      if (_accessToken != null) {
        await _secureStorage.write(key: _accessTokenKey, value: _accessToken);
      }
      if (_refreshToken != null) {
        await _secureStorage.write(key: _refreshTokenKey, value: _refreshToken);
      }
      await _secureStorage.write(key: _userKey, value: jsonEncode(_userJson()));
    } catch (_) {
      // Keep the current session usable if the platform storage is temporarily unavailable.
    }
  }

  Future<void> logout() async {
    _sessionGeneration++;
    _refreshTimer?.cancel();
    _status = AuthStatus.unauthenticated;
    _clearMemory();
    try {
      await _secureStorage.deleteAll();
    } catch (_) {
      // In-memory logout still takes effect if secure storage is unavailable.
    }
    notifyListeners();
  }

  void _clearMemory() {
    _role = null;
    _userEmail = null;
    _userPhone = null;
    _userName = null;
    _userId = null;
    _accessToken = null;
    _refreshToken = null;
  }

  void updateProfile({required String name, required String phone}) {
    _userName = name;
    _userPhone = phone;
    unawaited(_saveSession());
    notifyListeners();
  }

  /// Cambiar entre modo cliente y negocio (como Uber)
  void switchMode(UserRole newRole) {
    if (_role == null) return;
    _role = newRole;
    unawaited(_saveSession());
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);
}
