import 'package:flutter/material.dart';

// ============================================================
// MODELO DE RESERVA (hardcodeado por ahora)
// ============================================================

class BookingModel {
  final String id;
  final String establishmentName;
  final String serviceName;
  final String professionalName;
  final DateTime startAt;
  final int durationMin;
  final int price;
  final String status; // pending, confirmed, completed, cancelled, no_show
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

// ============================================================
// PANTALLA MIS RESERVAS
// ============================================================

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // --- Datos hardcodeados (después vienen del backend) ---
  final List<BookingModel> _bookings = [
    BookingModel(
      id: 'b1',
      establishmentName: 'Barbería El Rey',
      serviceName: 'Corte + Barba',
      professionalName: 'Carlos M.',
      startAt: DateTime.now().add(const Duration(days: 2, hours: 3)),
      durationMin: 45,
      price: 35000,
      status: 'confirmed',
      notes: 'Prefiero máquina del 2',
    ),
    BookingModel(
      id: 'b2',
      establishmentName: 'Barbería El Rey',
      serviceName: 'Corte Clásico',
      professionalName: 'Andrés R.',
      startAt: DateTime.now().add(const Duration(days: 5, hours: 1)),
      durationMin: 30,
      price: 25000,
      status: 'pending',
    ),
    BookingModel(
      id: 'b3',
      establishmentName: 'Barbería El Rey',
      serviceName: 'Fade Premium',
      professionalName: 'Luis P.',
      startAt: DateTime.now().subtract(const Duration(days: 3)),
      durationMin: 40,
      price: 30000,
      status: 'completed',
      notes: 'Excelente servicio',
    ),
    BookingModel(
      id: 'b4',
      establishmentName: 'Barbería El Rey',
      serviceName: 'Perfilado de Barba',
      professionalName: 'Carlos M.',
      startAt: DateTime.now().subtract(const Duration(days: 10)),
      durationMin: 20,
      price: 15000,
      status: 'cancelled',
    ),
    BookingModel(
      id: 'b5',
      establishmentName: 'Barbería El Rey',
      serviceName: 'Corte Clásico',
      professionalName: 'Andrés R.',
      startAt: DateTime.now().subtract(const Duration(days: 20)),
      durationMin: 30,
      price: 25000,
      status: 'no_show',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- Filtros ---
  List<BookingModel> get _upcoming {
    final now = DateTime.now();
    return _bookings.where((b) {
      return b.startAt.isAfter(now) &&
          (b.status == 'pending' || b.status == 'confirmed');
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  List<BookingModel> get _history {
    final now = DateTime.now();
    return _bookings.where((b) {
      return b.startAt.isBefore(now) ||
          b.status == 'completed' ||
          b.status == 'cancelled' ||
          b.status == 'no_show';
    }).toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
  }

  // ============================================================
  // Utilidades
  // ============================================================
  static const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _months = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];

  String _formatDate(DateTime d) {
    return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  String _formatTime(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
  // Estado (colores y texto)
  // ============================================================
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

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Tabs
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

        // Contenido
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
      itemBuilder: (context, i) => _buildBookingCard(list[i], isUpcoming),
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
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          // ---------- Header con estado ----------
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
                  '#${booking.id}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // ---------- Contenido ----------
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Servicio
                Text(
                  booking.serviceName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),

                // Barbería
                Row(
                  children: [
                    Icon(Icons.store,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      booking.establishmentName,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Fecha y hora
                _buildInfoRow(
                  theme,
                  Icons.calendar_today,
                  '${_formatDate(booking.startAt)} · ${_formatTime(booking.startAt)}',
                ),
                const SizedBox(height: 6),

                // Profesional
                _buildInfoRow(
                  theme,
                  Icons.person_outline,
                  booking.professionalName,
                ),
                const SizedBox(height: 6),

                // Duración
                _buildInfoRow(
                  theme,
                  Icons.timer_outlined,
                  '${booking.durationMin} min',
                ),

                // Notas (si hay)
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
                        Icon(Icons.notes,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant),
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

                // Precio + botones
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
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cancelar (próximamente)'),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 0),
                              minimumSize: const Size(0, 32),
                            ),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ver detalle (próximamente)'),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 0),
                              minimumSize: const Size(0, 32),
                            ),
                            child: const Text(
                              'Ver detalle',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
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