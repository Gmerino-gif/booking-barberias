import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../../core/modelos/user_role.dart';
import '../../auth/providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _bookingsCount = 0;
  int _favoritesCount = 0;
  int _reviewsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) return;
    try {
      final headers = {'Authorization': 'Bearer $token'};
      final responses = await Future.wait([
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/bookings/my'),
          headers: headers,
        ),
        http.get(Uri.parse('${ApiConfig.baseUrl}/favorites'), headers: headers),
        http.get(
          Uri.parse('${ApiConfig.baseUrl}/reviews/my'),
          headers: headers,
        ),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted || responses.any((response) => response.statusCode != 200)) {
        return;
      }
      List<dynamic> listAt(int index, String key) {
        final decoded = jsonDecode(responses[index].body);
        return decoded is Map<String, dynamic> && decoded[key] is List
            ? decoded[key] as List
            : const [];
      }

      setState(() {
        _bookingsCount = listAt(0, 'bookings').length;
        _favoritesCount = listAt(1, 'favorites').length;
        _reviewsCount = listAt(2, 'reviews').length;
      });
    } catch (_) {
      // Las estadísticas son secundarias; el perfil sigue disponible sin conexión.
    }
  }

  Future<void> _editProfile() async {
    final auth = context.read<AuthProvider>();
    final nameController = TextEditingController(text: auth.userName ?? '');
    final phoneController = TextEditingController(text: auth.userPhone ?? '');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      nameController.dispose();
      phoneController.dispose();
      return;
    }
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();
    if (name.length < 2 || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un nombre y teléfono válidos')),
      );
      return;
    }
    final token = auth.accessToken;
    if (token == null) return;
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/auth/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': name, 'phone': phone}),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        auth.updateProfile(name: name, phone: phone);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
      } else {
        final decoded = jsonDecode(response.body);
        final message =
            decoded is Map<String, dynamic> && decoded['message'] is String
            ? decoded['message'] as String
            : 'No se pudo actualizar el perfil';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar para actualizar el perfil'),
          ),
        );
      }
    }
  }

  void _showSettings() {
    final auth = context.read<AuthProvider>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Configuración de cuenta'),
        content: Text(
          'Correo de acceso: ${auth.userEmail ?? 'No disponible'}\n\nEl correo es el identificador de inicio de sesión. Puedes actualizar tu nombre y teléfono desde Editar perfil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ayuda'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '¿Cómo reservo una cita?\nBusca una barbería, elige un servicio y selecciona una hora disponible.',
              ),
              SizedBox(height: 12),
              Text(
                '¿Cómo cancelo una cita?\nAbre Mis reservas y cancela una cita futura pendiente o confirmada.',
              ),
              SizedBox(height: 12),
              Text(
                '¿Dónde encuentro mis barberías guardadas?\nEn Perfil, abre Mis favoritos.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro que quieres cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await auth.logout();
              if (mounted) context.go('/login');
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final name = auth.userName?.trim().isNotEmpty == true
        ? auth.userName!
        : 'Usuario';
    final email = auth.userEmail?.trim().isNotEmpty == true
        ? auth.userEmail!
        : 'usuario@booking-barberias.com';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildHeader(theme, name: name, email: email, phone: auth.userPhone),
          const SizedBox(height: 24),
          _buildStats(theme),
          const SizedBox(height: 24),
          _buildMenu(theme),
          const SizedBox(height: 16),
          _buildLogoutButton(theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme, {
    required String name,
    required String email,
    String? phone,
  }) {
    final role = context.read<AuthProvider>().role ?? UserRole.client;
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: theme.colorScheme.primary,
          child: Text(
            name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          style: TextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (phone != null && phone.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            phone,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _getRoleLabel(role),
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

  String _getRoleLabel(UserRole role) {
    switch (role) {
      case UserRole.client:
        return 'CLIENTE';
      case UserRole.owner:
        return 'DUEÑO DE NEGOCIO';
      case UserRole.professional:
        return 'PROFESIONAL';
      case UserRole.admin:
        return 'ADMIN';
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
            child: _buildStatItem(
              theme,
              _favoritesCount.toString(),
              'Favoritos',
            ),
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
            onTap: () => context.go('/client/favorites'),
          ),
          const Divider(height: 1, indent: 60),
          _buildMenuItem(
            theme,
            icon: Icons.person_outline,
            title: 'Editar perfil',
            subtitle: 'Cambiar nombre, foto, teléfono',
            onTap: _editProfile,
          ),
          const Divider(height: 1, indent: 60),
          _buildMenuItem(
            theme,
            icon: Icons.settings_outlined,
            title: 'Configuración',
            subtitle: 'Cuenta y datos de acceso',
            onTap: _showSettings,
          ),
          const Divider(height: 1, indent: 60),
          _buildMenuItem(
            theme,
            icon: Icons.help_outline,
            title: 'Ayuda',
            subtitle: 'Preguntas frecuentes, soporte',
            onTap: _showHelp,
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
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
