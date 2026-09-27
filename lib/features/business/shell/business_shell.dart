import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/providers/auth_provider.dart';

class BusinessShell extends StatelessWidget {
  final Widget child;

  const BusinessShell({super.key, required this.child});

  static const _tabs = [
    ('/business', Icons.dashboard_outlined, 'Panel'),
    ('/business/agenda', Icons.calendar_month_outlined, 'Agenda'),
    ('/business/services', Icons.content_cut, 'Servicios'),
    ('/business/profile', Icons.store_outlined, 'Mi negocio'),
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
