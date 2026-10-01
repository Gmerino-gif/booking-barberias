import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ============================================================
// MODELOS (hardcodeados por ahora, luego vienen del backend)
// ============================================================

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

// ============================================================
// PANTALLA DE DETALLE DE BARBERÍA
// ============================================================

class EstablishmentDetailScreen extends StatefulWidget {
  final String establishmentId;

  const EstablishmentDetailScreen({super.key, required this.establishmentId});

  @override
  State<EstablishmentDetailScreen> createState() =>
      _EstablishmentDetailScreenState();
}

class _EstablishmentDetailScreenState
    extends State<EstablishmentDetailScreen> {
  bool _isFavorite = false;

  // --- Datos hardcodeados (después vienen del backend) ---
  final EstablishmentDetail _establishment = const EstablishmentDetail(
    id: '1',
    name: 'Barbería El Rey',
    description:
        'Somos una barbería con más de 10 años de experiencia en el mercado. '
        'Ofrecemos cortes clásicos, modernos y tratamientos de barba con los '
        'mejores productos del mercado. Ambiente familiar y profesional.',
    photos: [],
    address: 'Calle 80 #45-12, Local 3',
    city: 'Barranquilla, Atlántico',
    phone: '+57 300 123 4567',
    rating: 4.8,
    reviewCount: 124,
  );

  final List<ServiceItem> _services = const [
    ServiceItem(
      id: 's1',
      name: 'Corte Clásico',
      description: 'Corte de cabello tradicional con tijera y máquina',
      price: 25000,
      durationMin: 30,
      category: 'Cortes',
    ),
    ServiceItem(
      id: 's2',
      name: 'Corte + Barba',
      description: 'Corte completo más arreglo de barba',
      price: 35000,
      durationMin: 45,
      category: 'Cortes',
    ),
    ServiceItem(
      id: 's3',
      name: 'Fade Premium',
      description: 'Degradado profesional con diseño',
      price: 30000,
      durationMin: 40,
      category: 'Cortes',
    ),
    ServiceItem(
      id: 's4',
      name: 'Perfilado de Barba',
      description: 'Perfilado y arreglo de barba con navaja',
      price: 15000,
      durationMin: 20,
      category: 'Barba',
    ),
    ServiceItem(
      id: 's5',
      name: 'Afeitado Clásico',
      description: 'Afeitado con navaja y toalla caliente',
      price: 20000,
      durationMin: 30,
      category: 'Barba',
    ),
  ];

  final List<ProfessionalItem> _professionals = const [
    ProfessionalItem(id: 'p1', name: 'Carlos M.', specialty: 'Barbero senior'),
    ProfessionalItem(
        id: 'p2', name: 'Andrés R.', specialty: 'Especialista en barba'),
    ProfessionalItem(id: 'p3', name: 'Luis P.', specialty: 'Fade & diseño'),
  ];

  final List<ReviewItem> _reviews = const [
    ReviewItem(
      id: 'r1',
      userName: 'Juan Pérez',
      rating: 5,
      comment:
          'Excelente atención, muy profesional. El mejor corte que me han hecho en Barranquilla.',
      timeAgo: 'Hace 2 días',
    ),
    ReviewItem(
      id: 'r2',
      userName: 'Diego M.',
      rating: 5,
      comment: 'Muy buen ambiente, precios justos. Carlos es un crack.',
      timeAgo: 'Hace 1 semana',
    ),
    ReviewItem(
      id: 'r3',
      userName: 'Andrés G.',
      rating: 4,
      comment: 'Buena atención, aunque tuve que esperar un poco.',
      timeAgo: 'Hace 2 semanas',
    ),
  ];

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

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFavorite ? 'Agregado a favoritos' : 'Eliminado de favoritos',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ---------- AppBar con foto/imagen ----------
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

          // ---------- Contenido ----------
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

                  // --- Botón Reservar general ---
                  FilledButton.icon(
                    onPressed: () {
                      context.go('/client/reservas');
                    },
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

                  // --- Servicios ---
                  _buildSectionTitle(theme, 'Servicios', Icons.content_cut),
                  const SizedBox(height: 12),
                  _buildServicesList(theme),
                  const SizedBox(height: 32),

                  // --- Profesionales ---
                  _buildSectionTitle(
                      theme, 'Nuestros profesionales', Icons.people_outline),
                  const SizedBox(height: 12),
                  _buildProfessionalsList(theme),
                  const SizedBox(height: 32),

                  // --- Reseñas ---
                  _buildSectionTitle(
                    theme,
                    'Reseñas (${_establishment.reviewCount})',
                    Icons.star_outline,
                  ),
                  const SizedBox(height: 12),
                  _buildReviewsList(theme),
                  const SizedBox(height: 32),

                  // --- Info de contacto ---
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
              Icon(Icons.location_on_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
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
                    Icon(Icons.access_time,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
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
                  onPressed: () {
                    context.go(
                      '/client/reservas'
                      '?establishmentId=${_establishment.id}'
                      '&establishmentName=${Uri.encodeComponent(_establishment.name)}'
                      '&serviceId=${service.id}'
                      '&serviceName=${Uri.encodeComponent(service.name)}'
                      '&price=${service.price}'
                      '&durationMin=${service.durationMin}',
                    );
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text(
                    'Reservar',
                    style: TextStyle(fontSize: 12),
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
          _buildContactRow(theme, Icons.location_on_outlined,
              '${_establishment.address}, ${_establishment.city}'),
          const Divider(height: 20),
          _buildContactRow(theme, Icons.phone_outlined, _establishment.phone),
        ],
      ),
    );
  }

  Widget _buildContactRow(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}