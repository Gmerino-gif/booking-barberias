import '../network/api_config.dart';

/// Resuelve las referencias de imagen que devuelve la API.
///
/// La API guarda las imágenes subidas como rutas relativas al servidor
/// (`/uploads/archivo.png`) para no atarlas a un host concreto; aquí se
/// convierten en una URL absoluta lista para `Image.network`.
class AppImageUrls {
  const AppImageUrls._();

  static String? resolve(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return value;
    if (lower.startsWith('data:')) return null;
    try {
      final base = Uri.tryParse(ApiConfig.baseUrl);
      if (base == null || base.host.isEmpty) return null;
      final path = value.startsWith('/') ? value : '/$value';
      return base.replace(path: path, query: null, fragment: null).toString();
    } catch (_) {
      // `ApiConfig.baseUrl` lanza si la configuración es inválida en producción.
      return null;
    }
  }
}
