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
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _favorites = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
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
            Uri.parse('${ApiConfig.baseUrl}/favorites'),
            headers: {
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(
          response.statusCode == 401
              ? 'Inicia sesión para ver tus favoritos'
              : 'No se pudieron cargar tus favoritos',
        );
      }
      final body = jsonDecode(response.body);
      final items = body is Map<String, dynamic> && body['favorites'] is List
          ? body['favorites'] as List
          : const <dynamic>[];
      if (!mounted) return;
      setState(() {
        _favorites = items.whereType<Map<String, dynamic>>().toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(String establishmentId) async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final response = await http
          .delete(
            Uri.parse('${ApiConfig.baseUrl}/favorites/$establishmentId'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 204) {
        setState(() {
          _favorites = _favorites.where((favorite) {
            final establishment = favorite['establishmentId'];
            final id = establishment is Map
                ? (establishment['_id'] ?? establishment['id']).toString()
                : establishment.toString();
            return id != establishmentId;
          }).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eliminado de favoritos')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo quitar de favoritos')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo conectar para actualizar favoritos'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/client/profile'),
        ),
        title: const Text('Mis favoritos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite_border,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Aún no tienes barberías favoritas',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Toca el corazón en la barbería que quieras guardar.',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _favorites.length,
      itemBuilder: (context, index) => _buildFavoriteTile(_favorites[index]),
    );
  }

  Widget _buildFavoriteTile(Map<String, dynamic> favorite) {
    final theme = Theme.of(context);
    final establishment = favorite['establishmentId'];
    if (establishment is! Map<String, dynamic>) return const SizedBox.shrink();

    final id = (establishment['_id'] ?? establishment['id'] ?? '').toString();
    final name = (establishment['name'] ?? 'Barbería').toString();
    final city = (establishment['city'] ?? '').toString();
    final address = (establishment['address'] ?? '').toString();
    final rating = establishment['rating'] is num
        ? (establishment['rating'] as num).toDouble()
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary,
          child: Icon(Icons.store, color: theme.colorScheme.onPrimary),
        ),
        title: Text(
          name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          [
            if (city.isNotEmpty) city,
            if (address.isNotEmpty) address,
            if (rating != null) '★ ${rating.toStringAsFixed(1)}',
          ].join(' · '),
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Quitar de favoritos',
          icon: Icon(Icons.favorite, color: theme.colorScheme.error),
          onPressed: () => _remove(id),
        ),
        onTap: id.isEmpty
            ? null
            : () => context.go(
                '/client/establishment/$id'
                '?name=${Uri.encodeComponent(name)}',
              ),
      ),
    );
  }
}
