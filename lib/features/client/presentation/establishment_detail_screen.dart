import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../auth/providers/auth_provider.dart';

class EstablishmentDetail {
  final String id;
  final String name;
  final String description;
  final List<String> photos;
  final String address;
  final String city;
  final String phone;
  final double rating;
  final int reviewCount;

  const EstablishmentDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.photos,
    required this.address,
    required this.city,
    required this.phone,
    required this.rating,
    required this.reviewCount,
  });
}

class ServiceItem {
  final String id;
  final String name;
  final String description;
  final int price;
  final int durationMin;
  final String category;

  const ServiceItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.durationMin,
    required this.category,
  });
}

class ProfessionalItem {
  final String id;
  final String name;
  final String specialty;

  const ProfessionalItem({
    required this.id,
    required this.name,
    required this.specialty,
  });
}

class ReviewItem {
  final String id;
  final String userName;
  final int rating;
  final String comment;
  final String timeAgo;

  const ReviewItem({
    required this.id,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.timeAgo,
  });
}

class EstablishmentDetailScreen extends StatefulWidget {
  final String establishmentId;
  final String? establishmentName;
  final String? establishmentPhone;

  const EstablishmentDetailScreen({
    super.key,
    required this.establishmentId,
    this.establishmentName,
    this.establishmentPhone,
  });

  @override
  State<EstablishmentDetailScreen> createState() =>
      _EstablishmentDetailScreenState();
}

class _EstablishmentDetailScreenState extends State<EstablishmentDetailScreen> {
  bool _isFavorite = false;
  bool _isLoading = true;
  String? _error;

  EstablishmentDetail _establishment = const EstablishmentDetail(
    id: '',
    name: 'Barbería',
    description: '',
    photos: [],
    address: '',
    city: '',
    phone: '',
    rating: 0,
    reviewCount: 0,
  );

  List<ServiceItem> _services = const [];
  List<ProfessionalItem> _professionals = const [];
  List<ReviewItem> _reviews = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final token = context.read<AuthProvider>().accessToken;
      final establishmentUri = Uri.parse(
        '${ApiConfig.baseUrl}/establishments/${widget.establishmentId}',
      );
      final servicesUri = Uri.parse(
        '${ApiConfig.baseUrl}/services?establishmentId=${widget.establishmentId}',
      );
      final professionalsUri = Uri.parse(
        '${ApiConfig.baseUrl}/professionals/establishment/${widget.establishmentId}',
      );
      final reviewsUri = Uri.parse(
        '${ApiConfig.baseUrl}/reviews/establishment/${widget.establishmentId}',
      );

      final responses = await Future.wait([
        http.get(establishmentUri).timeout(const Duration(seconds: 15)),
        http.get(servicesUri).timeout(const Duration(seconds: 15)),
        http.get(professionalsUri).timeout(const Duration(seconds: 15)),
        http.get(reviewsUri).timeout(const Duration(seconds: 15)),
      ]);

      final establishmentBody = _decodeBody(responses[0].body);
      final servicesBody = _decodeBody(responses[1].body);
      final professionalsBody = _decodeBody(responses[2].body);
      final reviewsBody = _decodeBody(responses[3].body);

      if (!mounted) return;

      if (responses[0].statusCode != 200 ||
          establishmentBody is! Map<String, dynamic>) {
        throw Exception(
          _readMessage(establishmentBody) ?? 'No se pudo cargar la barbería',
        );
      }

      final establishmentMap = establishmentBody['establishment'];
      if (establishmentMap is! Map<String, dynamic>) {
        throw const FormatException('Respuesta de establecimiento inválida');
      }

      final servicesList =
          (servicesBody is Map<String, dynamic>
                  ? servicesBody['services']
                  : null)
              as List<dynamic>? ??
          const [];
      final professionalsList =
          (professionalsBody is Map<String, dynamic>
                  ? professionalsBody['professionals']
                  : null)
              as List<dynamic>? ??
          const [];
      final reviewsList =
          (reviewsBody is Map<String, dynamic> ? reviewsBody['reviews'] : null)
              as List<dynamic>? ??
          const [];

