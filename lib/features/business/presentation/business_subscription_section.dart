import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

const _transferDetails = String.fromEnvironment(
  'SUBSCRIPTION_TRANSFER_DETAILS',
);

class BusinessSubscriptionSection extends StatefulWidget {
  const BusinessSubscriptionSection({super.key});

  @override
  State<BusinessSubscriptionSection> createState() =>
      _BusinessSubscriptionSectionState();
}

class _BusinessSubscriptionSectionState
    extends State<BusinessSubscriptionSection> {
  _SubscriptionSnapshot? _snapshot;
  Uint8List? _receiptBytes;
  String? _receiptFileName;
  String? _checkoutUrl;
  String? _loadError;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isCreatingCheckout = false;
  bool _isUploadingReceipt = false;

  _PaymentRecord? get _latestManualPayment {
    for (final payment in _snapshot?.payments ?? const <_PaymentRecord>[]) {
      if (payment.method == 'manual_transfer') return payment;
    }
    return null;
  }

  bool get _hasPendingManualPayment =>
      _snapshot?.payments.any(
        (payment) =>
            payment.method == 'manual_transfer' && payment.status == 'pending',
      ) ??
      false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory(showLoading: true);
    });
  }

  Future<bool> _loadHistory({bool showLoading = false}) async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _loadError = 'Tu sesión expiró. Inicia sesión otra vez.';
          _isLoading = false;
          _isRefreshing = false;
        });
      }
      return false;
    }

    if (mounted) {
      setState(() {
        if (showLoading) _isLoading = true;
        _isRefreshing = !showLoading;
        _loadError = null;
      });
    }

    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/payments/my-history'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      final decoded = _decode(response.body);
      if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
        throw _ApiException(
          _messageFrom(decoded) ??
              'No se pudo cargar el estado de la suscripción.',
        );
      }

      final snapshot = _SubscriptionSnapshot.fromJson(decoded);
      if (!mounted) return false;
      setState(() {
        _snapshot = snapshot;
        _loadError = null;
        _isLoading = false;
        _isRefreshing = false;
      });
      return true;
    } on TimeoutException {
      _setLoadError('El servidor tardó demasiado en responder.');
    } on http.ClientException {
      _setLoadError('No fue posible conectar con el servidor.');
    } on _ApiException catch (error) {
      _setLoadError(error.message);
    } on FormatException {
      _setLoadError('El servidor devolvió datos de suscripción inválidos.');
    } catch (_) {
      _setLoadError('No se pudo cargar el estado de la suscripción.');
    }
    return false;
  }

  void _setLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _loadError = message;
      _isLoading = false;
      _isRefreshing = false;
    });
  }

  Future<void> _refreshStatus() async {
    final previousExpiration = _snapshot?.expiresAt;
    final loaded = await _loadHistory();
    if (!mounted) return;
    if (!loaded) {
      _showMessage(
        _loadError ?? 'No se pudo actualizar el estado.',
        isError: true,
      );
      return;
    }

    final renewed =
        _snapshot?.expiresAt != null &&
        _snapshot!.expiresAt != previousExpiration;
    _showMessage(
      renewed
          ? '¡Suscripción renovada! Tu nueva fecha de vencimiento ya está activa.'
          : 'Estado actualizado. Si acabas de pagar, vuelve a consultar en unos segundos.',
    );
  }

  Future<void> _createWompiCheckout() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      _showMessage('Tu sesión expiró. Inicia sesión otra vez.', isError: true);
      return;
    }

    setState(() {
      _isCreatingCheckout = true;
      _checkoutUrl = null;
    });
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/payments/wompi-link'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      final decoded = _decode(response.body);
      final checkoutUrl = decoded is Map<String, dynamic>
          ? decoded['checkoutUrl']
          : null;
      if (response.statusCode != 201 ||
          checkoutUrl is! String ||
          checkoutUrl.trim().isEmpty) {
        throw _ApiException(
          _messageFrom(decoded) ?? 'No se pudo crear el enlace de pago.',
        );
      }

      final uri = Uri.tryParse(checkoutUrl);
      if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
        throw const _ApiException(
          'El servidor devolvió un enlace de pago inválido.',
        );
      }

      if (!mounted) return;
      setState(() => _checkoutUrl = checkoutUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showMessage(
          'No se pudo abrir Wompi automáticamente. Usa el enlace que aparece abajo.',
          isError: true,
        );
      }
    } on TimeoutException {
      _showMessage(
        'La creación del pago tardó demasiado. Inténtalo de nuevo.',
        isError: true,
      );
    } on http.ClientException {
      _showMessage('No fue posible conectar con el servidor.', isError: true);
    } on _ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (_) {
      _showMessage('No se pudo abrir el pago de Wompi.', isError: true);
    } finally {
      if (mounted) setState(() => _isCreatingCheckout = false);
    }
  }

  Future<void> _pickReceipt() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _showMessage('No se pudo leer la imagen seleccionada.', isError: true);
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        _showMessage(
          'La imagen supera el tamaño máximo de 5 MB.',
          isError: true,
        );
        return;
      }
      final extension = _imageExtension(bytes);
      if (extension == null) {
        _showMessage(
          'Formato no compatible. Usa una imagen JPG, PNG o WEBP.',
          isError: true,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _receiptBytes = bytes;
        _receiptFileName = 'comprobante.$extension';
      });
    } on PlatformException {
      _showMessage('No se pudo abrir el selector de imágenes.', isError: true);
    } catch (_) {
      _showMessage('No se pudo leer la imagen seleccionada.', isError: true);
    }
  }

  String? _imageExtension(Uint8List bytes) {
    bool startsWith(List<int> signature, [int offset = 0]) {
      if (bytes.length < offset + signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[offset + index] != signature[index]) return false;
      }
      return true;
    }

    if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'png';
    if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'jpg';
    if (startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
        startsWith(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return 'webp';
    }
    return null;
  }

  Future<void> _uploadReceipt() async {
    final bytes = _receiptBytes;
    if (bytes == null || _hasPendingManualPayment || _isUploadingReceipt) {
      return;
    }
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      _showMessage('Tu sesión expiró. Inicia sesión otra vez.', isError: true);
      return;
    }

    setState(() => _isUploadingReceipt = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/payments/manual-receipt'),
      )..headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile.fromBytes(
          'receipt',
          bytes,
          filename: _receiptFileName ?? 'comprobante.jpg',
        ),
      );
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );
      final response = await http.Response.fromStream(streamedResponse)
          .timeout(const Duration(seconds: 15));
      final decoded = _decode(response.body);
      if (response.statusCode != 201) {
        throw _ApiException(
          _messageFrom(decoded) ?? 'No se pudo enviar el comprobante.',
        );
      }

      if (!mounted) return;
      setState(() {
        _receiptBytes = null;
        _receiptFileName = null;
      });
      _showMessage('Comprobante enviado para revisión.');
      await _loadHistory();
    } on TimeoutException {
      _showMessage(
        'La carga tardó demasiado. Inténtalo de nuevo.',
        isError: true,
      );
    } on http.ClientException {
      _showMessage('No fue posible conectar con el servidor.', isError: true);
    } on _ApiException catch (error) {
      _showMessage(error.message, isError: true);
    } catch (_) {
      _showMessage('No se pudo enviar el comprobante.', isError: true);
    } finally {
      if (mounted) setState(() => _isUploadingReceipt = false);
    }
  }

  Future<void> _copyTransferDetails() async {
    await Clipboard.setData(const ClipboardData(text: _transferDetails));
    if (mounted) _showMessage('Datos de transferencia copiados.');
  }

  /// SnackBar con fondo oscuro y texto blanco para garantizar contraste;
  /// los errores usan además un rojo oscuro.
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: AppColors.snackBarForeground),
          ),
          backgroundColor: isError
              ? AppColors.snackBarErrorBackground
              : AppColors.snackBarBackground,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  String? _messageFrom(dynamic decoded) {
    final message = decoded is Map<String, dynamic> ? decoded['message'] : null;
    return message is String && message.trim().isNotEmpty ? message : null;
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _formatPrice(int amount) => amount.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_snapshot == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionTitle(theme),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _loadError ?? 'No se pudo cargar la suscripción.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _isRefreshing ? null : () => _loadHistory(),
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = _snapshot!;
    final subscriptionStatus = _statusFor(snapshot);
    final pendingPayment = _hasPendingManualPayment;
    final rejectedPayment = _latestManualPayment?.status == 'rejected'
        ? _latestManualPayment
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _sectionTitle(theme)),
                IconButton(
                  tooltip: 'Actualizar estado',
                  onPressed: _isRefreshing ? null : _refreshStatus,
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusBadge(status: subscriptionStatus),
                if (snapshot.expiresAt != null)
                  Text(
                    subscriptionStatus.daysRemaining < 0
                        ? 'Venció el ${_formatDate(snapshot.expiresAt!.toLocal())}'
                        : 'Vence el ${_formatDate(snapshot.expiresAt!.toLocal())}',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  Text(
                    'Sin fecha de vencimiento',
                    style: theme.textTheme.bodyMedium,
                  ),
              ],
            ),
            if (snapshot.expiresAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subscriptionStatus.daysRemaining < 0
                    ? 'La suscripción venció hace ${subscriptionStatus.daysRemaining.abs()} días.'
                    : 'Días restantes: ${subscriptionStatus.daysRemaining}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _isCreatingCheckout ? null : _createWompiCheckout,
              icon: _isCreatingCheckout
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Icon(Icons.credit_card_outlined),
              label: Text(
                _isCreatingCheckout
                    ? 'Creando enlace de pago…'
                    : 'Renovar con Wompi (\$${_formatPrice(snapshot.priceCop)} COP)',
              ),
            ),
            if (_checkoutUrl != null) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(_checkoutUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir enlace de pago'),
              ),
            ],
            if (pendingPayment) ...[
              const SizedBox(height: AppSpacing.md),
              _Notice(
                color: AppColors.warning,
                icon: Icons.hourglass_top,
                message:
                    'Comprobante en revisión: te notificaremos al aprobarse.',
              ),
            ] else if (rejectedPayment != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Notice(
                color: AppColors.danger,
                icon: Icons.error_outline,
                message: rejectedPayment.rejectionReason == null
                    ? 'El último comprobante fue rechazado. Puedes enviar uno nuevo.'
                    : 'Comprobante rechazado: ${rejectedPayment.rejectionReason}',
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Card(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.surfaceContainerHighest,
              child: ExpansionTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Reportar transferencia o pago QR'),
                subtitle: Text(
                  pendingPayment
                      ? 'Tienes un comprobante pendiente de revisión'
                      : 'Adjunta una captura para revisión manual',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _transferDetails.isEmpty
                          ? 'Los datos de transferencia aún no están configurados. '
                                'Solicítalos al administrador antes de realizar el pago.'
                          : _transferDetails,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (_transferDetails.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _copyTransferDetails,
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar datos de pago'),
                    ),
                  ],
                  if (!pendingPayment) ...[
                    const SizedBox(height: AppSpacing.sm),
                    if (_receiptBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Image.memory(
                          _receiptBytes!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _receiptFileName ?? 'Comprobante seleccionado',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    OutlinedButton.icon(
                      onPressed: _isUploadingReceipt ? null : _pickReceipt,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        _receiptBytes == null
                            ? 'Seleccionar comprobante'
                            : 'Cambiar imagen',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _receiptBytes == null || _isUploadingReceipt
                          ? null
                          : _uploadReceipt,
                      icon: _isUploadingReceipt
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.upload_file),
                      label: Text(
                        _isUploadingReceipt
                            ? 'Enviando comprobante…'
                            : 'Enviar comprobante para revisión',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'JPG, PNG o WEBP · máximo 5 MB',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (snapshot.payments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text('Historial de pagos', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              ...snapshot.payments
                  .take(4)
                  .map(
                    (payment) => _PaymentHistoryTile(
                      payment: payment,
                      formatDate: _formatDate,
                      formatPrice: _formatPrice,
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme) => Text(
    'Mi Suscripción',
    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
  );

  _SubscriptionStatus _statusFor(_SubscriptionSnapshot snapshot) {
    final expiration = snapshot.expiresAt?.toLocal();
    final today = DateTime.now();
    final daysRemaining = expiration == null
        ? 0
        : DateTime(
            expiration.year,
            expiration.month,
            expiration.day,
          ).difference(DateTime(today.year, today.month, today.day)).inDays;

    if (snapshot.subscriptionStatus == 'suspended') {
      return _SubscriptionStatus(
        label: 'Suspendida',
        color: AppColors.danger,
        daysRemaining: daysRemaining,
      );
    }
    if (expiration != null && daysRemaining < 0) {
      return _SubscriptionStatus(
        label: 'Vencida',
        color: AppColors.danger,
        daysRemaining: daysRemaining,
      );
    }
    if (snapshot.subscriptionStatus == 'trial') {
      return _SubscriptionStatus(
        label: 'En prueba',
        color: AppColors.info,
        daysRemaining: daysRemaining,
      );
    }
    if (expiration == null) {
      return _SubscriptionStatus(
        label: 'Activa',
        color: AppColors.success,
        daysRemaining: daysRemaining,
      );
    }
    if (daysRemaining <= 5) {
      return _SubscriptionStatus(
        label: 'Por vencer',
        color: AppColors.warning,
        daysRemaining: daysRemaining,
      );
    }
    return _SubscriptionStatus(
      label: 'Activa',
      color: AppColors.success,
      daysRemaining: daysRemaining,
    );
  }
}

class _SubscriptionSnapshot {
  const _SubscriptionSnapshot({
    required this.subscriptionStatus,
    required this.expiresAt,
    required this.priceCop,
    required this.payments,
  });

  final String subscriptionStatus;
  final DateTime? expiresAt;
  final int priceCop;
  final List<_PaymentRecord> payments;

  factory _SubscriptionSnapshot.fromJson(Map<String, dynamic> json) {
    final establishment = json['establishment'];
    final rawPayments = json['payments'];
    if (establishment is! Map<String, dynamic> || rawPayments is! List) {
      throw const FormatException('Respuesta de suscripción incompleta');
    }
    final rawExpiration = establishment['subscriptionExpiresAt'];
    final expiration = rawExpiration == null
        ? null
        : DateTime.tryParse(rawExpiration.toString());
    final rawPrice = establishment['priceCop'];
    if (rawPrice is! num || rawPrice < 1) {
      throw const FormatException('Precio de suscripción inválido');
    }
    final status = establishment['subscriptionStatus'];
    if (status is! String) {
      throw const FormatException('Estado de suscripción inválido');
    }
    return _SubscriptionSnapshot(
      subscriptionStatus: status,
      expiresAt: expiration,
      priceCop: rawPrice.toInt(),
      payments: rawPayments
          .whereType<Map<String, dynamic>>()
          .map(_PaymentRecord.fromJson)
          .toList(growable: false),
    );
  }
}

class _PaymentRecord {
  const _PaymentRecord({
    required this.method,
    required this.status,
    required this.amount,
    required this.createdAt,
    required this.reference,
    required this.rejectionReason,
  });

  final String method;
  final String status;
  final int amount;
  final DateTime? createdAt;
  final String? reference;
  final String? rejectionReason;

  factory _PaymentRecord.fromJson(Map<String, dynamic> json) {
    String? optionalText(Iterable<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    return _PaymentRecord(
      method: json['method'] is String ? json['method'] as String : '',
      status: json['status'] is String ? json['status'] as String : '',
      amount: json['amount'] is num ? (json['amount'] as num).toInt() : 0,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      reference: optionalText(['reference']),
      rejectionReason: optionalText([
        'rejectionReason',
        'rejectedReason',
        'reviewReason',
        'reason',
      ]),
    );
  }
}

class _SubscriptionStatus {
  const _SubscriptionStatus({
    required this.label,
    required this.color,
    required this.daysRemaining,
  });

  final String label;
  final Color color;
  final int daysRemaining;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final _SubscriptionStatus status;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: status.color),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.color,
    required this.icon,
    required this.message,
  });

  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.sm),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _PaymentHistoryTile extends StatelessWidget {
  const _PaymentHistoryTile({
    required this.payment,
    required this.formatDate,
    required this.formatPrice,
  });

  final _PaymentRecord payment;
  final String Function(DateTime) formatDate;
  final String Function(int) formatPrice;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (payment.status) {
      'approved' => AppColors.success,
      'pending' => AppColors.warning,
      'rejected' => AppColors.danger,
      _ => AppColors.neutral,
    };
    final methodLabel = payment.method == 'wompi'
        ? 'Wompi'
        : payment.method == 'manual_transfer'
        ? 'Transferencia / QR'
        : 'Pago';
    final date = payment.createdAt == null
        ? 'Fecha no disponible'
        : formatDate(payment.createdAt!.toLocal());

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.payments_outlined, color: statusColor),
      title: Text(
        '$methodLabel · \$${formatPrice(payment.amount)} COP',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [date, if (payment.reference != null) payment.reference!].join(' · '),
      ),
      trailing: Text(
        _statusLabel(payment.status),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: statusColor),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'approved' => 'Aprobado',
    'pending' => 'Pendiente',
    'rejected' => 'Rechazado',
    _ => status,
  };
}

class _ApiException implements Exception {
  const _ApiException(this.message);

  final String message;
}
