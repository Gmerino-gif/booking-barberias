import 'package:flutter/material.dart';

// ============================================================
// MODELOS SIMPLES (hardcodeados por ahora, después vienen de Node.js)
// ============================================================

class BarberService {
  final String name;
  final int price;
  final int durationMin;
  const BarberService({
    required this.name,
    required this.price,
    required this.durationMin,
  });
}

class Professional {
  final String name;
  final String specialty;
  final String? avatarUrl;
  const Professional({
    required this.name,
    required this.specialty,
    this.avatarUrl,
  });
}

// ============================================================
// PANTALLA DE RESERVAS
// ============================================================

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
  // --- Datos que vienen del detalle de la barbería ---
  BarberService get _service => BarberService(
        name: widget.serviceName,
        price: widget.servicePrice,
        durationMin: widget.serviceDurationMin,
      );

  final List<Professional> _professionals = const [
    Professional(name: 'Cualquiera', specialty: 'Primer disponible'),
    Professional(name: 'Carlos M.', specialty: 'Barbero senior'),
    Professional(name: 'Andrés R.', specialty: 'Especialista en barba'),
    Professional(name: 'Luis P.', specialty: 'Fade & diseño'),
  ];

  // Horas disponibles (hardcodeado, después viene del backend)
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

  // --- Estado de la selección ---
  DateTime _selectedDate = DateTime.now();
  String? _selectedHour;
  int _selectedProfessionalIndex = 0;

  // --- Utilidades ---
  static const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _months = [
    'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
    'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
  ];
  static const _monthsShort = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  String _formatDayLabel(DateTime d) {
    if (_isToday(d)) return 'Hoy';
    if (_isTomorrow(d)) return 'Mañana';
    return '${_weekdays[d.weekday - 1]}, ${d.day} de ${_months[d.month - 1]}';
  }

  String _formatFullDate(DateTime d) {
    return '${_weekdays[d.weekday - 1]} ${d.day} ${_monthsShort[d.month - 1]} ${d.year}';
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.day == now.day && d.month == now.month && d.year == now.year;
  }

  bool _isTomorrow(DateTime d) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return d.day == tomorrow.day &&
        d.month == tomorrow.month &&
        d.year == tomorrow.year;
  }

  String _formatPrice(int value) {
    final str = value.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return '\$${buf.toString()}';
  }

  // ============================================================
  // CALENDARIO PROFESIONAL
  // ============================================================
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final lastDate = now.add(const Duration(days: 90));

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: now,
      lastDate: lastDate,
      helpText: 'Selecciona la fecha de tu cita',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedHour = null;
      });
    }
  }

  // --- Confirmar ---
  void _confirmReservation() {
    if (_selectedHour == null) return;

    final day = _selectedDate;
    final prof = _professionals[_selectedProfessionalIndex];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('¡Reserva confirmada!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryRow(Icons.content_cut, _service.name),
            const SizedBox(height: 8),
            _buildSummaryRow(Icons.person_outline, prof.name),
            const SizedBox(height: 8),
            _buildSummaryRow(Icons.calendar_today,
                '${_formatFullDate(day)} · $_selectedHour'),
            const SizedBox(height: 8),
            _buildSummaryRow(Icons.attach_money,
                _formatPrice(_service.price)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _selectedHour = null;
                _selectedDate = DateTime.now();
                _selectedProfessionalIndex = 0;
              });
            },
            child: const Text('OK'),
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

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canConfirm = _selectedHour != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---------- Info del servicio ----------
          _buildServiceCard(theme),
          const SizedBox(height: 24),

          // ---------- PASO 1: Día (calendario) ----------
          _buildStepTitle('1', 'Elige el día'),
          const SizedBox(height: 12),
          _buildDateSelectorCard(theme),
          const SizedBox(height: 24),

          // ---------- PASO 2: Hora ----------
          _buildStepTitle('2', 'Elige la hora'),
          const SizedBox(height: 12),
          _buildHoursSelector(theme),
          const SizedBox(height: 24),

          // ---------- PASO 3: Profesional ----------
          _buildStepTitle('3', 'Elige el profesional'),
          const SizedBox(height: 12),
          _buildProfessionalsSelector(theme),
          const SizedBox(height: 24),

          // ---------- Resumen ----------
          _buildSummaryCard(theme),
          const SizedBox(height: 16),

          // ---------- Botón confirmar ----------
          FilledButton(
            onPressed: canConfirm ? _confirmReservation : null,
            child: Text(
              canConfirm ? 'CONFIRMAR RESERVA' : 'ELIGE UNA HORA',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------- Widgets auxiliares ----------

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
                  '${_service.name} · ${_formatPrice(_service.price)}',
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
              '${_service.durationMin} min',
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

  // ============================================================
  // SELECTOR DE FECHA (tarjeta que abre el calendario)
  // ============================================================
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
                color: selected
                    ? Colors.black
                    : theme.colorScheme.onSurface,
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
        itemBuilder: (context, i) {
          final prof = _professionals[i];
          final selected = i == _selectedProfessionalIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedProfessionalIndex = i),
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
                      prof.name.substring(0, 1),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    prof.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : null,
                    ),
                  ),
                  Text(
                    prof.specialty,
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

  Widget _buildSummaryCard(ThemeData theme) {
    final day = _selectedDate;
    final prof = _professionals[_selectedProfessionalIndex];

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
          _buildSummaryRow(
            Icons.calendar_today,
            _formatFullDate(day),
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            Icons.access_time,
            _selectedHour ?? 'Sin hora seleccionada',
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            Icons.person_outline,
            prof.name,
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            Icons.timer_outlined,
            '${_service.durationMin} min',
          ),
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
                _formatPrice(_service.price),
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
}