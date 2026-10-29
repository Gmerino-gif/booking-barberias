import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Origen desde el que el usuario obtiene la imagen.
enum ImagePickSource { gallery, camera }

/// Error de cara al usuario al elegir una imagen del dispositivo.
class ImagePickerException implements Exception {
  const ImagePickerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Imagen elegida por el usuario, lista para enviarse al backend.
///
/// [dataUrl] ya viene codificado como `data:image/...;base64,...`, que es el
/// formato que acepta `POST /uploads/image`.
class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.dataUrl,
    this.fileName,
  });

  final Uint8List bytes;
  final String dataUrl;
  final String? fileName;
}

/// Acceso al selector nativo de imágenes (galería o cámara).
///
/// Reduce la imagen antes de subirla: el backend rechaza archivos de más de
/// 5 MB y las fotos de cámara sin comprimir los superan con facilidad.
class ImagePickerService {
  const ImagePickerService._();

  /// Lado máximo (px) al que se redimensiona la imagen elegida.
  static const int maxDimension = 1600;

  /// Calidad de recompresión aplicada por el selector.
  static const int quality = 85;

  /// Tamaño máximo aceptado por el backend (`MAX_IMAGE_BYTES`).
  static const int maxBytes = 5 * 1024 * 1024;

  /// La cámara solo existe en móviles; en escritorio y web se oculta la opción.
  static bool get cameraSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Abre el selector nativo. Devuelve `null` si el usuario cancela.
  static Future<PickedImage?> pick({
    ImagePickSource source = ImagePickSource.gallery,
  }) async {
    final picker = ImagePicker();

    XFile? file;
    try {
      file = await picker.pickImage(
        source: source == ImagePickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: maxDimension.toDouble(),
        maxHeight: maxDimension.toDouble(),
        imageQuality: quality,
      );
    } on PlatformException catch (error) {
      throw ImagePickerException(_messageFor(error));
    }

    if (file == null) return null;

    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Exception {
      throw const ImagePickerException(
        'No pudimos leer la imagen seleccionada. Intenta con otra.',
      );
    }

    if (bytes.isEmpty) {
      throw const ImagePickerException(
        'No pudimos leer la imagen seleccionada. Intenta con otra.',
      );
    }
    if (bytes.length > maxBytes) {
      throw const ImagePickerException(
        'La imagen supera los 5 MB. Elige una más pequeña.',
      );
    }

    final mimeType = _detectMimeType(bytes);
    if (mimeType == null) {
      throw const ImagePickerException(
        'Formato no compatible. Usa una imagen JPG, PNG, WEBP o GIF.',
      );
    }

    return PickedImage(
      bytes: bytes,
      dataUrl: 'data:$mimeType;base64,${base64Encode(bytes)}',
      fileName: file.name,
    );
  }

  /// Traduce los códigos de error del plugin a mensajes en español.
  static String _messageFor(PlatformException error) {
    switch (error.code) {
      case 'photo_access_denied':
        return 'Necesitamos permiso para acceder a tus fotos. '
            'Actívalo en los ajustes del sistema.';
      case 'camera_access_denied':
        return 'Necesitamos permiso para usar la cámara. '
            'Actívalo en los ajustes del sistema.';
      case 'invalid_image':
        return 'La imagen seleccionada no es válida.';
      default:
        return 'No pudimos abrir el selector de imágenes. Intenta de nuevo.';
    }
  }

  /// Detecta el formato real por los bytes iniciales, igual que el backend.
  static String? _detectMimeType(Uint8List bytes) {
    if (_startsWith(bytes, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (_startsWith(bytes, const [0x47, 0x49, 0x46])) return 'image/gif';
    if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
        _startsWith(bytes, const [0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    return null;
  }

  static bool _startsWith(Uint8List bytes, List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }
}
