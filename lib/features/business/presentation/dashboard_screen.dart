import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';

class BusinessDashboardScreen extends StatelessWidget {
  const BusinessDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().userName ?? 'Negocio';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Hola, $user 👋',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Resumen de hoy'),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(
              child: _KpiCard(
                title: 'Reservas hoy',
                value: '8',
                icon: Icons.event_available,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: 'Ingresos',
                value: '\$210k',
                icon: Icons.attach_money,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(
              child: _KpiCard(
                title: 'Ocupación',
                value: '75%',
                icon: Icons.pie_chart_outline,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _KpiCard(
                title: 'Próxima cita',
                value: '3:30pm',
                icon: Icons.schedule,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Próximas reservas',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        ...List.generate(
          4,
          (i) => Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text('Cliente ${i + 1}'),
              subtitle: const Text('Corte + Barba · 4:00pm'),
              trailing: Chip(
                label: const Text('Confirmada'),
                backgroundColor: Colors.green.withValues(alpha: 0.15),
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
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}