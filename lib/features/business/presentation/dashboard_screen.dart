import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';

/// El backend entrega los nombres ya resueltos en campos "planos"
/// (`clientName`, `professionalName`, `serviceName`, `clientPhone`) porque son
/// el resultado de un `populate`. Algunas respuestas pueden incluir también el
/// documento anidado, así que se aceptan ambos formatos y se prefiere el plano.
String _resolveLabel(
  Map<String, dynamic> map,
  String flatKey,
  Map<String, dynamic>? nested,
  String nestedKey,
  String fallback,
) {
  final resolved = _resolveValue(map, flatKey, nested, nestedKey);
  return resolved ?? fallback;
}

/// Igual que [_resolveLabel] pero sin valor por defecto: devuelve `null`
/// cuando el dato no existe o viene vacío (p. ej. el teléfono del cliente).
String? _resolveValue(
  Map<String, dynamic> map,
  String flatKey,
  Map<String, dynamic>? nested,
  String nestedKey,
) {
  final flat = map[flatKey];
  final value = flat is String && flat.trim().isNotEmpty
      ? flat
      : nested?[nestedKey];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _readRating(dynamic value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

List<String> _readTags(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();
}

/// Reseña que el cliente dejó al servicio; `null` mientras no lo califique.
_BookingReview? _mapBookingReview(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final review = _BookingReview(
    rating: _readRating(raw['rating']),
    ratingProfessional: _readRating(raw['ratingProfessional']),
    tags: _readTags(raw['tags']),
    comment: (raw['comment'] is String ? raw['comment'] as String : '').trim(),
  );
  return review.isEmpty ? null : review;
}

class _BookingReview {
  final int? rating;
  final int? ratingProfessional;
  final List<String> tags;
  final String comment;

  const _BookingReview({
    this.rating,
    this.ratingProfessional,
    this.tags = const [],
    this.comment = '',
  });

  bool get isEmpty =>
      rating == null &&
      ratingProfessional == null &&
      tags.isEmpty &&
      comment.isEmpty;
}

/// Reseña del establecimiento tal como la ve el negocio (con el autor).
class _ReviewSummary {
  final String clientName;
  final String? professionalName;
  final int? rating;
  final int? ratingProfessional;
  final List<String> tags;
  final String comment;

  const _ReviewSummary({
    required this.clientName,
    this.professionalName,
    this.rating,
    this.ratingProfessional,
    this.tags = const [],
    this.comment = '',
  });
}

class _BookingSummary {
  final String id;
  final String clientName;
  final String? clientPhone;
  final String serviceName;
  final String professionalName;
  final DateTime startAt;
  final int price;
  final String status;
  final _BookingReview? review;

  const _BookingSummary({
    required this.id,
    required this.clientName,
    this.clientPhone,
    required this.serviceName,
    required this.professionalName,
    required this.startAt,
    required this.price,
    required this.status,
    this.review,
  });
}

class _ServiceSummary {
  final String id;
  final String name;
  final String description;
  final int price;
  final int durationMin;

  const _ServiceSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMin,
  });
}

class BusinessDashboardScreen extends StatefulWidget {
  const BusinessDashboardScreen({super.key});

  @override
  State<BusinessDashboardScreen> createState() =>
      _BusinessDashboardScreenState();
}

