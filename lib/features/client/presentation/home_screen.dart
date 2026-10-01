import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/nearby_map.dart';

class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key});

  // --- Barberías hardcodeadas (después vienen del backend) ---
  // Coordenadas aproximadas de Barranquilla
  static const List<NearbyBarber> _nearbyBarbers = [
    NearbyBarber(
      id: '1',
      name: 'Barbería El Rey',
      lat: 10.9878,
      lng: -74.7889,
      rating: 4.8,
    ),
    NearbyBarber(
      id: '2',
      name: 'Barber Shop',
      lat: 10.9950,
      lng: -74.7950,
      rating: 4.5,
    ),
    NearbyBarber(
      id: '3',
      name: 'The Fade Room',
      lat: 10.9820,
      lng: -74.7820,
      rating: 4.9,
    ),
    NearbyBarber(
      id: '4',
      name: 'Barbería Clásica',
      lat: 10.9920,
      lng: -74.7780,
      rating: 4.3,
    ),
    NearbyBarber(
      id: '5',
      name: 'Estilo Urbano',
      lat: 10.9780,
      lng: -74.7960,
      rating: 4.6,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------- Ubicación ----------
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Barberías cerca de ti'),
            subtitle: const Text('Barranquilla, Atlántico'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: filtrar por cercanía
            },
          ),
        ),
        const SizedBox(height: 16),

        // ---------- MAPA ----------
        const Text(
          'Cerca de ti',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        NearbyMap(
          barbers: _nearbyBarbers,
          userLat: 10.9878,
          userLng: -74.7889,
          height: 220,
          onBarberTap: (barber) {
            context.go('/client/establishment/${barber.id}');
          },
        ),
        const SizedBox(height: 24),

        // ---------- Destacados ----------
        const Text(
          'Destacados',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        ...List.generate(
          5,
          (i) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.store)),
              title: Text('Barbería ${i + 1}'),
              subtitle: const Text('Corte + Barba · \$25.000'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.go('/client/establishment/${i + 1}');
              },
            ),
          ),
        ),
      ],
    );
  }
}