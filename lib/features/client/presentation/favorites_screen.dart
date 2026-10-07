import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../core/network/api_config.dart';
import '../../auth/providers/auth_provider.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}
class _FavoritesScreenState extends State<FavoritesScreen> {
  bool _loading = true; String? _error; List<Map<String,dynamic>> _favorites = [];
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = context.read<AuthProvider>().accessToken;
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/favorites'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception(response.statusCode == 401 ? 'Inicia sesión para ver tus favoritos' : 'No se pudieron cargar tus favoritos');
      final body = jsonDecode(response.body) as Map<String,dynamic>;
      if (mounted) setState(() => _favorites = (body['favorites'] as List? ?? []).whereType<Map<String,dynamic>>().toList());
    } catch(e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ','')); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _remove(String id) async {
    final token = context.read<AuthProvider>().accessToken;
    final response = await http.delete(Uri.parse('${ApiConfig.baseUrl}/favorites/$id'), headers: {'Authorization': 'Bearer $token'});
    if (!mounted) return;
    if (response.statusCode == 200) setState(() => _favorites.removeWhere((f) => f['establishmentId'] is Map && f['establishmentId']['_id'].toString() == id));
    else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo quitar de favoritos')));
  }
  @override void initState(){ super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
  @override Widget build(BuildContext context) => Scaffold(body: _loading ? const Center(child: CircularProgressIndicator()) : _error != null ? Center(child: TextButton(onPressed: _load, child: Text('$_error · Reintentar'))) : _favorites.isEmpty ? const Center(child: Text('Aún no tienes barberías favoritas')) : ListView(children: _favorites.map((favorite) {
    final establishment = favorite['establishmentId']; if (establishment is! Map<String,dynamic>) return const SizedBox.shrink();
    final id = (establishment['_id'] ?? establishment['id'] ?? '').toString(); final name = (establishment['name'] ?? 'Barbería').toString();
    return ListTile(leading: const Icon(Icons.favorite, color: Colors.red), title: Text(name), subtitle: Text('${establishment['city'] ?? ''} · ${establishment['address'] ?? ''}'), onTap: () => context.go('/client/establishment/$id?name=${Uri.encodeComponent(name)}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _remove(id)));
  }).toList()));
}