class _BusinessDashboardScreenState extends State<BusinessDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  String _businessName = 'Negocio';
  double _rating = 0;
  List<_BookingSummary> _bookings = const [];
  List<_ServiceSummary> _services = const [];
  List<_ReviewSummary> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Inicia sesión para ver el panel del negocio';
      });
      return;
    }

    try {
      final establishmentResponse = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/establishments/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));

      final establishmentBody = _decodeBody(establishmentResponse.body);
      final establishment = establishmentBody is Map<String, dynamic>
          ? establishmentBody['establishment']
          : null;

      if (establishmentResponse.statusCode != 200 ||
          establishment is! Map<String, dynamic>) {
        throw Exception(
          _readMessage(establishmentBody) ??
              'No se pudo cargar la información del negocio',
        );
      }

      final establishmentId =
          (establishment['_id'] ?? establishment['id'] ?? '').toString();
      final businessName = (establishment['name'] ?? 'Negocio').toString();
      final rating = establishment['rating'] is num
          ? (establishment['rating'] as num).toDouble()
          : 0.0;

      final bookingsFuture = http.get(
        Uri.parse('${ApiConfig.baseUrl}/bookings/business'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final servicesFuture = http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/services?establishmentId=$establishmentId',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
      // Reseñas que los clientes dejaron al negocio y a cada barbero.
      final reviewsFuture = http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/reviews/establishment/$establishmentId',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      final responses = await Future.wait([
        bookingsFuture.timeout(const Duration(seconds: 15)),
        servicesFuture.timeout(const Duration(seconds: 15)),
        reviewsFuture.timeout(const Duration(seconds: 15)),
      ]);

      final bookingsBody = _decodeBody(responses[0].body);
      final servicesBody = _decodeBody(responses[1].body);
      final reviewsBody = _decodeBody(responses[2].body);

      final bookingsList =
          (bookingsBody is Map<String, dynamic>
                  ? bookingsBody['bookings']
                  : null)
              as List<dynamic>? ??
          const [];
      final servicesList =
          (servicesBody is Map<String, dynamic>
                  ? servicesBody['services']
                  : null)
              as List<dynamic>? ??
          const [];
      // Un fallo al traer reseñas no debe romper el panel: se lista vacío.
      final reviewsList =
          (reviewsBody is Map<String, dynamic> ? reviewsBody['reviews'] : null)
              as List<dynamic>? ??
          const [];

      if (!mounted) return;

      setState(() {
        _businessName = businessName;
        _rating = rating;
        _bookings = bookingsList
            .whereType<Map<String, dynamic>>()
            .map(_mapBooking)
            .toList();
        _services = servicesList
            .whereType<Map<String, dynamic>>()
            .map(_mapService)
            .toList();
        _reviews = reviewsList
            .whereType<Map<String, dynamic>>()
            .map(_mapReview)
            .toList();
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  _BookingSummary _mapBooking(Map<String, dynamic> map) {
    final service = map['serviceId'] is Map<String, dynamic>
        ? map['serviceId'] as Map<String, dynamic>
        : null;
    final client = map['clientId'] is Map<String, dynamic>
        ? map['clientId'] as Map<String, dynamic>
        : null;
    final professional = map['professionalId'] is Map<String, dynamic>
        ? map['professionalId'] as Map<String, dynamic>
        : null;

    return _BookingSummary(
      id: (map['_id'] ?? map['id'] ?? '').toString(),
      clientName: _resolveLabel(map, 'clientName', client, 'name', 'Cliente'),
      clientPhone: _resolveValue(map, 'clientPhone', client, 'phone'),
      serviceName: _resolveLabel(map, 'serviceName', service, 'name', 'Servicio'),
      professionalName: _resolveLabel(
        map,
        'professionalName',
        professional,
        'name',
        'Profesional',
      ),
      startAt:
          AppFormatters.parseApiDateTime(map['startAt']) ?? DateTime.now(),
      price: _readInt(map['price']) ?? _readInt(service?['price']) ?? 0,
      status: (map['status'] ?? 'pending').toString(),
      review: _mapBookingReview(map['review']),
    );
  }

  _ReviewSummary _mapReview(Map<String, dynamic> map) {
    final author = map['userId'] is Map<String, dynamic>
        ? map['userId'] as Map<String, dynamic>
        : null;
    final professional = map['professionalId'] is Map<String, dynamic>
        ? map['professionalId'] as Map<String, dynamic>
        : null;

    return _ReviewSummary(
      clientName: _resolveLabel(map, 'clientName', author, 'name', 'Cliente'),
      professionalName: _resolveValue(
        map,
        'professionalName',
        professional,
        'name',
      ),
      rating: _readRating(map['rating']),
      ratingProfessional: _readRating(map['ratingProfessional']),
      tags: _readTags(map['tags']),
      comment: (map['comment'] is String ? map['comment'] as String : '')
          .trim(),
    );
  }

  _ServiceSummary _mapService(Map<String, dynamic> map) {
    return _ServiceSummary(
      id: (map['_id'] ?? map['id'] ?? '').toString(),
      name: (map['name'] ?? 'Servicio').toString(),
      description: (map['description'] ?? '').toString(),
      price: _readInt(map['price']) ?? 0,
      durationMin: _readInt(map['durationMin']) ?? 30,
    );
  }

  int? _readInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic>? _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _readMessage(Map<String, dynamic>? body) {
    final value = body?['message'];
    return value is String ? value : null;
  }

  String _formatCurrency(int value) => AppFormatters.currency(value);

  String _formatTime(DateTime date) => AppFormatters.time(date);

  String _formatDate(DateTime date) =>
      AppFormatters.date(date, includeYear: false);

  List<_BookingSummary> get _upcomingBookings {
    final now = DateTime.now();
    final result = _bookings
        .where((booking) => booking.startAt.isAfter(now))
        .toList();
    result.sort((a, b) => a.startAt.compareTo(b.startAt));
    return result;
  }

  int get _todaysBookingCount {
    final today = DateTime.now();
    return _bookings.where((booking) {
      return booking.startAt.year == today.year &&
          booking.startAt.month == today.month &&
          booking.startAt.day == today.day;
    }).length;
  }

  /// Revenue = sum of every *completed* service booked at this business.
  ///
  /// Pending, confirmed, cancelled and no-show bookings are not earnings yet,
  /// so they must never be added to the total.
  int get _completedRevenue {
    return _bookings
        .where((booking) => booking.status == 'completed')
        .fold<int>(0, (sum, booking) => sum + booking.price);
  }

  /// Same figure but restricted to today's completed services.
  int get _todaysCompletedRevenue {
    final today = DateTime.now();
    return _bookings
        .where((booking) {
          return booking.status == 'completed' &&
              booking.startAt.year == today.year &&
              booking.startAt.month == today.month &&
              booking.startAt.day == today.day;
        })
        .fold<int>(0, (sum, booking) => sum + booking.price);
  }

  DateTime? get _nextBookingDate {
    if (_upcomingBookings.isEmpty) return null;
    return _upcomingBookings.first.startAt;
  }

  ({Color color, String label}) _getStatusInfo(String status) {
    return (
      color: AppColors.forStatus(status),
      label: AppFormatters.statusLabel(status),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final nextBooking = _nextBookingDate;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Hola, $_businessName 👋',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                'Resumen del negocio',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            // Promedio de estrellas que los clientes le dieron al negocio.
            if (_rating > 0)
              Chip(
                avatar: Icon(
                  Icons.star,
                  size: 16,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                label: Text(_rating.toStringAsFixed(1)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                title: 'Reservas hoy',
                value: _todaysBookingCount.toString(),
                icon: Icons.event_available,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: 'Ingresos',
                value: _formatCurrency(_completedRevenue),
                subtitle: 'Hoy: ${_formatCurrency(_todaysCompletedRevenue)}',
                icon: Icons.attach_money,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                title: 'Servicios',
                value: _services.length.toString(),
                icon: Icons.content_cut,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: 'Próxima cita',
                value: nextBooking == null
                    ? 'Sin citas'
                    : _formatTime(nextBooking),
                icon: Icons.schedule,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Próximas reservas',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (_upcomingBookings.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No tienes reservas próximas en este momento.'),
            ),
          )
        else
          ..._upcomingBookings.take(5).map((booking) {
            final statusInfo = _getStatusInfo(booking.status);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: statusInfo.color.withValues(alpha: 0.15),
                  child: Icon(Icons.person_outline, color: statusInfo.color),
                ),
                title: Text(booking.clientName),
                isThreeLine: true,
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${booking.serviceName} · ${booking.professionalName}',
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${_formatDate(booking.startAt)} '
                      '${_formatTime(booking.startAt)}',
                    ),
                    if (booking.clientPhone != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: 13,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              booking.clientPhone!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatCurrency(booking.price)),
                    const SizedBox(height: 6),
                    Chip(
                      label: Text(statusInfo.label),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: statusInfo.color.withValues(alpha: 0.12),
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Reseñas recientes',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_reviews.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aún no tienes reseñas de tus clientes.'),
            ),
          )
        else
          ..._reviews.take(5).map((review) => _ReviewTile(review: review)),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final _ReviewSummary review;

  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    review.clientName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (review.rating != null) _StarsRow(rating: review.rating!),
              ],
            ),
            if (review.professionalName != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Atención de ${review.professionalName}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (review.ratingProfessional != null)
                    _StarsRow(rating: review.ratingProfessional!),
                ],
              ),
            ],
            if (review.tags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: review.tags
                    .map((tag) => _TagPill(label: tag))
                    .toList(),
              ),
            ],
            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(review.comment, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fila de 5 estrellas rellenas según la calificación (1-5).
class _StarsRow extends StatelessWidget {
  final int rating;

  const _StarsRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (index) => Icon(
          index < rating ? Icons.star : Icons.star_border,
          size: 14,
          color: color,
        ),
      ),
    );
  }
}

