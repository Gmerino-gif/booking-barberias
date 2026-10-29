import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';
import '../../../core/utils/image_urls.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/establishments').replace(
        queryParameters: {'q': _controller.text.trim()},
      );
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('No se pudo realizar la búsqueda');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(
        () => _items = (decoded['establishments'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Logo del negocio resuelto a una imagen mostrable (o `null` para el icono).
  ImageProvider<Object>? _logoProvider(String? logo) {
    final url = AppImageUrls.resolve(logo);
    return url == null ? null : NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Nombre, ciudad o dirección',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                onPressed: _search,
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          ListTile(
            leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: Text(_error!),
            trailing: IconButton(
              tooltip: 'Reintentar',
              onPressed: _search,
              icon: const Icon(Icons.refresh),
            ),
          ),
        Expanded(
          child: _items.isEmpty && !_loading
              ? const Center(child: Text('No se encontraron barberías'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _buildTile(theme, _items[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildTile(ThemeData theme, Map<String, dynamic> item) {
    final id = (item['_id'] ?? item['id'] ?? '').toString();
    final name = (item['name'] ?? 'Barbería').toString();
    final logo = (item['logo'] as String?)?.trim();
    final subtitle = [item['city'], item['address']]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' · ');
    final rating = (item['rating'] as num?)?.toStringAsFixed(1) ?? '0.0';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary,
        foregroundImage: _logoProvider(logo),
        child: Icon(Icons.content_cut, color: theme.colorScheme.onPrimary),
      ),
      title: Text(name),
      subtitle: Text(subtitle),
      trailing: Text('★ $rating'),
      onTap: id.isEmpty
          ? null
          : () => context.go(
              '/client/establishment/$id?name=${Uri.encodeComponent(name)}',
            ),
    );
  }
}
