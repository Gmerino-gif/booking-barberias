import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';

class ClientShell extends StatelessWidget {
  final Widget child;

  const ClientShell({super.key, required this.child});

  static const _tabs = [
    ('/client', Icons.home_outlined, 'Inicio'),
    ('/client/search', Icons.search, 'Buscar'),
    ('/client/my-bookings', Icons.event_note_outlined, 'Mis reservas'),
    ('/client/profile', Icons.person_outline, 'Perfil'),
  ];

  int _indexFromLocation(String location) {
    if (location.startsWith('/client/my-bookings')) return 2;
    if (location.startsWith('/client/search')) return 1;
    // Favoritos se abre desde el perfil, así que mantiene esa pestaña activa.
    if (location.startsWith('/client/profile')) return 3;
    if (location.startsWith('/client/favorites')) return 3;
    if (location.startsWith('/client/establecimiento') ||
        location.startsWith('/client/establishment')) {
      return 1;
    }
    final i = _tabs.indexWhere((t) => location.startsWith(t.$1));
    return i < 0 ? 0 : i;
  }

  /// Las pantallas raíz (pestañas) usan el AppBar del shell; las sub-vistas
  /// (`/client/establishment/:id`, `/client/reservas`, ...) traen su propia
  /// cabecera con su botón de volver, así evitamos barras duplicadas.
  bool _isTabRoot(String location) =>
      _tabs.any((tab) => location == tab.$1);

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFromLocation(location);

    return Scaffold(
      appBar: _isTabRoot(location)
          ? AppBar(
              title: Text(_tabs[index].$3),
              actions: [
                IconButton(
                  tooltip: 'Cerrar sesión',
                  icon: const Icon(Icons.logout),
                  onPressed: () => _logout(context),
                ),
              ],
            )
          : null,
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: _tabs
            .map(
              (t) => NavigationDestination(icon: Icon(t.$2), label: t.$3),
            )
            .toList(),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().logout();
    if (!context.mounted) return;
    context.go('/login');
  }
}
