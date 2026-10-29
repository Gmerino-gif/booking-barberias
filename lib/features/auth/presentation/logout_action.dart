import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

/// Evita que un doble toque en el botón de salir abra dos diálogos o cierre la
/// sesión dos veces (el segundo `logout()` llegaría con el contexto ya
/// desmontado).
bool _logoutFlowInProgress = false;

/// Pregunta al usuario si realmente quiere cerrar sesión.
///
/// Devuelve `true` solo si confirma la acción (al tocar fuera del diálogo o
/// con "Cancelar" devuelve `false`).
Future<bool> showLogoutConfirmation(BuildContext context) async {
  final theme = Theme.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: const Text('Cerrar sesión'),
      content: const Text('¿Estás seguro que quieres cerrar sesión?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: const Text('Cerrar sesión'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

/// Flujo completo de cierre de sesión: confirma con el usuario y, solo si
/// acepta, limpia la sesión y navega al login.
///
/// Es el único punto de salida del flujo: cualquier botón de "Cerrar sesión"
/// debe llamar aquí para que la confirmación nunca se pueda omitir.
Future<void> confirmAndLogout(BuildContext context) async {
  if (_logoutFlowInProgress) return;
  _logoutFlowInProgress = true;

  // Se capturan antes del `await` para no usar el `context` después del
  // diálogo (la pantalla puede haberse desmontado).
  final auth = context.read<AuthProvider>();
  final router = GoRouter.of(context);

  try {
    if (!await showLogoutConfirmation(context)) return;

    await auth.logout();
    router.go('/login');
  } finally {
    _logoutFlowInProgress = false;
  }
}
