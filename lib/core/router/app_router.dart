import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/password_recovery_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/business/presentation/dashboard_screen.dart';
import '../../features/business/presentation/business_profile_screen.dart';
import '../../features/business/shell/business_shell.dart';
import '../../features/client/presentation/home_screen.dart';
import '../../features/client/presentation/my_bookings_screen.dart';
import '../../features/client/shell/client_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/client/presentation/reservations_screen.dart';
import '../../features/client/presentation/establishment_detail_screen.dart';
import '../../features/client/presentation/profile_screen.dart';
import '../../features/client/presentation/search_screen.dart';
import '../../features/client/presentation/favorites_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final auth = context.read<AuthProvider>();
      final path = state.uri.path;

      final isSplash = path == '/splash';
      final isLogin = path == '/login';
      final isPublicAuthRoute = isSplash || isLogin || path == '/register' || path == '/forgot-password' || path == '/reset-password';

      if (auth.status == AuthStatus.unauthenticated) {
        if (isPublicAuthRoute) return null;
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
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, state) => ResetPasswordScreen(
          email: state.uri.queryParameters['email'],
          token: state.uri.queryParameters['token'],
        ),
      ),

      // ---------- CLIENT ----------
      ShellRoute(
        builder: (context, state, child) => ClientShell(child: child),
        routes: [
          GoRoute(path: '/client', builder: (_, _) => const ClientHomeScreen()),
          GoRoute(
            path: '/client/establishment/:id',
            builder: (_, state) => EstablishmentDetailScreen(
              establishmentId: state.pathParameters['id']!,
              establishmentName: state.uri.queryParameters['name'],
              establishmentPhone: state.uri.queryParameters['phone'],
            ),
          ),
          GoRoute(path: '/client/search', builder: (_, _) => const SearchScreen()),
          GoRoute(path: '/client/favorites', builder: (_, _) => const FavoritesScreen()),
          GoRoute(
            path: '/client/reservas',
            builder: (_, state) {
              final q = state.uri.queryParameters;
              return ReservationsScreen(
                establishmentId: q['establishmentId'] ?? '1',
                establishmentName: q['establishmentName'] ?? 'Barbería 1',
                serviceId: q['serviceId'] ?? 's1',
                serviceName: q['serviceName'] ?? 'Corte Clásico',
                servicePrice: int.tryParse(q['price'] ?? '') ?? 25000,
                serviceDurationMin: int.tryParse(q['durationMin'] ?? '') ?? 30,
              );
            },
          ),
          GoRoute(
            path: '/client/my-bookings',
            builder: (_, _) => const MyBookingsScreen(),
          ),
          GoRoute(
            path: '/client/profile',
            builder: (_, _) => const ProfileScreen(),
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
            builder: (_, _) => const BusinessAgendaScreen(),
          ),
          GoRoute(
            path: '/business/services',
            builder: (_, _) => const BusinessServicesScreen(),
          ),
          GoRoute(
            path: '/business/profile',
            builder: (_, _) => const BusinessProfileScreen(),
          ),
        ],
      ),
    ],
  );
}
