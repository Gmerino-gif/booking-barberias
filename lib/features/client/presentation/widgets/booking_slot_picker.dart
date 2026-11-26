import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/network/api_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';

/// Selector de nuevo día y hora para una cita ya creada.
///
/// Reutiliza el mismo endpoint público de disponibilidad
/// (`GET /bookings/availability`) y el mismo patrón visual que
/// `ReservationsScreen` (tarjeta de fecha + chips de horas), para que
/// reprogramar se sienta igual que reservar.
///
/// Devuelve el instante local elegido, o `null` si el usuario cierra sin
/// confirmar.
Future<DateTime?> showBookingSlotPicker(
  BuildContext context, {
  required String establishmentId,
  required String professionalId,
  required String serviceId,
  String? currentScheduleLabel,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _BookingSlotPickerSheet(
      establishmentId: establishmentId,
      professionalId: professionalId,
      serviceId: serviceId,
      currentScheduleLabel: currentScheduleLabel,
    ),
  );
}

class _BookingSlotPickerSheet extends StatefulWidget {
  final String establishmentId;
  final String professionalId;
  final String serviceId;
  final String? currentScheduleLabel;

  const _BookingSlotPickerSheet({
    required this.establishmentId,
    required this.professionalId,
    required this.serviceId,
    this.currentScheduleLabel,
  });

  @override
  State<_BookingSlotPickerSheet> createState() =>
      _BookingSlotPickerSheetState();
}

class _BookingSlotPickerSheetState extends State<_BookingSlotPickerSheet> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  final Map<String, DateTime> _slotStartAt = {};
  List<String> _hours = const [];
  String? _selectedHour;
  bool _isLoading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    final requestId = ++_requestId;
    final selectedDate = _selectedDate;
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedHour = null;
      _hours = const [];
      _slotStartAt.clear();
    });

    try {
      final date =
          '${selectedDate.year.toString().padLeft(4, '0')}-'
          '${selectedDate.month.toString().padLeft(2, '0')}-'
          '${selectedDate.day.toString().padLeft(2, '0')}';
      final uri = Uri.parse('${ApiConfig.baseUrl}/bookings/availability')
          .replace(
            queryParameters: {
              'establishmentId': widget.establishmentId,
              'professionalId': widget.professionalId,
              'serviceId': widget.serviceId,
              'date': date,
              'utcOffsetMinutes': selectedDate.timeZoneOffset.inMinutes
                  .toString(),
            },
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('No se pudieron cargar los horarios disponibles');
      }
      final decoded = jsonDecode(response.body);
      final rawSlots = decoded is Map<String, dynamic> && decoded['slots'] is List
          ? decoded['slots'] as List
          : const <dynamic>[];
      final slots = <String, DateTime>{};
      for (final raw in rawSlots.whereType<String>()) {
        final local = AppFormatters.parseApiDateTime(raw);
        if (local == null) continue;
        slots[AppFormatters.hourLabel(local)] = local;
      }
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _slotStartAt.addAll(slots);
        _hours = slots.keys.toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'Selecciona el nuevo día',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadAvailability();
  }

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Hoy';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day) {
      return 'Mañana';
    }
    return AppFormatters.date(date, includeYear: false);
  }

  void _confirm() {
    final startAt = _slotStartAt[_selectedHour];
    if (startAt == null) return;
    Navigator.of(context).pop(startAt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canConfirm = _selectedHour != null;
    final currentSchedule = widget.currentScheduleLabel;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reprogramar cita',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppTypography.bold,
                ),
              ),
              if (currentSchedule != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Ahora: $currentSchedule',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _buildDateCard(theme),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildHours(theme),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canConfirm ? _confirm : null,
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                  child: const Text('CONFIRMAR NUEVO HORARIO'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateCard(ThemeData theme) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.md),
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
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              ),
              child: Icon(
                Icons.calendar_month,
                color: theme.colorScheme.onPrimary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.md - 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nuevo día',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: AppTypography.medium,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dayLabel(_selectedDate),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: AppTypography.bold,
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

  Widget _buildHours(ThemeData theme) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return TextButton(
        onPressed: _loadAvailability,
        child: Text('$_error · Reintentar'),
      );
    }
    if (_hours.isEmpty) {
      return Text(
        'No hay horarios disponibles para este día.',
        style: theme.textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _hours.map((hour) {
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
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              border: selected
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : null,
            ),
            child: Text(
              hour,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: AppTypography.semiBold,
                color: selected
                    ? theme.colorScheme.onSecondary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
