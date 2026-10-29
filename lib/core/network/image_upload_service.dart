import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Error de cara al usuario al subir una imagen de perfil.
class ImageUploadException implements Exception {
  final String message;

  const ImageUploadException(this.message);

  @override
  String toString() => message;
}

/// Sube imágenes de negocio (logo/banner) y de profesionales al backend.
///
/// El backend responde con la referencia almacenada (`/uploads/archivo.png`),
/// que es la que debe persistirse en el perfil del negocio o del profesional.
class ImageUploadService {
  const ImageUploadService._();

  /// Descarga la imagen desde un enlace público y la almacena en el servidor.
  static Future<String> uploadFromUrl({
    required String url,
    required String? token,
  }) => _upload({'url': url.trim()}, token);

  /// Sube la imagen desde sus bytes en base64 (`data:image/png;base64,...`).
  ///
  /// Es la vía pensada para selectores de archivos del dispositivo.
  static Future<String> uploadFromDataUrl({
    required String dataUrl,
    required String? token,
  }) => _upload({'image': dataUrl}, token);

  static Future<String> _upload(
    Map<String, String> payload,
    String? token,
  ) async {
    if (token == null || token.isEmpty) {
      throw const ImageUploadException(
        'Tu sesión expiró. Inicia sesión otra vez.',
      );
    }

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/uploads/image'),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const ImageUploadException('La carga de la imagen tardó demasiado.');
    } on http.ClientException {
      throw const ImageUploadException(
        'No fue posible conectar con el servidor.',
      );
    }

    final decoded = _decode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      final url = decoded?['url'];
      if (url is String && url.trim().isNotEmpty) return url.trim();
      throw const ImageUploadException(
        'El servidor no devolvió la imagen guardada.',
      );
    }

    final message = decoded?['message'];
    throw ImageUploadException(
      message is String ? message : 'No se pudo subir la imagen.',
    );
  }

  static Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