      setState(() {
        _establishment = EstablishmentDetail(
          id: (establishmentMap['_id'] ?? widget.establishmentId).toString(),
          name:
              (establishmentMap['name'] ??
                      widget.establishmentName ??
                      'Barbería')
                  .toString(),
          description: (establishmentMap['description'] ?? 'Sin descripción')
              .toString(),
          photos: const [],
          address: (establishmentMap['address'] ?? '').toString(),
          city: (establishmentMap['city'] ?? '').toString(),
          phone: (establishmentMap['phone'] ?? widget.establishmentPhone ?? '')
              .toString(),
          rating:
              (establishmentMap['rating'] is num
                      ? establishmentMap['rating']
                      : 0)
                  .toDouble(),
          reviewCount:
              (establishmentMap['reviewCount'] is num
                      ? establishmentMap['reviewCount']
                      : reviewsList.length)
                  as int,
        );
        _services = servicesList.whereType<Map<String, dynamic>>().map((item) {
          final rawCategory = item['category'] ?? 'General';
          return ServiceItem(
            id: (item['_id'] ?? item['id'] ?? '').toString(),
            name: (item['name'] ?? 'Servicio').toString(),
            description: (item['description'] ?? '').toString(),
            price: (item['price'] is num ? item['price'] : 0).toInt(),
            durationMin: (item['durationMin'] is num ? item['durationMin'] : 30)
                .toInt(),
            category: rawCategory.toString(),
          );
        }).toList();
        _professionals = professionalsList
            .whereType<Map<String, dynamic>>()
            .map((item) {
              return ProfessionalItem(
                id: (item['_id'] ?? item['id'] ?? '').toString(),
                name: (item['name'] ?? 'Profesional').toString(),
                specialty: (item['specialty'] ?? 'Barbero').toString(),
              );
            })
            .toList();
        _reviews = reviewsList.whereType<Map<String, dynamic>>().map((item) {
          final userMap = item['userId'];
          final userName = userMap is Map<String, dynamic>
              ? (userMap['name'] ?? 'Usuario').toString()
              : 'Usuario';
          return ReviewItem(
            id: (item['_id'] ?? item['id'] ?? '').toString(),
            userName: userName,
            rating: (item['rating'] is num ? item['rating'] : 0).toInt(),
            comment: (item['comment'] ?? '').toString(),
            timeAgo: 'Reciente',
          );
        }).toList();
        _isLoading = false;
        _error = null;
      });
      if (token != null) {
        final favoriteResponse = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/favorites'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (favoriteResponse.statusCode == 200 && mounted) {
          final body = _decodeBody(favoriteResponse.body);
          final favorites = body?['favorites'] as List? ?? [];
          setState(
            () => _isFavorite = favorites.any(
              (f) =>
                  f is Map &&
                  ((f['establishmentId'] is Map
                              ? f['establishmentId']['_id']
                              : f['establishmentId'])
                          .toString() ==
                      widget.establishmentId),
            ),
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Map<String, dynamic>? _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _readMessage(Map<String, dynamic>? body) {
    final value = body?['message'];
    return value is String ? value : null;
  }

  void _goToReservation({
    String? serviceId,
    String? serviceName,
    int? price,
    int? durationMin,
  }) {
    if (_services.isEmpty || serviceId == null || serviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay servicios disponibles para esta barbería.'),
        ),
      );
      return;
    }

    final selectedService = _services.firstWhere(
      (service) => service.id == serviceId,
      orElse: () => _services.first,
    );

    context.go(
      '/client/reservas'
      '?establishmentId=${_establishment.id}'
      '&establishmentName=${Uri.encodeComponent(_establishment.name)}'
      '&serviceId=${selectedService.id}'
      '&serviceName=${Uri.encodeComponent(selectedService.name)}'
      '&price=${selectedService.price}'
      '&durationMin=${selectedService.durationMin}',
    );
  }

  // ============================================================
  // Utilidades
  // ============================================================
  String _formatPrice(int value) {
    final str = value.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return '\$${buf.toString()}';
  }

