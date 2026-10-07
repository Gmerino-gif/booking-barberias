import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../auth/providers/auth_provider.dart';

class BookingModel {
  final String id;
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
    required this.establishmentName,
    required this.serviceName,
    required this.professionalName,
    required this.startAt,
    required this.durationMin,
    required this.price,
    required this.status,
    this.notes = '',
  });
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookings();
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
        final message = decoded is Map<String, dynamic> ? decoded['message'] : null;
        throw Exception(message is String ? message : 'No se pudieron cargar tus reservas');
      }

      final decoded = jsonDecode(response.body);
      final items = decoded is Map<String, dynamic> && decoded['bookings'] is List
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

  BookingModel _mapBooking(dynamic item) {
    final map = item is Map<String, dynamic> ? item : <String, dynamic>{};

    final establishment = map['establishmentId'];
    final service = map['serviceId'];
    final professional = map['professionalId'];
    final startAtRaw = map['startAt'];
    final startAt = DateTime.tryParse(startAtRaw?.toString() ?? '') ?? DateTime.now();
    final duration = _readInt(map['durationMin']) ??
        (service is Map<String, dynamic> ? _readInt(service['durationMin']) : null) ??
        30;
    final price = _readInt(map['price']) ??
        (service is Map<String, dynamic> ? _readInt(service['price']) : null) ??
        0;

    return BookingModel(
      id: (map['_id'] ?? map['id'] ?? '').toString(),
      establishmentName: (establishment is Map<String, dynamic>
              ? (establishment['name'] ?? map['establishmentName'] ?? 'Barbería')
              : (map['establishmentName'] ?? 'Barbería'))
          .toString(),
      serviceName: (service is Map<String, dynamic>
              ? (service['name'] ?? map['serviceName'] ?? 'Servicio')
              : (map['serviceName'] ?? 'Servicio'))
          .toString(),
      professionalName: (professional is Map<String, dynamic>
              ? (professional['name'] ?? map['professionalName'] ?? 'Profesional')
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

  static const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _months = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  String _formatDate(DateTime date) {
    return '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatPrice(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < raw.length; index++) {
      if (index > 0 && (raw.length - index) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(raw[index]);
    }
    return '\$${buffer.toString()}';
  }

  ({Color color, String label, IconData icon}) _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
        return (color: Colors.orange, label: 'Pendiente', icon: Icons.schedule);
      case 'confirmed':
        return (color: Colors.green, label: 'Confirmada', icon: Icons.check_circle);
      case 'completed':
        return (color: Colors.blue, label: 'Completada', icon: Icons.done_all);
      case 'cancelled':
        return (color: Colors.red, label: 'Cancelada', icon: Icons.cancel);
      case 'no_show':
        return (color: Colors.grey, label: 'No asistió', icon: Icons.person_off);
      default:
        return (color: Colors.grey, label: status, icon: Icons.info);
    }
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
      itemBuilder: (context, index) => _buildBookingCard(list[index], isUpcoming),
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
          const SizedBox(height: 16),
          Text(
            isUpcoming ? 'No tienes reservas próximas' : 'Aún no tienes historial',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            isUpcoming
                ? 'Cuando reserves una cita aparecerá aquí'
                : 'Tus reservas anteriores aparecerán aquí',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(BookingModel booking, bool isUpcoming) {
    final theme = Theme.of(context);
    final statusInfo = _getStatusInfo(booking.status);
    final shortId = booking.id.length > 8 ? booking.id.substring(0, 8) : booking.id;

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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusInfo.color,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '#$shortId',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.store, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        booking.establishmentName,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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
                        Icon(Icons.notes, size: 14, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            booking.notes,
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.onSurfaceVariant,
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (isUpcoming)
                      OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cancelar reserva (próximamente)')),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
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
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
