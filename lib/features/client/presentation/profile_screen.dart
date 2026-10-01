import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ============================================================
// MODELO DE USUARIO (hardcodeado por ahora)
// ============================================================

class UserProfile {
  final String name;
  final String email;
  final String role; // 'client', 'owner', 'professional', 'admin'

  const UserProfile({
    required this.name,
    required this.email,
    required this.role,
  });
}

// ============================================================
// PANTALLA DE PERFIL DEL CLIENTE
// ============================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // --- Datos hardcodeados (después vienen del backend: GET /auth/me) ---
  final UserProfile _user = const UserProfile(
    name: 'Steven Santiago',
    email: 'demo@test.com',
    role: 'client',
  );

  // --- Contadores (hardcodeados, después vienen del backend) ---
  int _bookingsCount = 5;
  int _favoritesCount = 3;
  int _reviewsCount = 2;

  // ============================================================
  // Acciones
  // ============================================================
  void _logout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/login');
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ---------- Header con avatar ----------
          _buildHeader(theme),
          const SizedBox(height: 24),

          // ---------- Stats ----------
          _buildStats(theme),
          const SizedBox(height: 24),

          // ---------- Menú ----------
          _buildMenu(theme),
          const SizedBox(height: 16),

          // ---------- Cerrar sesión ----------
          _buildLogoutButton(theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGETS AUXILIARES
  // ============================================================

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: theme.colorScheme.primary,
          child: Text(
            _user.name.isNotEmpty ? _user.name.substring(0, 1).toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _user.name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _user.email,
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _getRoleLabel(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.secondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  String _getRoleLabel() {
    switch (_user.role) {
      case 'client':
        return 'CLIENTE';
      case 'owner':
        return 'DUEÑO DE NEGOCIO';
      case 'professional':
        return 'PROFESIONAL';
      case 'admin':
        return 'ADMIN';
      default:
        return _user.role.toUpperCase();
    }
  }

  Widget _buildStats(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatItem(theme, _bookingsCount.toString(), 'Reservas'),
          ),
          Container(
            height: 40,
            width: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          Expanded(
            child: _buildStatItem(theme, _favoritesCount.toString(), 'Favoritos'),
          ),
          Container(
            height: 40,
            width: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          Expanded(
            child: _buildStatItem(theme, _reviewsCount.toString(), 'Reseñas'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(ThemeData theme, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMenu(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _buildMenuItem(
            theme,
            icon: Icons.event_note_outlined,
            title: 'Mis reservas',
            subtitle: 'Ver historial y próximas',
            onTap: () => context.go('/client/my-bookings'),
          ),
          const Divider(height: 1, indent: 60),
          _buildMenuItem(
            theme,
            icon: Icons.favorite_outline,
            title: 'Mis favoritos',
            subtitle: 'Barberías guardadas',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Mis favoritos (próximamente)'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 60),
          _buildMenuItem(
            theme,
            icon: Icons.person_outline,
            title: 'Editar perfil',
            subtitle: 'Cambiar nombre, foto, teléfono',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Editar perfil (próximamente)'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 60),
          _buildMenuItem(
            theme,
            icon: Icons.settings_outlined,
            title: 'Configuración',
            subtitle: 'Notificaciones, privacidad',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Configuración (próximamente)'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 60),
          _buildMenuItem(
            theme,
            icon: Icons.help_outline,
            title: 'Ayuda',
            subtitle: 'Preguntas frecuentes, soporte',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ayuda (próximamente)'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: theme.colorScheme.primary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }

  Widget _buildLogoutButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text(
          'CERRAR SESIÓN',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}