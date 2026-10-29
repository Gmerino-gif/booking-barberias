import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_urls.dart';
import '../../auth/providers/auth_provider.dart';

class EstablishmentDetail {
  final String id;
  final String name;
  final String description;
  final List<String> photos;

  /// Banner de portada y logo del negocio (referencias `/uploads/...` o URL).
  final String? banner;
  final String? logo;

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
    this.banner,
    this.logo,
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
  final String? photo;

  /// Promedio de estrellas recibidas y número de calificaciones.
  final double rating;
  final int reviewCount;

  const ProfessionalItem({
    required this.id,
    required this.name,
    required this.specialty,
    this.photo,
    this.rating = 0,
    this.reviewCount = 0,
  });
}

class ReviewItem {
  final String id;
  final String userName;
  final int rating;
  final String comment;
  final String timeAgo;

  /// Profesional calificado en la reseña (puede faltar en reseñas antiguas).
  final String? professionalName;

  /// Etiquetas de opinión rápida elegidas por el cliente.
  final List<String> tags;

  const ReviewItem({
    required this.id,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.timeAgo,
    this.professionalName,
    this.tags = const [],
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
          photos: (establishmentMap['photos'] as List<dynamic>? ?? const [])
              .map((photo) => photo.toString().trim())
              .where((photo) => photo.isNotEmpty)
              .toList(),
          banner: _imageRef(establishmentMap['banner']),
          logo: _imageRef(establishmentMap['logo']),
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
                photo: _imageRef(item['photo']),
                rating: (item['rating'] is num ? item['rating'] : 0).toDouble(),
                reviewCount: (item['reviewCount'] is num
                        ? item['reviewCount']
                        : 0)
                    .toInt(),
              );
            })
            .toList();
        _reviews = reviewsList.whereType<Map<String, dynamic>>().map((item) {
          final userMap = item['userId'];
          final userName = userMap is Map<String, dynamic>
              ? (userMap['name'] ?? 'Usuario').toString()
              : 'Usuario';
          final professionalMap = item['professionalId'];
          final rawTags = item['tags'];
          return ReviewItem(
            id: (item['_id'] ?? item['id'] ?? '').toString(),
            userName: userName,
            rating: (item['rating'] is num ? item['rating'] : 0).toInt(),
            comment: (item['comment'] ?? '').toString(),
            timeAgo: 'Reciente',
            professionalName: professionalMap is Map<String, dynamic>
                ? (professionalMap['name'] ?? '').toString()
                : null,
            tags: rawTags is List
                ? rawTags
                      .map((tag) => tag.toString().trim())
                      .where((tag) => tag.isNotEmpty)
                      .toList()
                : const [],
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
  String _formatPrice(int value) => AppFormatters.currency(value);

  /// Normaliza una referencia de imagen del API (`null` si viene vacía).
  String? _imageRef(Object? value) {
    final ref = value?.toString().trim() ?? '';
    return ref.isEmpty ? null : ref;
  }

  /// URL absoluta lista para `Image.network`/`NetworkImage`.
  String? _imageUrl(String? ref) => AppImageUrls.resolve(ref);

  /// Vuelve al listado principal de barberías.
  void _goBack() => context.go('/client');

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
                      color: AppColors.accent,
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
      final message = _readMessage(_decodeBody(response.body));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message ?? 'No se pudo publicar la reseña'),
        ),
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
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
          title: const Text('Detalle de barbería'),
        ),
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
            leading: IconButton(
              tooltip: 'Volver',
              icon: const Icon(Icons.arrow_back),
              onPressed: _goBack,
            ),
            iconTheme: IconThemeData(color: theme.colorScheme.onPrimary),
            actions: [
              IconButton(
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite
                      ? AppColors.danger
                      : theme.colorScheme.onPrimary,
                ),
                onPressed: _toggleFavorite,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _establishment.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: AppTypography.bold,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _buildBannerBackground(theme),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.primary.withValues(alpha: 0.7),
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
                  _buildIdentityRow(theme),
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
                    label: Text(
                      'RESERVAR CITA',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: AppTypography.bold,
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

  /// Fondo del encabezado: banner del negocio o degradado con el icono por
  /// defecto cuando aún no se ha subido una imagen.
  Widget _buildBannerBackground(ThemeData theme) {
    final placeholder = Container(
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
        color: theme.colorScheme.onPrimary.withValues(alpha: 0.3),
      ),
    );

    final bannerUrl = _imageUrl(_establishment.banner) ??
        (_establishment.photos.isEmpty
            ? null
            : _imageUrl(_establishment.photos.first));
    if (bannerUrl == null) return placeholder;

    return Image.network(
      bannerUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }

  /// Logo del negocio junto a la valoración y la dirección.
  Widget _buildIdentityRow(ThemeData theme) {
    final logoUrl = _imageUrl(_establishment.logo);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primary,
          foregroundImage: logoUrl == null ? null : NetworkImage(logoUrl),
          child: Icon(
            Icons.storefront_outlined,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: _buildInfoRow(theme)),
      ],
    );
  }

  Widget _buildInfoRow(ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Icon(Icons.star, color: theme.colorScheme.secondary, size: 18),
              const SizedBox(width: 4),
              Text(
                '${_establishment.rating}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: AppTypography.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${_establishment.reviewCount})',
                style: theme.textTheme.bodySmall?.copyWith(
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
                  style: theme.textTheme.bodySmall?.copyWith(
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
        Text(
          'Sobre nosotros',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: AppTypography.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _establishment.description,
          style: theme.textTheme.bodySmall?.copyWith(
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
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: AppTypography.bold,
          ),
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
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: AppTypography.bold,
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
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: AppTypography.bold,
                  ),
                ),
                const SizedBox(height: 4),
                if (service.description.isNotEmpty)
                  Text(
                    service.description,
                    style: theme.textTheme.bodySmall?.copyWith(
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
                      style: theme.textTheme.bodySmall?.copyWith(
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
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppTypography.bold,
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
                  child: Text(
                    'Reservar',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
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
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _professionals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final p = _professionals[i];
          final photoUrl = _imageUrl(p.photo);
          return Container(
            width: 130,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primary,
                  foregroundImage: photoUrl == null
                      ? null
                      : NetworkImage(photoUrl),
                  child: Text(
                    p.name.substring(0, 1),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: AppTypography.bold,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  p.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: AppTypography.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  p.specialty,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (p.reviewCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.star,
                          size: 12,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          p.rating.toStringAsFixed(1),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: AppTypography.bold,
                          ),
                        ),
                        Text(
                          ' (${p.reviewCount})',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
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
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: AppTypography.bold,
                    color: theme.colorScheme.onPrimary,
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: AppTypography.bold,
                      ),
                    ),
                    Text(
                      review.timeAgo,
                      style: theme.textTheme.labelSmall?.copyWith(
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
          if (review.professionalName != null &&
              review.professionalName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.content_cut,
                  size: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Atención de ${review.professionalName}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (review.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: review.tags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.08,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        tag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.4,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactInfo(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
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
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}
