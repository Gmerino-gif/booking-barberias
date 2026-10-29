import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/image_upload_service.dart';
import '../theme/app_theme.dart';
import '../utils/image_picker_service.dart';
import '../utils/image_urls.dart';

/// Acción elegida en el selector de origen de la imagen.
enum _ImageAction { gallery, camera, link }

/// Campo reutilizable para gestionar una imagen de perfil (logo, banner o foto).
///
/// Muestra una vista previa de la imagen actual y permite reemplazarla tomando
/// una foto, eligiendo un archivo de la galería o pegando un enlace público. En
/// todos los casos la imagen se sube al backend, que responde con la referencia
/// almacenada (`/uploads/archivo.png`) a través de [onChanged].
class ImageEditField extends StatefulWidget {
  const ImageEditField({
    super.key,
    required this.label,
    required this.onChanged,
    required this.authToken,
    this.value,
    this.helperText = '',
    this.height = 160,
    this.circular = false,
    this.enabled = true,
  });

  final String label;

  /// Referencia actual de la imagen (`/uploads/...` o URL absoluta).
  final String? value;

  final ValueChanged<String?> onChanged;
  final String? authToken;
  final String helperText;
  final double height;
  final bool circular;
  final bool enabled;

  @override
  State<ImageEditField> createState() => _ImageEditFieldState();
}

class _ImageEditFieldState extends State<ImageEditField> {
  bool _isUploading = false;

  /// Bytes elegidos en el dispositivo, usados como vista previa inmediata
  /// mientras la subida está en curso.
  Uint8List? _pendingBytes;

  String? get _previewUrl => AppImageUrls.resolve(widget.value);

  bool get _hasImage => _pendingBytes != null || _previewUrl != null;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _removeImage() {
    setState(() => _pendingBytes = null);
    widget.onChanged(null);
  }

  Future<void> _pickImage() async {
    final action = await showModalBottomSheet<_ImageAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _SourceSheet(label: widget.label),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _ImageAction.gallery:
        await _pickFromDevice(ImagePickSource.gallery);
      case _ImageAction.camera:
        await _pickFromDevice(ImagePickSource.camera);
      case _ImageAction.link:
        await _pickFromLink();
    }
  }

  Future<void> _pickFromDevice(ImagePickSource source) async {
    PickedImage? picked;
    try {
      picked = await ImagePickerService.pick(source: source);
    } on ImagePickerException catch (error) {
      _showMessage(error.message);
      return;
    }

    // El usuario cerró el selector sin elegir nada.
    final image = picked;
    if (image == null) return;

    setState(() {
      _isUploading = true;
      _pendingBytes = image.bytes;
    });

    try {
      final stored = await ImageUploadService.uploadFromDataUrl(
        dataUrl: image.dataUrl,
        token: widget.authToken,
      );
      if (!mounted) return;
      setState(() => _pendingBytes = null);
      widget.onChanged(stored);
      _showMessage('Imagen actualizada');
    } on ImageUploadException catch (error) {
      if (!mounted) return;
      // La vista previa local se descarta para no mostrar algo que no se guardó.
      setState(() => _pendingBytes = null);
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickFromLink() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => _ImageUrlDialog(title: widget.label),
    );

    if (!mounted || url == null || url.isEmpty) return;
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      _showMessage('El enlace debe empezar por http:// o https://');
      return;
    }
    await _uploadFromUrl(url);
  }

  Future<void> _uploadFromUrl(String url) async {
    setState(() => _isUploading = true);
    try {
      final stored = await ImageUploadService.uploadFromUrl(
        url: url,
        token: widget.authToken,
      );
      if (!mounted) return;
      widget.onChanged(stored);
      _showMessage('Imagen actualizada');
    } on ImageUploadException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: AppTypography.semiBold,
                ),
              ),
            ),
            if (_hasImage && widget.enabled)
              TextButton(
                onPressed: _isUploading ? null : _removeImage,
                child: const Text('Quitar'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(child: _buildPreview(theme)),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: widget.enabled && !_isUploading ? _pickImage : null,
          icon: _isUploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _isUploading
                ? 'Subiendo imagen…'
                : _hasImage
                    ? 'Cambiar imagen'
                    : 'Agregar imagen',
          ),
        ),
        if (widget.helperText.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.helperText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final width = widget.circular ? widget.height : double.infinity;

    final placeholder = Container(
      width: width,
      height: widget.height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.circular
            ? null
            : BorderRadius.circular(AppRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.circular ? Icons.badge_outlined : Icons.image_outlined,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sin imagen',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    final loading = Container(
      width: width,
      height: widget.height,
      alignment: Alignment.center,
      color: theme.colorScheme.surfaceContainerHighest,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );

    final Widget image;
    if (_pendingBytes != null) {
      // Vista previa local: se muestra al instante, sin esperar la red.
      image = Image.memory(
        _pendingBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (_previewUrl != null) {
      image = Image.network(
        _previewUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : loading,
      );
    } else {
      image = placeholder;
    }

    if (widget.circular) {
      return ClipOval(
        child: SizedBox(width: widget.height, height: widget.height, child: image),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(width: double.infinity, height: widget.height, child: image),
    );
  }
}

/// Hoja inferior con los orígenes disponibles para la imagen.
class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppTypography.semiBold,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(context, _ImageAction.gallery),
          ),
          if (ImagePickerService.cameraSupported)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar una foto'),
              onTap: () => Navigator.pop(context, _ImageAction.camera),
            ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Usar un enlace'),
            subtitle: const Text('Pega la dirección pública de la imagen'),
            onTap: () => Navigator.pop(context, _ImageAction.link),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Diálogo para indicar el enlace público de la imagen que se quiere subir.
///
/// Es un widget con estado propio para que el [TextEditingController] se libere
/// en su `dispose` (no al cerrar el diálogo desde el widget que lo abre).
class _ImageUrlDialog extends StatefulWidget {
  const _ImageUrlDialog({required this.title});

  final String title;

  @override
  State<_ImageUrlDialog> createState() => _ImageUrlDialogState();
}

class _ImageUrlDialogState extends State<_ImageUrlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (!mounted || text.isEmpty) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pega el enlace público de la imagen (JPG, PNG, WEBP o GIF de '
            'máximo 5 MB). La guardaremos en tu perfil.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Enlace de la imagen',
              hintText: 'https://…',
              prefixIcon: const Icon(Icons.link),
              suffixIcon: IconButton(
                tooltip: 'Pegar del portapapeles',
                icon: const Icon(Icons.content_paste),
                onPressed: _pasteFromClipboard,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Subir')),
      ],
    );
  }
}
