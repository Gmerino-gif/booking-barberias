import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../auth/providers/auth_provider.dart';

class _BookingSummary {
  final String id;
  final String clientName;
  final String serviceName;
  final String professionalName;
  final DateTime startAt;
  final int price;
  final String status;

  const _BookingSummary({
    required this.id,
    required this.clientName,
    required this.serviceName,
    required this.professionalName,
    required this.startAt,
    required this.price,
    required this.status,
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
  List<_BookingSummary> _bookings = const [];
  List<_ServiceSummary> _services = const [];

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

      final responses = await Future.wait([
        bookingsFuture.timeout(const Duration(seconds: 15)),
        servicesFuture.timeout(const Duration(seconds: 15)),
      ]);

      final bookingsBody = _decodeBody(responses[0].body);
      final servicesBody = _decodeBody(responses[1].body);

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

      if (!mounted) return;

      setState(() {
        _businessName = businessName;
        _bookings = bookingsList
            .whereType<Map<String, dynamic>>()
            .map(_mapBooking)
            .toList();
        _services = servicesList
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

  _BookingSummary _mapBooking(Map<String, dynamic> map) {
    final startAtRaw = map['startAt'];
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
      clientName: (client?['name'] ?? 'Cliente').toString(),
      serviceName: (service?['name'] ?? map['serviceName'] ?? 'Servicio')
          .toString(),
      professionalName: (professional?['name'] ?? 'Profesional').toString(),
      startAt:
          DateTime.tryParse(startAtRaw?.toString() ?? '') ?? DateTime.now(),
      price: _readInt(map['price']) ?? _readInt(service?['price']) ?? 0,
      status: (map['status'] ?? 'pending').toString(),
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

  String _formatCurrency(int value) {
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

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDate(DateTime date) {
    final weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }

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

  int get _todaysIncome {
    final today = DateTime.now();
    return _bookings
        .where((booking) {
          return booking.startAt.year == today.year &&
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
    switch (status) {
      case 'pending':
        return (color: Colors.orange, label: 'Pendiente');
      case 'confirmed':
        return (color: Colors.green, label: 'Confirmada');
      case 'completed':
        return (color: Colors.blue, label: 'Completada');
      case 'cancelled':
        return (color: Colors.red, label: 'Cancelada');
      case 'no_show':
        return (color: Colors.grey, label: 'No asistió');
      default:
        return (color: Colors.grey, label: status);
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

    final nextBooking = _nextBookingDate;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Hola, $_businessName 👋',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        const Text('Resumen del negocio'),
        const SizedBox(height: 16),
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
                value: _formatCurrency(_todaysIncome),
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
        const Text(
          'Próximas reservas',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                subtitle: Text(
                  '${booking.serviceName} · ${booking.professionalName} · ${_formatDate(booking.startAt)} ${_formatTime(booking.startAt)}',
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
    final startAtRaw = map['startAt'];
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
      clientName: (client?['name'] ?? 'Cliente').toString(),
      serviceName: (service?['name'] ?? map['serviceName'] ?? 'Servicio')
          .toString(),
      professionalName: (professional?['name'] ?? 'Profesional').toString(),
      startAt:
          DateTime.tryParse(startAtRaw?.toString() ?? '') ?? DateTime.now(),
      price: _readInt(map['price']) ?? _readInt(service?['price']) ?? 0,
      status: (map['status'] ?? 'pending').toString(),
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

  String _formatDate(DateTime date) {
    final weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  ({Color color, String label}) _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
        return (color: Colors.orange, label: 'Pendiente');
      case 'confirmed':
        return (color: Colors.green, label: 'Confirmada');
      case 'completed':
        return (color: Colors.blue, label: 'Completada');
      case 'cancelled':
        return (color: Colors.red, label: 'Cancelada');
      case 'no_show':
        return (color: Colors.grey, label: 'No asistió');
      default:
        return (color: Colors.grey, label: status);
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

    final grouped = <String, List<_BookingSummary>>{};
    for (final booking in _bookings) {
      grouped.putIfAbsent(_formatDate(booking.startAt), () => []).add(booking);
    }

    final dates = grouped.keys.toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Agenda',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        const SizedBox(height: 16),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...list.map((booking) {
                      final statusInfo = _getStatusInfo(booking.status);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${booking.serviceName} · ${booking.professionalName}',
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${_formatTime(booking.startAt)} hrs'),
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
                                  '${booking.price} COP',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
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

  String _formatCurrency(int value) {
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
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Servicios del negocio',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
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
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatCurrency(service.price)),
                    const SizedBox(height: 4),
                    Text(
                      '${service.durationMin} min',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
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
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(title, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
