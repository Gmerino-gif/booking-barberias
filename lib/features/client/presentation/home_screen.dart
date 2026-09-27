import 'package:flutter/material.dart';

class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Barberías cerca de ti'),
            subtitle: const Text('Barranquilla, Atlántico'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ),
        const SizedBox(height: 12),
        const Text('Destacados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        ...List.generate(
          5,
          (i) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.store)),
              title: Text('Barbería ${i + 1}'),
              subtitle: const Text('Corte + Barba · \$25.000'),
              trailing: const Icon(Icons.star, color: Colors.amber, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}