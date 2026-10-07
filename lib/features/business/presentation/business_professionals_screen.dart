import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../auth/providers/auth_provider.dart';

class _ProfessionalItem {
  final String id;
  final String name;
  final String specialty;
  final Set<String> serviceIds;

  const _ProfessionalItem({
    required this.id,
    required this.name,
    required this.specialty,
    required this.serviceIds,
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
                    const Text(
                      'Si no seleccionas servicios, podrá atenderlos todos.',
                      style: TextStyle(fontSize: 12),
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
    final token = context.read<AuthProvider>().accessToken;
    final isEdit = professional != null;
    final professionalId = professional?.id;
    try {
      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/professionals${isEdit ? '/$professionalId' : ''}',
      );
      final response = isEdit
          ? await http.put(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'name': name,
                'specialty': specialty,
                'services': selectedServiceIds.toList(),
              }),
            )
          : await http.post(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'name': name,
                'specialty': specialty,
                'services': selectedServiceIds.toList(),
              }),
            );
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
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(professional.name),
                      subtitle: Text(
                        professional.specialty.isEmpty
                            ? 'Sin especialidad'
                            : professional.specialty,
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
