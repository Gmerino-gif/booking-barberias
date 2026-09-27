import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/business/presentation/dashboard_screen.dart';
import '../../features/business/shell/business_shell.dart';
import '../../features/client/presentation/home_screen.dart';
import '../../features/client/shell/client_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final path = state.uri.path;

      final isSplash = path == '/splash';
      final isLogin = path == '/login';

      if (auth.status == AuthStatus.unauthenticated) {
        if (isLogin || isSplash) return null;
        return '/login';
      }

      // Autenticado: sacarlo de splash/login
      if (isSplash || isLogin) {
        return auth.isBusiness ? '/business' : '/client';
      }

      // Evitar que un cliente entre a /business y viceversa
      if (auth.isBusiness && path.startsWith('/client')) {
        return '/business';
      }
      if (!auth.isBusiness && path.startsWith('/business')) {
        return '/client';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const LoginScreen(),
      ),

      // ---------- CLIENT ----------
      ShellRoute(
        builder: (context, state, child) => ClientShell(child: child),
        routes: [
          GoRoute(
            path: '/client',
            builder: (_, _) => const ClientHomeScreen(),
          ),
          GoRoute(
            path: '/client/search',
            builder: (_, _) =>
                const Center(child: Text('Búsqueda de establecimientos')),
          ),
          GoRoute(
            path: '/client/bookings',
            builder: (_, _) => const Center(child: Text('Mis reservas')),
          ),
          GoRoute(
            path: '/client/profile',
            builder: (_, _) => const Center(child: Text('Mi perfil')),
          ),
        ],
      ),

      // ---------- BUSINESS ----------
      ShellRoute(
        builder: (context, state, child) => BusinessShell(child: child),
        routes: [
          GoRoute(
            path: '/business',
            builder: (_, _) => const BusinessDashboardScreen(),
          ),
          GoRoute(
            path: '/business/agenda',
            builder: (_, _) => const Center(child: Text('Agenda')),
          ),
          GoRoute(
            path: '/business/services',
            builder: (_, _) => const Center(child: Text('CRUD de servicios')),
          ),
          GoRoute(
            path: '/business/profile',
            builder: (_, _) => const Center(child: Text('Perfil del negocio')),
          ),
        ],
      ),
    ],
  );
}