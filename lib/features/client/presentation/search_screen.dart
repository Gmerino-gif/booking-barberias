import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_config.dart';

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

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/establishments')
          .replace(queryParameters: {'q': _controller.text.trim()});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
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
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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

  @override
  Widget build(BuildContext context) => Column(
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
          title: Text(_error!),
          trailing: IconButton(
            onPressed: _search,
            icon: const Icon(Icons.refresh),
          ),
        ),
      Expanded(
        child: _items.isEmpty && !_loading
            ? const Center(child: Text('No se encontraron barberías'))
            : ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final item = _items[i];
                  final id = (item['_id'] ?? item['id'] ?? '').toString();
                  final name = (item['name'] ?? 'Barbería').toString();
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.content_cut)),
                    title: Text(name),
                    subtitle: Text(
                      [item['city'], item['address']]
                          .whereType<String>()
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                    ),
                    trailing: Text(
                      '★ ${(item['rating'] as num?)?.toStringAsFixed(1) ?? '0.0'}',
                    ),
                    onTap: () => context.go(
                      '/client/establishment/$id?name=${Uri.encodeComponent(name)}',
                    ),
                  );
                },
              ),
      ),
    ],
  );
}
