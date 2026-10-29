import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/image_urls.dart';
import '../../../core/widgets/image_edit_field.dart';
import '../../auth/providers/auth_provider.dart';

class _ProfessionalItem {
  final String id;
  final String name;
  final String specialty;
  final Set<String> serviceIds;
  final String? photo;
  final double rating;
  final int reviewCount;

  const _ProfessionalItem({
    required this.id,
    required this.name,
    required this.specialty,
    required this.serviceIds,
    this.photo,
    this.rating = 0,
    this.reviewCount = 0,
  });
}

class _BusinessServiceOption {
  final String id;
  final String name;

  const _BusinessServiceOption(this.id, this.name);
}

class BusinessProfessionalsScreen extends StatefulWidget {
  const BusinessProfessionalsScreen({super.key});

  @override
  State<BusinessProfessionalsScreen> createState() =>
      _BusinessProfessionalsScreenState();
}

class _BusinessProfessionalsScreenState
    extends State<BusinessProfessionalsScreen> {
  bool _loading = true;
  String? _error;
  String? _establishmentId;
  List<_ProfessionalItem> _professionals = const [];
  List<_BusinessServiceOption> _services = const [];

  Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _message(http.Response response, String fallback) {
    final decoded = _decode(response.body);
    return decoded?['message'] is String
        ? decoded!['message'] as String
        : fallback;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = context.read<AuthProvider>().accessToken;
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/professionals/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      final decoded = _decode(response.body);
      if (response.statusCode != 200 || decoded == null) {
        throw Exception(
          _message(response, 'No se pudieron cargar los profesionales'),
        );
      }
      final items = decoded['professionals'] is List
          ? decoded['professionals'] as List
          : const <dynamic>[];
      final establishmentId = decoded['establishmentId']?.toString() ?? '';
      final servicesResponse = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/services?establishmentId=$establishmentId',
            ),
          )
          .timeout(const Duration(seconds: 15));
      final servicesBody = _decode(servicesResponse.body);
      final serviceItems = servicesBody?['services'] is List
          ? servicesBody!['services'] as List
          : const <dynamic>[];
      if (!mounted) return;
      setState(() {
        _establishmentId = establishmentId;
        _services = serviceItems
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => _BusinessServiceOption(
                (item['_id'] ?? item['id'] ?? '').toString(),
                (item['name'] ?? 'Servicio').toString(),
              ),
            )
            .toList();
        _professionals = items
            .whereType<Map<String, dynamic>>()
            .map(
              (item) => _ProfessionalItem(
                id: (item['_id'] ?? item['id'] ?? '').toString(),
                name: (item['name'] ?? '').toString(),
                specialty: (item['specialty'] ?? '').toString(),
                photo: (item['photo'] ?? '').toString().trim().isEmpty
                    ? null
                    : (item['photo'] ?? '').toString().trim(),
                rating: (item['rating'] as num?)?.toDouble() ?? 0,
                reviewCount: (item['reviewCount'] as num?)?.toInt() ?? 0,
                serviceIds: ((item['services'] as List?) ?? const [])
                    .map(
                      (service) => service is Map<String, dynamic>
                          ? (service['_id'] ?? service['id'] ?? '').toString()
                          : service.toString(),
                    )
                    .toSet(),
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _edit([_ProfessionalItem? professional]) async {
    final nameController = TextEditingController(
      text: professional?.name ?? '',
    );
    final specialtyController = TextEditingController(
      text: professional?.specialty ?? '',
    );
    final selectedServiceIds = professional?.serviceIds.toSet() ?? <String>{};
    var photoRef = professional?.photo;
    final authToken = context.read<AuthProvider>().accessToken;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          professional == null ? 'Agregar profesional' : 'Editar profesional',
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                  TextField(
                    controller: specialtyController,
                    maxLength: 100,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Especialidad',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ImageEditField(
                    label: 'Foto del profesional',
                    value: photoRef,
                    authToken: authToken,
                    circular: true,
                    height: 96,
                    helperText: 'Se mostrará en la página de tu negocio.',
                    onChanged: (value) =>
                        setDialogState(() => photoRef = value),
                  ),
                  if (_services.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Servicios que atiende'),
                    ),
                    ..._services.map(
                      (service) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(service.name),
                        value: selectedServiceIds.contains(service.id),
                        onChanged: (selected) => setDialogState(() {
                          if (selected == true) {
                            selectedServiceIds.add(service.id);
                          } else {
                            selectedServiceIds.remove(service.id);
                          }
                        }),
                      ),
                    ),
                    Text(
                      'Si no seleccionas servicios, podrá atenderlos todos.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
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
    if (save != true || !mounted) {
      nameController.dispose();
      specialtyController.dispose();
      return;
    }
    final name = nameController.text.trim();
    final specialty = specialtyController.text.trim();
    nameController.dispose();
    specialtyController.dispose();
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El nombre debe tener al menos dos caracteres'),
        ),
      );
      return;
    }
    final isEdit = professional != null;
    final professionalId = professional?.id;
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/professionals${isEdit ? '/$professionalId' : ''}',
      );
      final payload = jsonEncode({
        'name': name,
        'specialty': specialty,
        'services': selectedServiceIds.toList(),
        // `''` limpia la foto: `parseImageRef` lo interpreta como "sin imagen".
        'photo': photoRef ?? '',
      });
      final headers = {
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      };
      final response = isEdit
          ? await http.put(uri, headers: headers, body: payload)
          : await http.post(uri, headers: headers, body: payload);
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit ? 'Profesional actualizado' : 'Profesional agregado',
            ),
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _message(response, 'No se pudo guardar el profesional'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar para guardar el profesional'),
          ),
        );
      }
    }
  }

  Future<void> _delete(_ProfessionalItem professional) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar profesional'),
        content: Text('¿Quieres eliminar a ${professional.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Conservar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final token = context.read<AuthProvider>().accessToken;
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/professionals/${professional.id}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profesional eliminado')));
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _message(response, 'No se pudo eliminar el profesional'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar para eliminar el profesional'),
          ),
        );
      }
    }
  }

  /// Resuelve la referencia de la foto a una imagen mostrable, o `null` para
  /// que el [CircleAvatar] muestre el icono por defecto.
  ImageProvider<Object>? _photoProvider(String? photo) {
    final url = AppImageUrls.resolve(photo);
    return url == null ? null : NetworkImage(url);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: _load,
            child: Text('$_error · Reintentar'),
          ),
        ),
      );
    }
    return Scaffold(
      body: _professionals.isEmpty
          ? const Center(child: Text('Aún no has agregado profesionales.'))
          : ListView(
              children: _professionals
                  .map(
                    (professional) => ListTile(
                      leading: CircleAvatar(
                        foregroundImage: _photoProvider(professional.photo),
                        child: const Icon(Icons.person_outline),
                      ),
                      title: Text(professional.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            professional.specialty.isEmpty
                                ? 'Sin especialidad'
                                : professional.specialty,
                          ),
                          if (professional.reviewCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.secondary,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    professional.rating.toStringAsFixed(1),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: AppTypography.bold,
                                        ),
                                  ),
                                  Text(
                                    ' (${professional.reviewCount})',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => action == 'edit'
                            ? _edit(professional)
                            : _delete(professional),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Editar')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar'),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _establishmentId == null ? null : () => _edit(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Agregar'),
      ),
    );
  }
}