/// Etiqueta de opinión rápida elegida por el cliente.
class _TagPill extends StatelessWidget {
  final String label;

  const _TagPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// Calificación que el cliente dejó en una cita concreta de la agenda.
class _BookingReviewSummary extends StatelessWidget {
  final _BookingReview review;

  const _BookingReviewSummary({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratings = [
      if (review.rating != null) 'Negocio ${review.rating}/5',
      if (review.ratingProfessional != null)
        'Barbero ${review.ratingProfessional}/5',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ratings.isNotEmpty)
          Row(
            children: [
              Icon(Icons.star, size: 14, color: theme.colorScheme.secondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Calificada · ${ratings.join(' · ')}',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
        if (review.tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: review.tags.map((tag) => _TagPill(label: tag)).toList(),
          ),
        ],
        if (review.comment.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(review.comment, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class BusinessAgendaScreen extends StatefulWidget {
  const BusinessAgendaScreen({super.key});

  @override
  State<BusinessAgendaScreen> createState() => _BusinessAgendaScreenState();
}

class _BusinessAgendaScreenState extends State<BusinessAgendaScreen> {
  bool _isLoading = true;
  String? _error;
  List<_BookingSummary> _bookings = const [];

  Future<void> _changeBookingStatus(
    _BookingSummary booking,
    String status,
  ) async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/${booking.id}/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': status}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estado de la reserva actualizado')),
        );
        await _loadAgenda();
      } else {
        final body = _decodeBody(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _readMessage(body) ?? 'No se pudo actualizar la reserva',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar para actualizar la reserva'),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAgenda();
  }

  Future<void> _loadAgenda() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Inicia sesión para ver tu agenda';
      });
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/bookings/business'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));

      final decoded = _decodeBody(response.body);
      if (!mounted) return;

      if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
        throw Exception(_readMessage(decoded) ?? 'No se pudo cargar la agenda');
      }

      final items =
          (decoded['bookings'] is List
                  ? decoded['bookings']
                  : const <dynamic>[])
              as List<dynamic>;

      setState(() {
        _bookings = items
            .whereType<Map<String, dynamic>>()
            .map(_mapBooking)
            .toList();
        _bookings.sort((a, b) => a.startAt.compareTo(b.startAt));
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  _BookingSummary _mapBooking(Map<String, dynamic> map) {
    final service = map['serviceId'] is Map<String, dynamic>
        ? map['serviceId'] as Map<String, dynamic>
        : null;
    final client = map['clientId'] is Map<String, dynamic>
        ? map['clientId'] as Map<String, dynamic>
        : null;
    final professional = map['professionalId'] is Map<String, dynamic>
        ? map['professionalId'] as Map<String, dynamic>
        : null;

    return _BookingSummary(
      id: (map['_id'] ?? map['id'] ?? '').toString(),
      clientName: _resolveLabel(map, 'clientName', client, 'name', 'Cliente'),
      clientPhone: _resolveValue(map, 'clientPhone', client, 'phone'),
      serviceName: _resolveLabel(map, 'serviceName', service, 'name', 'Servicio'),
      professionalName: _resolveLabel(
        map,
        'professionalName',
        professional,
        'name',
        'Profesional',
      ),
      startAt:
          AppFormatters.parseApiDateTime(map['startAt']) ?? DateTime.now(),
      price: _readInt(map['price']) ?? _readInt(service?['price']) ?? 0,
      status: (map['status'] ?? 'pending').toString(),
      review: _mapBookingReview(map['review']),
    );
  }

  int? _readInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic>? _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _readMessage(Map<String, dynamic>? body) {
    final value = body?['message'];
    return value is String ? value : null;
  }

  String _formatDate(DateTime date) =>
      AppFormatters.date(date, includeYear: false);

  String _formatTime(DateTime date) => AppFormatters.time(date);

  String _formatCurrency(int value) => AppFormatters.currency(value);

  ({Color color, String label}) _getStatusInfo(String status) {
    return (
      color: AppColors.forStatus(status),
      label: AppFormatters.statusLabel(status),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final grouped = <String, List<_BookingSummary>>{};
    for (final booking in _bookings) {
      grouped.putIfAbsent(_formatDate(booking.startAt), () => []).add(booking);
    }

    final dates = grouped.keys.toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Agenda', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.md),
        if (dates.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No hay citas agendadas todavía.'),
            ),
          )
        else
          ...dates.map((date) {
            final list = grouped[date]!;
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ...list.map((booking) {
                      final statusInfo = _getStatusInfo(booking.status);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: statusInfo.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.schedule,
                                color: statusInfo.color,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking.clientName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${booking.serviceName} · ${booking.professionalName}',
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${_formatTime(booking.startAt)} hrs'),
                                  if (booking.clientPhone != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.phone,
                                          size: 13,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: AppSpacing.xs),
                                        Expanded(
                                          child: Text(
                                            booking.clientPhone!,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (booking.review != null) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    _BookingReviewSummary(
                                      review: booking.review!,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Chip(
                                  label: Text(statusInfo.label),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: statusInfo.color.withValues(
                                    alpha: 0.12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatCurrency(booking.price),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall,
                                ),
                                if (booking.status == 'pending' ||
                                    booking.status == 'confirmed')
                                  PopupMenuButton<String>(
                                    tooltip: 'Actualizar reserva',
                                    onSelected: (status) =>
                                        _changeBookingStatus(booking, status),
                                    itemBuilder: (_) => [
                                      if (booking.status == 'pending')
                                        const PopupMenuItem(
                                          value: 'confirmed',
                                          child: Text('Confirmar'),
                                        ),
                                      if (booking.status == 'pending' ||
                                          booking.status == 'confirmed')
                                        const PopupMenuItem(
                                          value: 'cancelled',
                                          child: Text('Cancelar'),
                                        ),
                                      if (booking.status == 'confirmed' &&
                                          booking.startAt.isBefore(
                                            DateTime.now(),
                                          )) ...[
                                        const PopupMenuItem(
                                          value: 'completed',
                                          child: Text('Marcar completada'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'no_show',
                                          child: Text('Marcar inasistencia'),
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class BusinessServicesScreen extends StatefulWidget {
  const BusinessServicesScreen({super.key});

  @override
  State<BusinessServicesScreen> createState() => _BusinessServicesScreenState();
}

class _BusinessServicesScreenState extends State<BusinessServicesScreen> {
  bool _isLoading = true;
  String? _error;
  String? _establishmentId;
  List<_ServiceSummary> _services = const [];

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Inicia sesión para ver tus servicios';
      });
      return;
    }

    try {
      final establishmentResponse = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/establishments/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));

      final establishmentBody = _decodeBody(establishmentResponse.body);
      final establishment = establishmentBody is Map<String, dynamic>
          ? establishmentBody['establishment']
          : null;

      if (establishmentResponse.statusCode != 200 ||
          establishment is! Map<String, dynamic>) {
        throw Exception(
          _readMessage(establishmentBody) ?? 'No se pudo cargar el negocio',
        );
      }

      final establishmentId =
          (establishment['_id'] ?? establishment['id'] ?? '').toString();
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/services?establishmentId=$establishmentId',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=UTF-8',
            },
          )
          .timeout(const Duration(seconds: 15));

      final decoded = _decodeBody(response.body);
      if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
        throw Exception(
          _readMessage(decoded) ?? 'No se pudieron cargar los servicios',
        );
      }

      final output = decoded['services'];
      final items = output is List ? output : const <dynamic>[];

      if (!mounted) return;
      setState(() {
        _establishmentId = establishmentId;
        _services = items
            .whereType<Map<String, dynamic>>()
            .map(_mapService)
            .toList();
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  _ServiceSummary _mapService(Map<String, dynamic> map) {
    return _ServiceSummary(
      id: (map['_id'] ?? map['id'] ?? '').toString(),
      name: (map['name'] ?? 'Servicio').toString(),
      description: (map['description'] ?? '').toString(),
      price: _readInt(map['price']) ?? 0,
      durationMin: _readInt(map['durationMin']) ?? 30,
    );
  }

  int? _readInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Map<String, dynamic>? _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _readMessage(Map<String, dynamic>? body) {
    final value = body?['message'];
    return value is String ? value : null;
  }

  String _formatCurrency(int value) => AppFormatters.currency(value);

  Future<void> _editService([_ServiceSummary? service]) async {
    final nameController = TextEditingController(text: service?.name ?? '');
    final descriptionController = TextEditingController(text: service?.description ?? '');
    final priceController = TextEditingController(text: service?.price.toString() ?? '');
    final durationController = TextEditingController(text: service?.durationMin.toString() ?? '30');
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(service == null ? 'Agregar servicio' : 'Editar servicio'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: nameController, maxLength: 100, decoration: const InputDecoration(labelText: 'Nombre'), validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Ingresa un nombre' : null),
              TextFormField(controller: descriptionController, maxLength: 500, decoration: const InputDecoration(labelText: 'Descripción')),
              TextFormField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio (COP)'), validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? 'Ingresa un precio válido' : null),
              TextFormField(controller: durationController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duración (minutos)'), validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 5 || n > 480 ? 'Usa entre 5 y 480 minutos' : null; }),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true); }, child: const Text('Guardar')),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      nameController.dispose(); descriptionController.dispose(); priceController.dispose(); durationController.dispose();
      return;
    }

    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    final establishmentId = _establishmentId;
    if (token == null || establishmentId == null) {
      nameController.dispose();
      descriptionController.dispose();
      priceController.dispose();
      durationController.dispose();
      return;
    }
    try {
      final uri = service == null
          ? Uri.parse('${ApiConfig.baseUrl}/services')
          : Uri.parse('${ApiConfig.baseUrl}/services/${service.id}');
      final payload = jsonEncode({
        'establishmentId': establishmentId,
        'name': nameController.text.trim(),
        'description': descriptionController.text.trim(),
        'price': int.parse(priceController.text),
        'durationMin': int.parse(durationController.text),
      });
      final response = service == null
          ? await http.post(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: payload)
          : await http.put(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'}, body: payload);
      if (!mounted) return;
      if (response.statusCode == 201 || response.statusCode == 200) {
        await _loadServices();
      } else {
        final body = _decodeBody(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_readMessage(body) ?? 'No se pudo guardar el servicio')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo conectar para guardar el servicio')));
    } finally {
      nameController.dispose(); descriptionController.dispose(); priceController.dispose(); durationController.dispose();
    }
  }

  Future<void> _deleteService(_ServiceSummary service) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar servicio'),
        content: Text('¿Eliminar ${service.name}? Las reservas existentes se conservan y pueden impedir la eliminación.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    try {
      final response = await http.delete(Uri.parse('${ApiConfig.baseUrl}/services/${service.id}'), headers: {'Authorization': 'Bearer $token'});
      if (!mounted) return;
      if (response.statusCode == 200) {
        await _loadServices();
      } else {
        final body = _decodeBody(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_readMessage(body) ?? 'No se pudo eliminar el servicio')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo conectar para eliminar el servicio')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Servicios del negocio',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: () => _editService(), icon: const Icon(Icons.add), label: const Text('Agregar servicio'))),
        if (_services.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Aún no hay servicios registrados para este negocio.',
              ),
            ),
          )
        else
          ..._services.map(
            (service) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.content_cut)),
                title: Text(service.name),
                subtitle: Text(
                  service.description.isEmpty
                      ? 'Sin descripción'
                      : service.description,
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) => action == 'edit' ? _editService(service) : _deleteService(service),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_formatCurrency(service.price)),
                    const SizedBox(height: 4),
                    Text(
                      '${service.durationMin} min',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Icon(Icons.more_horiz, size: 18),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(title, style: theme.textTheme.bodySmall),
            if (subtitle != null)
              Text(
                subtitle!,
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
