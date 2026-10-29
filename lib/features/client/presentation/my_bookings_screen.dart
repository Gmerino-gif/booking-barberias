import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import 'widgets/service_review_card.dart';

class BookingModel {
  final String id;
  final String establishmentId;
  final String professionalId;
  final String establishmentName;
  final String serviceName;
  final String professionalName;
  final DateTime startAt;
  final int durationMin;
  final int price;
  final String status;
  final String notes;

  const BookingModel({
    required this.id,
    this.establishmentId = '',
    this.professionalId = '',
    required this.establishmentName,
    required this.serviceName,
    required this.professionalName,
    required this.startAt,
    required this.durationMin,
    required this.price,
    required this.status,
    this.notes = '',
  });

  /// Una cita completada puede calificarse desde el historial.
  bool get canReview =>
      status == 'completed' &&
      id.isNotEmpty &&
      establishmentId.isNotEmpty;
}

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = true;
  String? _error;
  List<BookingModel> _bookings = const [];

  /// Reseñas ya publicadas, indexadas por el id de la cita calificada.
  Map<String, SubmittedReview> _reviewsByBooking = const {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookings();
    _loadReviews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Inicia sesión para ver tus reservas';
      });
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/bookings/my'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=UTF-8',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode != 200) {
        final decoded = jsonDecode(response.body);
        final message = decoded is Map<String, dynamic>
            ? decoded['message']
            : null;
        throw Exception(
          message is String ? message : 'No se pudieron cargar tus reservas',
        );
      }

      final decoded = jsonDecode(response.body);
      final items =
          decoded is Map<String, dynamic> && decoded['bookings'] is List
          ? decoded['bookings'] as List
          : <dynamic>[];

      setState(() {
        _bookings = items.map<BookingModel>(_mapBooking).toList();
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

  Future<void> _cancelBooking(BookingModel booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar reserva'),
        content: Text(
          '¿Quieres cancelar la cita de ${booking.serviceName} en ${booking.establishmentName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancelar cita'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/bookings/${booking.id}/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'status': 'cancelled'}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Reserva cancelada')));
        await _loadBookings();
      } else {
        final body = jsonDecode(response.body);
        final message =
            body is Map<String, dynamic> && body['message'] is String
            ? body['message'] as String
            : 'No se pudo cancelar la reserva';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar para cancelar la reserva'),
          ),
        );
      }
    }
  }

  /// Carga las reseñas del cliente para saber qué servicios ya calificó.
  Future<void> _loadReviews() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/reviews/my'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=UTF-8',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted || response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      final items = decoded is Map<String, dynamic> && decoded['reviews'] is List
          ? decoded['reviews'] as List
          : <dynamic>[];

      final byBooking = <String, SubmittedReview>{};
      for (final item in items.whereType<Map<String, dynamic>>()) {
        final bookingId = _readId(item['bookingId']);
        if (bookingId == null || bookingId.isEmpty) continue;
        byBooking[bookingId] = SubmittedReview.fromJson(item);
      }
      setState(() => _reviewsByBooking = byBooking);
    } catch (_) {
      // Las reseñas son secundarias: el historial sigue visible sin conexión.
    }
  }

  /// Publica la reseña de una cita completada. Devuelve el mensaje de error o
  /// `null` si se guardó correctamente.
  Future<String?> _submitReview(
    BookingModel booking,
    ServiceReviewDraft draft,
  ) async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      return 'Inicia sesión para calificar tu servicio';
    }
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/reviews'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode({
              'bookingId': booking.id,
              'establishmentId': booking.establishmentId,
              if (booking.professionalId.isNotEmpty)
                'professionalId': booking.professionalId,
              if (draft.rating != null) 'rating': draft.rating,
              if (draft.ratingProfessional != null)
                'ratingProfessional': draft.ratingProfessional,
              'tags': draft.tags,
              'comment': draft.comment,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return null;

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Gracias por calificar tu servicio!')),
        );
        await _loadReviews();
        return null;
      }

      final body = jsonDecode(response.body);
      final message = body is Map<String, dynamic> && body['message'] is String
          ? body['message'] as String
          : 'No se pudo publicar tu reseña';
      return message;
    } catch (_) {
      return 'No se pudo conectar para publicar tu reseña';
    }
  }

  BookingModel _mapBooking(dynamic item) {
    final map = item is Map<String, dynamic> ? item : <String, dynamic>{};

    final establishment = map['establishmentId'];
    final service = map['serviceId'];
    final professional = map['professionalId'];
    final startAt =
        AppFormatters.parseApiDateTime(map['startAt']) ?? DateTime.now();
    final duration =
        _readInt(map['durationMin']) ??
        (service is Map<String, dynamic>
            ? _readInt(service['durationMin'])
            : null) ??
        30;
    final price =
        _readInt(map['price']) ??
        (service is Map<String, dynamic> ? _readInt(service['price']) : null) ??
        0;

    return BookingModel(
      id: (map['_id'] ?? map['id'] ?? '').toString(),
      establishmentId:
          _readId(establishment) ?? _readId(map['establishmentId']) ?? '',
      professionalId:
          _readId(professional) ?? _readId(map['professionalId']) ?? '',
      establishmentName:
          (establishment is Map<String, dynamic>
                  ? (establishment['name'] ??
                        map['establishmentName'] ??
                        'Barbería')
                  : (map['establishmentName'] ?? 'Barbería'))
              .toString(),
      serviceName:
          (service is Map<String, dynamic>
                  ? (service['name'] ?? map['serviceName'] ?? 'Servicio')
                  : (map['serviceName'] ?? 'Servicio'))
              .toString(),
      professionalName:
          (professional is Map<String, dynamic>
                  ? (professional['name'] ??
                        map['professionalName'] ??
                        'Profesional')
                  : (map['professionalName'] ?? 'Profesional'))
              .toString(),
      startAt: startAt,
      durationMin: duration,
      price: price,
      status: (map['status'] ?? 'pending').toString(),
      notes: (map['notes'] ?? '').toString(),
    );
  }

  int? _readInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Id de un campo que puede venir como cadena o como documento poblado.
  String? _readId(dynamic value) {
    if (value is Map<String, dynamic>) {
      return _readId(value['_id'] ?? value['id']);
    }
    final id = value?.toString().trim() ?? '';
    return id.isEmpty ? null : id;
  }

  List<BookingModel> get _upcoming {
    final now = DateTime.now();
    final upcoming = _bookings.where((booking) {
      return booking.startAt.isAfter(now) &&
          (booking.status == 'pending' || booking.status == 'confirmed');
    }).toList();
    upcoming.sort((a, b) => a.startAt.compareTo(b.startAt));
    return upcoming;
  }

  List<BookingModel> get _history {
    final now = DateTime.now();
    final history = _bookings.where((booking) {
      return booking.startAt.isBefore(now) ||
          booking.status == 'completed' ||
          booking.status == 'cancelled' ||
          booking.status == 'no_show';
    }).toList();
    history.sort((a, b) => b.startAt.compareTo(a.startAt));
    return history;
  }

  String _formatDate(DateTime date) => AppFormatters.date(date);

  String _formatTime(DateTime date) => AppFormatters.time(date);

  String _formatPrice(int value) => AppFormatters.currency(value);

  ({Color color, String label, IconData icon}) _getStatusInfo(String status) {
    const icons = <String, IconData>{
      'pending': Icons.schedule,
      'confirmed': Icons.check_circle,
      'completed': Icons.done_all,
      'cancelled': Icons.cancel,
      'canceled': Icons.cancel,
      'no_show': Icons.person_off,
    };
    return (
      color: AppColors.forStatus(status),
      label: AppFormatters.statusLabel(status),
      icon: icons[status.toLowerCase()] ?? Icons.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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

    return Column(
      children: [
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.secondary,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Próximas'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildList(_upcoming, isUpcoming: true),
              _buildList(_history, isUpcoming: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<BookingModel> list, {required bool isUpcoming}) {
    if (list.isEmpty) {
      return _buildEmptyState(isUpcoming);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) =>
          _buildBookingCard(list[index], isUpcoming),
    );
  }

  Widget _buildEmptyState(bool isUpcoming) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isUpcoming ? Icons.event_available : Icons.event_busy,
            size: 72,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            isUpcoming
                ? 'No tienes reservas próximas'
                : 'Aún no tienes historial',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isUpcoming
                ? 'Cuando reserves una cita aparecerá aquí'
                : 'Tus reservas anteriores aparecerán aquí',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(BookingModel booking, bool isUpcoming) {
    final theme = Theme.of(context);
    final statusInfo = _getStatusInfo(booking.status);
    final shortId = booking.id.length > 8
        ? booking.id.substring(0, 8)
        : booking.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusInfo.color.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13),
                topRight: Radius.circular(13),
              ),
            ),
            child: Row(
              children: [
                Icon(statusInfo.icon, size: 18, color: statusInfo.color),
                const SizedBox(width: 6),
                Text(
                  statusInfo.label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: AppTypography.bold,
                    color: statusInfo.color,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '#$shortId',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.serviceName,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.store,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        booking.establishmentName,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildInfoRow(
                  theme,
                  Icons.calendar_today,
                  '${_formatDate(booking.startAt)} · ${_formatTime(booking.startAt)}',
                ),
                const SizedBox(height: 6),
                _buildInfoRow(
                  theme,
                  Icons.person_outline,
                  booking.professionalName,
                ),
                const SizedBox(height: 6),
                _buildInfoRow(
                  theme,
                  Icons.timer_outlined,
                  '${booking.durationMin} min',
                ),
                if (booking.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notes,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            booking.notes,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatPrice(booking.price),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (isUpcoming)
                      OutlinedButton(
                        onPressed: () => _cancelBooking(booking),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 0,
                          ),
                          minimumSize: const Size(0, 32),
                        ),
                        child: Text(
                          'Cancelar',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                  ],
                ),
                if (booking.canReview) ...[
                  const SizedBox(height: 12),
                  ServiceReviewCard(
                    key: ValueKey('review-${booking.id}'),
                    establishmentName: booking.establishmentName,
                    professionalName: booking.professionalName,
                    existing: _reviewsByBooking[booking.id],
                    onSubmit: (draft) => _submitReview(booking, draft),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
