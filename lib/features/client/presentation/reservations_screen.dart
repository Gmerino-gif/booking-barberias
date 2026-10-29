import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/providers/auth_provider.dart';
import 'establishment_detail_screen.dart' show ServiceItem;

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
  List<ServiceItem> _services = const [];
  List<String> _availableHours = const [];
  final Map<String, DateTime> _slotStartAt = {};
  bool _isLoadingAvailability = false;
  String? _availabilityError;
  int _availabilityRequestId = 0;

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedHour;
  int _selectedProfessionalIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProfessionals();
    _loadServices();
  }

  Future<List<ServiceItem>> _fetchServices() async {
    final response = await http
        .get(
          Uri.parse(
            '${ApiConfig.baseUrl}/services?establishmentId=${widget.establishmentId}',
          ),
          headers: const {'Content-Type': 'application/json; charset=UTF-8'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('No se pudieron cargar los servicios');
    }
    final decoded = jsonDecode(response.body);
    final rawList = decoded is Map<String, dynamic>
        ? decoded['services']
        : null;
    final items = rawList is List ? rawList : const <dynamic>[];
    return items.whereType<Map<String, dynamic>>().map((item) {
      final rawCategory = item['category'] ?? 'General';
      return ServiceItem(
        id: (item['_id'] ?? item['id'] ?? '').toString(),
        name: (item['name'] ?? 'Servicio').toString(),
        description: (item['description'] ?? '').toString(),
        price: (item['price'] is num ? item['price'] : 0).toInt(),
        durationMin: (item['durationMin'] is num ? item['durationMin'] : 30)
            .toInt(),
        category: rawCategory.toString(),
      );
    }).toList();
  }

  Future<void> _loadServices() async {
    try {
      final services = await _fetchServices();
      if (!mounted) return;
      setState(() => _services = services);
    } catch (_) {
      // Cambiar de servicio es opcional: si falla seguimos con el seleccionado.
    }
  }

  /// Vuelve al detalle del establecimiento para elegir otro servicio.
  void _goBackToEstablishment() {
    context.go(
      '/client/establishment/${widget.establishmentId}'
      '?name=${Uri.encodeComponent(widget.establishmentName)}',
    );
  }

  /// Abre el selector de servicios para cambiar el servicio de la reserva.
  Future<void> _changeService() async {
    var services = _services;
    if (services.isEmpty) {
      try {
        services = await _fetchServices();
        if (!mounted) return;
        setState(() => _services = services);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
        return;
      }
    }
    if (!mounted) return;

    if (services.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta barbería aún no tiene servicios disponibles'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<ServiceItem>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Elige otro servicio',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: services.length,
                    itemBuilder: (_, index) {
                      final service = services[index];
                      final isCurrent = service.id == widget.serviceId;
                      return ListTile(
                        enabled: !isCurrent,
                        leading: Icon(
                          isCurrent
                              ? Icons.check_circle
                              : Icons.content_cut_outlined,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(service.name),
                        subtitle: Text(
                          '${service.durationMin} min · '
                          '${AppFormatters.currency(service.price)}',
                        ),
                        trailing: isCurrent
                            ? Text(
                                'Actual',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop(service),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    if (selected.id == widget.serviceId) return;

    // Reabrimos el flujo con el nuevo servicio, conservando el establecimiento.
    context.go(
      '/client/reservas'
      '?establishmentId=${widget.establishmentId}'
      '&establishmentName=${Uri.encodeComponent(widget.establishmentName)}'
      '&serviceId=${selected.id}'
      '&serviceName=${Uri.encodeComponent(selected.name)}'
      '&price=${selected.price}'
      '&durationMin=${selected.durationMin}',
    );
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
        final message = decoded is Map<String, dynamic>
            ? decoded['message']
            : null;
        throw Exception(
          message is String
              ? message
              : 'No se pudieron cargar los profesionales',
        );
      }

      final decoded = jsonDecode(response.body);
      final rawList = decoded is Map<String, dynamic>
          ? decoded['professionals']
          : null;
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
        _error = professionals.isEmpty
            ? 'No hay profesionales disponibles para esta barbería'
            : null;
        if (_professionals.isNotEmpty) {
          _selectedProfessionalIndex = 0;
        }
      });
      if (professionals.isNotEmpty) await _loadAvailability();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadAvailability() async {
    if (_professionals.isEmpty) return;
    final requestId = ++_availabilityRequestId;
    final selectedDate = _selectedDate;
    final professional = _professionals[_selectedProfessionalIndex];
    setState(() {
      _isLoadingAvailability = true;
      _availabilityError = null;
      _selectedHour = null;
      _availableHours = const [];
      _slotStartAt.clear();
    });

    try {
      final date =
          '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
      final uri = Uri.parse('${ApiConfig.baseUrl}/bookings/availability')
          .replace(
            queryParameters: {
              'establishmentId': widget.establishmentId,
              'professionalId': professional.id,
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
      final rawSlots =
          decoded is Map<String, dynamic> && decoded['slots'] is List
          ? decoded['slots'] as List
          : const <dynamic>[];
      final slots = <String, DateTime>{};
      for (final raw in rawSlots.whereType<String>()) {
        final local = AppFormatters.parseApiDateTime(raw);
        if (local == null) continue;
        slots[AppFormatters.hourLabel(local)] = local;
      }
      if (!mounted || requestId != _availabilityRequestId) return;
      setState(() {
        _slotStartAt.addAll(slots);
        _availableHours = slots.keys.toList();
        _isLoadingAvailability = false;
      });
    } catch (error) {
      if (!mounted || requestId != _availabilityRequestId) return;
      setState(() {
        _isLoadingAvailability = false;
        _availabilityError = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _confirmReservation() async {
    if (_selectedHour == null || _professionals.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión para reservar')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final startAt = _slotStartAt[_selectedHour];
      if (startAt == null) throw Exception('Selecciona un horario disponible');
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
              'startAt': startAt.toUtc().toIso8601String(),
              'utcOffsetMinutes': _selectedDate.timeZoneOffset.inMinutes,
              'notes': '',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200 && response.statusCode != 201) {
        final message = decoded is Map<String, dynamic>
            ? decoded['message']
            : null;
        throw Exception(
          message is String ? message : 'No se pudo crear la reserva',
        );
      }

      final shouldViewBookings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 28),
              SizedBox(width: 8),
              Text('¡Reserva creada!'),
            ],
          ),
          content: Text(
            'Tu cita para ${widget.serviceName} quedó agendada con ${professional.name}.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Ver reservas'),
            ),
          ],
        ),
      );
      if (shouldViewBookings == true && mounted) {
        context.go('/client/my-bookings');
      }
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
      await _loadAvailability();
    }
  }

  String _formatDayLabel(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
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

  String _formatFullDate(DateTime date) => AppFormatters.date(date);

  String _formatPrice(int value) => AppFormatters.currency(value);

  /// Cabecera común de la pantalla (volver + cambiar servicio).
  AppBar _buildAppBar({bool allowChangeService = true}) {
    return AppBar(
      leading: IconButton(
        tooltip: 'Volver',
        icon: const Icon(Icons.arrow_back),
        onPressed: _goBackToEstablishment,
      ),
      title: Text(widget.establishmentName, overflow: TextOverflow.ellipsis),
      actions: [
        if (allowChangeService)
          IconButton(
            tooltip: 'Cambiar servicio',
            icon: const Icon(Icons.swap_horiz),
            onPressed: _changeService,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedProfessional =
        _professionals.isNotEmpty &&
            _selectedProfessionalIndex < _professionals.length
        ? _professionals[_selectedProfessionalIndex]
        : null;
    final canConfirm =
        _selectedHour != null && !_isSubmitting && _professionals.isNotEmpty;

    if (_isLoading) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildServiceCard(theme),
            const SizedBox(height: 24),
            _buildStepTitle('1', 'Elige el día'),
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
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: AppTypography.bold,
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
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimary,
              fontWeight: AppTypography.bold,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: AppTypography.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildServiceCard(ThemeData theme) {
    final onPrimary = theme.colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store, color: onPrimary, size: 32),
              const SizedBox(width: AppSpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.establishmentName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onPrimary,
                        fontWeight: AppTypography.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${widget.serviceName} · '
                      '${_formatPrice(widget.servicePrice)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.lg + 4),
                ),
                child: Text(
                  '${widget.serviceDurationMin} min',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondary,
                    fontWeight: AppTypography.bold,
                  ),
                ),
              ),
            ],
          ),
          // Acceso directo para cambiar de servicio sin salir del flujo.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _changeService,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Cambiar servicio'),
              style: TextButton.styleFrom(
                foregroundColor: onPrimary,
                visualDensity: VisualDensity.compact,
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
                    'Fecha seleccionada',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: AppTypography.medium,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDayLabel(_selectedDate),
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

  Widget _buildHoursSelector(ThemeData theme) {
    if (_isLoadingAvailability) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_availabilityError != null) {
      return TextButton(
        onPressed: _loadAvailability,
        child: Text('$_availabilityError · Reintentar'),
      );
    }
    if (_availableHours.isEmpty) {
      return const Text(
        'No hay horarios disponibles para esta fecha y profesional.',
      );
    }
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
            onTap: () {
              setState(() => _selectedProfessionalIndex = index);
              _loadAvailability();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: AppTypography.bold,
                        color: selected
                            ? theme.colorScheme.onSecondary
                            : theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    professional.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: AppTypography.bold,
                      color: selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    professional.specialty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
                          : theme.colorScheme.onSurfaceVariant,
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

  Widget _buildSummaryCard(
    ThemeData theme,
    ProfessionalOption? selectedProfessional,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de tu reserva',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: AppTypography.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow(
            Icons.calendar_today,
            _formatFullDate(_selectedDate),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildSummaryRow(
            Icons.access_time,
            _selectedHour ?? 'Sin hora seleccionada',
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildSummaryRow(
            Icons.person_outline,
            selectedProfessional?.name ?? 'Sin profesional',
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildSummaryRow(
            Icons.timer_outlined,
            '${widget.serviceDurationMin} min',
          ),
          const Divider(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppTypography.bold,
                ),
              ),
              Text(
                _formatPrice(widget.servicePrice),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: AppTypography.bold,
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
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}
