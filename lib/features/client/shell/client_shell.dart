import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../auth/presentation/logout_action.dart';

class ClientShell extends StatefulWidget {
  final Widget child;

  const ClientShell({super.key, required this.child});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  /// Destino por defecto cuando no hay un "volver" claro.
  static const _homeLocation = '/client';

  static const _tabs = [
    ('/client', Icons.home_outlined, 'Inicio'),
    ('/client/search', Icons.search, 'Buscar'),
    ('/client/my-bookings', Icons.event_note_outlined, 'Mis reservas'),
    ('/client/profile', Icons.person_outline, 'Perfil'),
  ];

  /// Pestañas que además muestran el botón de "volver" en el AppBar.
  static const _tabsWithBack = {'/client/my-bookings'};

  /// Pantallas de un flujo puntual a las que no tiene sentido regresar
  /// (p. ej. el formulario de reserva de una cita que ya se creó).
  static const _transientPrefixes = ['/client/reservas'];

  /// Como la navegación usa `context.go` (sin pila de `Navigator`), el shell
  /// recuerda la ubicación anterior para que las pestañas puedan ofrecer un
  /// "volver" real sin apilar rutas.
  Uri? _currentLocation;
  Uri? _previousLocation;

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
  bool _isTabRoot(String location) => _tabs.any((tab) => location == tab.$1);

  /// Registra la ubicación actual para poder volver a la anterior.
  void _rememberLocation(Uri location) {
    if (_currentLocation == location) return;
    _previousLocation = _currentLocation;
    _currentLocation = location;
  }

  /// A dónde debe llevar el botón de "volver" desde [location].
  String _backTarget(String location) {
    final previous = _previousLocation;
    if (previous == null) return _homeLocation;

    final previousPath = previous.path;
    if (previousPath == location) return _homeLocation;
    if (!previousPath.startsWith('/client')) return _homeLocation;
    if (_transientPrefixes.any(previousPath.startsWith)) return _homeLocation;

    // Se conservan los query params (`?name=...`) de la pantalla anterior.
    return previous.toString();
  }

  void _goBack(String location) {
    // Si algo quedó apilado en el Navigator, primero se cierra esa ruta.
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(_backTarget(location));
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri;
    _rememberLocation(location);

    final path = location.path;
    final index = _indexFromLocation(path);
    final isTabRoot = _isTabRoot(path);
    final showBack = isTabRoot && _tabsWithBack.contains(path);

    return Scaffold(
      appBar: isTabRoot
          ? AppBar(
              leading: showBack
                  ? IconButton(
                      tooltip: 'Volver',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => _goBack(path),
                    )
                  : null,
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
      body: widget.child,
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

  Future<void> _logout(BuildContext context) => confirmAndLogout(context);
}
