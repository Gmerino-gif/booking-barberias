import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../auth/providers/auth_provider.dart';

class ProfessionalOption {
  final String id;
  final String name;
  final String specialty;

  const ProfessionalOption({
    required this.id,
    required this.name,
    required this.specialty,
  });
}

class ReservationsScreen extends StatefulWidget {
  final String establishmentId;
  final String establishmentName;
  final String serviceId;
  final String serviceName;
  final int servicePrice;
  final int serviceDurationMin;

  const ReservationsScreen({
    super.key,
    required this.establishmentId,
    required this.establishmentName,
    required this.serviceId,
    required this.serviceName,
    required this.servicePrice,
    required this.serviceDurationMin,
  });

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  List<ProfessionalOption> _professionals = const [];
  final List<String> _availableHours = const [
    '09:00 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '12:30 PM',
    '02:00 PM',
    '03:30 PM',
    '04:00 PM',
    '05:30 PM',
  ];

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedHour;
  int _selectedProfessionalIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProfessionals();
  }

  Future<void> _loadProfessionals() async {
    try {
      final auth = context.read<AuthProvider>();
      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/professionals/establishment/${widget.establishmentId}',
            ),
            headers: {
              if (auth.accessToken != null && auth.accessToken!.isNotEmpty)
                'Authorization': 'Bearer ${auth.accessToken}',
              'Content-Type': 'application/json; charset=UTF-8',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode != 200) {
        final decoded = jsonDecode(response.body);
        final message = decoded is Map<String, dynamic> ? decoded['message'] : null;
        throw Exception(message is String ? message : 'No se pudieron cargar los profesionales');
      }

      final decoded = jsonDecode(response.body);
      final rawList = decoded is Map<String, dynamic> ? decoded['professionals'] : null;
      final items = rawList is List ? rawList : const <dynamic>[];

      final professionals = items.whereType<Map<String, dynamic>>().map((item) {
        return ProfessionalOption(
          id: (item['_id'] ?? item['id'] ?? '').toString(),
          name: (item['name'] ?? 'Profesional').toString(),
          specialty: (item['specialty'] ?? 'Barbero').toString(),
        );
      }).toList();

      setState(() {
        _professionals = professionals;
        _isLoading = false;
        _error = professionals.isEmpty ? 'No hay profesionales disponibles para esta barberÃ­a' : null;
        if (_professionals.isNotEmpty) {
          _selectedProfessionalIndex = 0;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _confirmReservation() async {
    if (_selectedHour == null || _professionals.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesiÃ³n para reservar')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final startAt = _buildSelectedDateTime();
      final professional = _professionals[_selectedProfessionalIndex];
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/bookings'),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
              'Authorization': 'Bearer ${auth.accessToken}',
            },
            body: jsonEncode({
              'establishmentId': widget.establishmentId,
              'professionalId': professional.id,
              'serviceId': widget.serviceId,
              'startAt': startAt.toIso8601String(),
              'notes': '',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 && response.statusCode != 201) {
        final message = decoded is Map<String, dynamic> ? decoded['message'] : null;
        throw Exception(message is String ? message : 'No se pudo crear la reserva');
      }

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Â¡Reserva creada!'),
            ],
          ),
          content: Text(
            'Tu cita para ${widget.serviceName} quedÃ³ agendada con ${professional.name}.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/client/my-bookings');
              },
              child: const Text('Ver reservas'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  DateTime _buildSelectedDateTime() {
    if (_selectedHour == null || _selectedHour!.isEmpty) {
      return DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        10,
        0,
      );
    }

    final parts = _selectedHour!.split(RegExp(r'\s+'));
    final time = parts.first;
    final meridiem = parts.length > 1 ? parts[1].toUpperCase() : 'AM';
    final hourMinute = time.split(':');
    var hour = int.parse(hourMinute[0]);
    final minute = int.parse(hourMinute[1]);

    if (meridiem == 'PM' && hour != 12) {
      hour += 12;
    }
    if (meridiem == 'AM' && hour == 12) {
      hour = 0;
    }

    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      hour,
      minute,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Selecciona la fecha de tu cita',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedHour = null;
      });
    }
  }

  static const _weekdays = ['Lun', 'Mar', 'MiÃ©', 'Jue', 'Vie', 'SÃ¡b', 'Dom'];
  static const _months = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];
  static const _monthsShort = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  String _formatDayLabel(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Hoy';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day) {
      return 'MaÃ±ana';
    }
    return '${_weekdays[date.weekday - 1]}, ${date.day} de ${_months[date.month - 1]}';
  }

  String _formatFullDate(DateTime date) {
    return '${_weekdays[date.weekday - 1]} ${date.day} ${_monthsShort[date.month - 1]} ${date.year}';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedProfessional = _professionals.isNotEmpty && _selectedProfessionalIndex < _professionals.length
        ? _professionals[_selectedProfessionalIndex]
        : null;
    final canConfirm = _selectedHour != null && !_isSubmitting && _professionals.isNotEmpty;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.establishmentName)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.establishmentName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.establishmentName)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildServiceCard(theme),
            const SizedBox(height: 24),
            _buildStepTitle('1', 'Elige el dÃ­a'),
            const SizedBox(height: 12),
            _buildDateSelectorCard(theme),
            const SizedBox(height: 24),
            _buildStepTitle('2', 'Elige la hora'),
            const SizedBox(height: 12),
            _buildHoursSelector(theme),
            const SizedBox(height: 24),
            _buildStepTitle('3', 'Elige el profesional'),
            const SizedBox(height: 12),
            _buildProfessionalsSelector(theme),
            const SizedBox(height: 24),
            _buildSummaryCard(theme, selectedProfessional),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: canConfirm ? _confirmReservation : null,
              child: Text(
                _isSubmitting ? 'CONFIRMANDO...' : 'CONFIRMAR RESERVA',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStepTitle(String number, String title) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildServiceCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.store, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.establishmentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.serviceName} Â· ${_formatPrice(widget.servicePrice)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${widget.serviceDurationMin} min',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelectorCard(ThemeData theme) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.calendar_month,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fecha seleccionada',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDayLabel(_selectedDate),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHoursSelector(ThemeData theme) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _availableHours.map((hour) {
        final selected = hour == _selectedHour;
        return GestureDetector(
          onTap: () => setState(() => _selectedHour = hour),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : null,
            ),
            child: Text(
              hour,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.black : theme.colorScheme.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildProfessionalsSelector(ThemeData theme) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _professionals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final professional = _professionals[index];
          final selected = index == _selectedProfessionalIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedProfessionalIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: selected
                    ? Border.all(color: theme.colorScheme.secondary, width: 2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: selected
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.primary,
                    child: Text(
                      professional.name.isNotEmpty
                          ? professional.name.substring(0, 1).toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    professional.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : null,
                    ),
                  ),
                  Text(
                    professional.specialty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? Colors.white70 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme, ProfessionalOption? selectedProfessional) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de tu reserva',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow(Icons.calendar_today, _formatFullDate(_selectedDate)),
          const SizedBox(height: 8),
          _buildSummaryRow(Icons.access_time, _selectedHour ?? 'Sin hora seleccionada'),
          const SizedBox(height: 8),
          _buildSummaryRow(
            Icons.person_outline,
            selectedProfessional?.name ?? 'Sin profesional',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(Icons.timer_outlined, '${widget.serviceDurationMin} min'),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatPrice(widget.servicePrice),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }
}
