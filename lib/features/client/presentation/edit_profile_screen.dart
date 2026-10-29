import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/modelos/user_role.dart';
import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

/// Pantalla completa para editar los datos personales del usuario.
///
/// Permite actualizar el nombre y el teléfono contra `PATCH /auth/me` y
/// refleja la respuesta del servidor en [AuthProvider] para que el resto de la
/// app vea los cambios.
///
/// El correo electrónico se muestra como dato de solo lectura: es el
/// identificador de acceso de la cuenta y el backend rechaza cualquier intento
/// de modificarlo.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;

  bool _isSaving = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _nameCtrl = TextEditingController(text: auth.userName ?? '');
    _phoneCtrl = TextEditingController(text: auth.userPhone ?? '');
    _emailCtrl = TextEditingController(text: auth.userEmail ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) return 'El nombre debe tener al menos 2 caracteres';
    if (name.length > 80) return 'El nombre es demasiado largo';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\+?[0-9\s().-]+$').hasMatch(phone) ||
        digits.length < 7 ||
        digits.length > 15 ||
        phone.length > 20) {
      return 'Ingresa un número válido (7 a 15 dígitos)';
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final token = auth.accessToken;
    if (token == null) {
      _goBack();
      return;
    }

    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    // El correo es el identificador de acceso y no se envía nunca al servidor:
    // solo se pueden modificar el nombre y el celular.
    final patch = <String, dynamic>{};
    if (name != (auth.userName ?? '')) patch['name'] = name;
    if (phone != (auth.userPhone ?? '')) patch['phone'] = phone;

    if (patch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No has cambiado ningún dato')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final response = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/auth/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: jsonEncode(patch),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      final decoded = _decode(response.body);
      if (response.statusCode == 200) {
        final user = decoded is Map<String, dynamic> ? decoded['user'] : null;
        if (user is Map<String, dynamic>) {
          auth.applyUserPayload(user);
        } else {
          auth.updateProfile(name: name, phone: phone);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado correctamente')),
        );
        _goBack();
        return;
      }

      final message = decoded is Map<String, dynamic>
          ? decoded['message'] as String?
          : null;
      setState(() {
        _serverError = message ?? 'No se pudo actualizar el perfil';
      });
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _serverError = 'El servidor tardó demasiado en responder';
        });
      }
    } on http.ClientException {
      if (mounted) {
        setState(() {
          _serverError = 'No fue posible conectar con el servidor';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _serverError = 'Ocurrió un error al actualizar el perfil';
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  dynamic _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  void _goBack() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/client/profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final role = auth.role ?? UserRole.client;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
          onPressed: _goBack,
        ),
        title: const Text('Editar perfil y ajustes'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    (auth.userName?.trim().isNotEmpty ?? false)
                        ? auth.userName!.trim().substring(0, 1).toUpperCase()
                        : '?',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  _roleLabel(role),
                  style: theme.textTheme.labelSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Datos personales',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Actualiza tu nombre y tu número de celular.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: _validateName,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Celular',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: _validatePhone,
                onFieldSubmitted: (_) {
                  if (!_isSaving) _save();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailCtrl,
                readOnly: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                  suffixIcon: Icon(Icons.lock_outline),
                  helperText: 'El correo no se puede modificar',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'El correo es tu identificador de acceso. Contacta a soporte si '
                'necesitas cambiarlo.',
                style: theme.textTheme.bodySmall,
              ),
              if (_serverError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _serverError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Guardando...' : 'Guardar cambios'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _isSaving ? null : _goBack,
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _roleLabel(UserRole role) {
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
}
