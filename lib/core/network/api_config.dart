import 'package:flutter/foundation.dart';

class ApiConfig {
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static void validateConfiguration() {
    if (baseUrl.isEmpty) {
      throw StateError('API_BASE_URL no puede estar vacío.');
    }
  }

  static String get baseUrl {
    final configuredUrl = _configuredBaseUrl.trim();
    if (configuredUrl.isNotEmpty) {
      final uri = Uri.tryParse(configuredUrl);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw StateError('API_BASE_URL debe ser una URL HTTP o HTTPS válida.');
      }
      if (!kDebugMode && uri.scheme != 'https') {
        throw StateError('API_BASE_URL debe usar HTTPS en builds de producción.');
      }
      return configuredUrl.replaceFirst(RegExp(r'/+$'), '');
    }

    if (!kDebugMode) {
      throw StateError(
        'Configura API_BASE_URL al compilar la app de producción, por ejemplo '
        '--dart-define=API_BASE_URL=https://api.tudominio.com/api.',
      );
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000/api';
    }
    return 'http://localhost:3000/api';
  }
}