  Future<void> _toggleFavorite() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para guardar favoritos')),
      );
      return;
    }
    final wasFavorite = _isFavorite;
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/favorites${wasFavorite ? '/${widget.establishmentId}' : ''}',
    );
    final response = wasFavorite
        ? await http.delete(uri, headers: {'Authorization': 'Bearer $token'})
        : await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'establishmentId': widget.establishmentId}),
          );
    if (!mounted) return;
    if (response.statusCode == 200 ||
        response.statusCode == 201 ||
        (!wasFavorite && response.statusCode == 409)) {
      setState(() => _isFavorite = !wasFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFavorite ? 'Agregado a favoritos' : 'Eliminado de favoritos',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar favoritos')),
      );
    }
  }

  Future<void> submitReview() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para escribir una reseña')),
      );
      return;
    }
    var rating = 5;
    final comment = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Escribe tu reseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (index) => IconButton(
                    onPressed: () => setDialogState(() => rating = index + 1),
                    icon: Icon(
                      index < rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: comment,
                maxLength: 500,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Cuéntanos cómo fue tu experiencia',
                ),
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
              child: const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
    if (submit != true || !mounted) {
      comment.dispose();
      return;
    }
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/reviews'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'establishmentId': widget.establishmentId,
        'rating': rating,
        'comment': comment.text.trim(),
      }),
    );
    comment.dispose();
    if (!mounted) return;
    if (response.statusCode == 201) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reseña publicada')));
      await _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo publicar la reseña')),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle de barbería')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? Colors.red : Colors.white,
                ),
                onPressed: _toggleFavorite,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _establishment.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.store,
                      size: 100,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(theme),
                  const SizedBox(height: 20),
                  _buildDescription(theme),
                  const SizedBox(height: 24),

                  FilledButton.icon(
                    onPressed: _services.isEmpty
                        ? null
                        : () => _goToReservation(
                            serviceId: _services.first.id,
                            serviceName: _services.first.name,
                            price: _services.first.price,
                            durationMin: _services.first.durationMin,
                          ),
                    icon: const Icon(Icons.calendar_month),
                    label: const Text(
                      'RESERVAR CITA',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildSectionTitle(theme, 'Servicios', Icons.content_cut),
                  const SizedBox(height: 12),
                  _buildServicesList(theme),
                  const SizedBox(height: 32),
                  _buildSectionTitle(
                    theme,
                    'Nuestros profesionales',
                    Icons.people_outline,
                  ),
                  const SizedBox(height: 12),
                  _buildProfessionalsList(theme),
                  const SizedBox(height: 32),
                  _buildSectionTitle(
                    theme,
                    'Reseñas (${_establishment.reviewCount})',
                    Icons.star_outline,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: submitReview,
                      icon: const Icon(Icons.rate_review_outlined),
                      label: const Text('Escribir reseña'),
                    ),
                  ),
                  _buildReviewsList(theme),
                  const SizedBox(height: 32),
                  _buildSectionTitle(theme, 'Contacto', Icons.info_outline),
                  const SizedBox(height: 12),
                  _buildContactInfo(theme),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WIDGETS AUXILIARES
  // ============================================================

  Widget _buildInfoRow(ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.star, color: theme.colorScheme.secondary, size: 18),
              const SizedBox(width: 4),
              Text(
                '${_establishment.rating}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${_establishment.reviewCount})',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${_establishment.address}, ${_establishment.city}',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sobre nosotros',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          _establishment.description,
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildServicesList(ThemeData theme) {
    final Map<String, List<ServiceItem>> grouped = {};
    for (final s in _services) {
      grouped.putIfAbsent(s.category, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                entry.key.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...entry.value.map((s) => _buildServiceTile(theme, s)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildServiceTile(ThemeData theme, ServiceItem service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                if (service.description.isNotEmpty)
                  Text(
                    service.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${service.durationMin} min',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatPrice(service.price),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: FilledButton(
                  onPressed: () => _goToReservation(
                    serviceId: service.id,
                    serviceName: service.name,
                    price: service.price,
                    durationMin: service.durationMin,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Reservar', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalsList(ThemeData theme) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _professionals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final p = _professionals[i];
          return Container(
            width: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    p.name.substring(0, 1),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  p.specialty,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewsList(ThemeData theme) {
    return Column(
      children: _reviews.map((r) => _buildReviewTile(theme, r)).toList(),
    );
  }

  Widget _buildReviewTile(ThemeData theme, ReviewItem review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  review.userName.substring(0, 1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      review.timeAgo,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < review.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: theme.colorScheme.secondary,
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.comment,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          _buildContactRow(
            theme,
            Icons.location_on_outlined,
            '${_establishment.address}, ${_establishment.city}',
          ),
          if (_establishment.phone.isNotEmpty) ...[
            const Divider(height: 20),
            _buildContactRow(theme, Icons.phone_outlined, _establishment.phone),
          ],
        ],
      ),
    );
  }

  Widget _buildContactRow(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}
