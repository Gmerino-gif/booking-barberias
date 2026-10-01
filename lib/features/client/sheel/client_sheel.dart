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
    final i = _tabs.indexWhere((t) => location.startsWith(t.$1));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFromLocation(location);

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabs[index].$3),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.$2),
                  label: t.$3,
                ))
            .toList(),
      ),
    );
  }
}