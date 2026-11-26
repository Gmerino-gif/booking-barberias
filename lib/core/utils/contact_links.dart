import 'package:url_launcher/url_launcher.dart';

/// Construye y abre los enlaces de contacto del negocio con sus clientes:
/// llamada telefónica (`tel:`) y WhatsApp (`https://wa.me/...`).
///
/// Vive en `core/utils` para que cualquier pantalla (agenda, panel, etc.)
/// construya los enlaces igual y no duplique la normalización del teléfono.
/// No se usa `canLaunchUrl` a propósito: en Flutter Web devuelve `false` para
/// esquemas externos (`tel:`, `whatsapp:`) y bloquearía un lanzamiento que sí
/// funciona; por eso se llama directamente a [launchUrl] y se informa el
/// fallo con el valor devuelto o con la excepción.
class AppContactLinks {
  const AppContactLinks._();

  /// Indicativo de Colombia, requerido por los enlaces `wa.me`.
  static const String colombiaCountryCode = '57';

  /// Normaliza el teléfono de un cliente colombiano a solo dígitos con
  /// indicativo país (p. ej. `573001234567`).
  ///
  /// Acepta formatos como `+57 300 123 4567`, `300-123-4567`,
  /// `(300) 123 4567` o `0057 300 123 4567`. Devuelve `null` cuando el valor
  /// no sirve para marcar (vacío, sin dígitos o con un largo no reconocido),
  /// para que la UI muestre un mensaje en lugar de abrir un enlace roto.
  static String? normalizeColombianPhone(String? raw) {
    if (raw == null) return null;
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    // Prefijo internacional escrito como 00 (0057 300...).
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    // Móvil/fijo colombiano sin indicativo: 10 dígitos.
    if (digits.length == 10) return '$colombiaCountryCode$digits';
    // Ya viene con indicativo de Colombia.
    if (digits.length == 12 && digits.startsWith(colombiaCountryCode)) {
      return digits;
    }
    return null;
  }

  /// Enlace para abrir el marcador del teléfono.
  static Uri telUri(String normalizedPhone) =>
      Uri(scheme: 'tel', path: '+$normalizedPhone');

  /// Enlace de WhatsApp con un mensaje inicial opcional ya codificado.
  static Uri whatsAppUri(String normalizedPhone, {String? message}) {
    final text = message?.trim() ?? '';
    final query = text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}';
    return Uri.parse('https://wa.me/$normalizedPhone$query');
  }

  /// Abre [uri] en la app externa correspondiente (marcador, WhatsApp o
  /// navegador). Devuelve `false` cuando el sistema no pudo abrirlo.
  static Future<bool> launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
