import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

// ============================================================
// ETIQUETAS DE OPINIÓN RÁPIDA (BURBUJAS)
// ============================================================

/// Etiqueta seleccionable de opinión rápida.
///
/// `stars` es el peso de la etiqueta sobre la calificación (1-5). La
/// calificación final es el promedio de las etiquetas elegidas, de modo que el
/// cliente puede calificar sin escribir nada.
class ReviewTag {
  final String label;
  final int stars;

  const ReviewTag(this.label, this.stars);
}

/// Etiquetas rápidas para la barbería.
const List<ReviewTag> kEstablishmentReviewTags = [
  ReviewTag('Excelente', 5),
  ReviewTag('Buena atención', 5),
  ReviewTag('Buen ambiente', 4),
  ReviewTag('Limpio', 4),
  ReviewTag('Puntual', 4),
  ReviewTag('Buen precio', 4),
  ReviewTag('Regular', 3),
  ReviewTag('Mucha espera', 2),
];

/// Etiquetas rápidas para el profesional/barbero.
const List<ReviewTag> kProfessionalReviewTags = [
  ReviewTag('Excelente corte', 5),
  ReviewTag('Muy profesional', 5),
  ReviewTag('Amable', 5),
  ReviewTag('Corte preciso', 5),
  ReviewTag('Puntual', 4),
  ReviewTag('Regular', 3),
  ReviewTag('Llegó tarde', 2),
];

// ============================================================
// MODELOS
// ============================================================

/// Reseña ya publicada por el cliente para un servicio completado.
class SubmittedReview {
  final String id;
  final int? rating;
  final int? ratingProfessional;
  final List<String> tags;
  final String comment;

  const SubmittedReview({
    required this.id,
    this.rating,
    this.ratingProfessional,
    this.tags = const [],
    this.comment = '',
  });

  /// Construye la reseña desde la respuesta de `/reviews/my`.
  factory SubmittedReview.fromJson(Map<String, dynamic> json) {
    int? readRating(Object? value) =>
        value is num && value >= 1 && value <= 5 ? value.toInt() : null;

    final rawTags = json['tags'];
    return SubmittedReview(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      rating: readRating(json['rating']),
      ratingProfessional: readRating(json['ratingProfessional']),
      tags: rawTags is List
          ? rawTags
                .map((tag) => tag.toString().trim())
                .where((tag) => tag.isNotEmpty)
                .toList()
          : const [],
      comment: (json['comment'] ?? '').toString().trim(),
    );
  }
}

/// Datos que se envían a `POST /reviews` desde la tarjeta del historial.
class ServiceReviewDraft {
  final int? rating;
  final int? ratingProfessional;
  final List<String> tags;
  final String comment;

  const ServiceReviewDraft({
    this.rating,
    this.ratingProfessional,
    this.tags = const [],
    this.comment = '',
  });

  bool get isEmpty =>
      rating == null &&
      ratingProfessional == null &&
      tags.isEmpty &&
      comment.trim().isEmpty;
}

// ============================================================
// TARJETA DE RESEÑA DENTRO DEL HISTORIAL DE SERVICIOS
// ============================================================

/// Permite calificar la barbería y al profesional de una cita completada
/// directamente desde la tarjeta del historial.
///
/// Se califica con burbujas/etiquetas de opinión rápida; el comentario escrito
/// es opcional y aparece cuando el cliente no elige ninguna etiqueta.
class ServiceReviewCard extends StatefulWidget {
  final String establishmentName;
  final String professionalName;

  /// Reseña ya publicada (si existe) para este servicio.
  final SubmittedReview? existing;

  /// Publica la reseña. Devuelve `null` si se guardó o el mensaje de error.
  final Future<String?> Function(ServiceReviewDraft draft) onSubmit;

  const ServiceReviewCard({
    super.key,
    required this.establishmentName,
    required this.professionalName,
    required this.existing,
    required this.onSubmit,
  });

  @override
  State<ServiceReviewCard> createState() => _ServiceReviewCardState();
}

class _ServiceReviewCardState extends State<ServiceReviewCard> {
  final Set<String> _establishmentSelected = {};
  final Set<String> _professionalSelected = {};
  final TextEditingController _comment = TextEditingController();
  bool _showComment = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Promedio (redondeado) de las etiquetas elegidas que aportan estrellas.
  int? _ratingFrom(Set<String> selected, List<ReviewTag> tags) {
    final weights = tags
        .where((tag) => selected.contains(tag.label) && tag.stars > 0)
        .map((tag) => tag.stars)
        .toList();
    if (weights.isEmpty) return null;
    final average = weights.reduce((a, b) => a + b) / weights.length;
    return average.round().clamp(1, 5);
  }

  ServiceReviewDraft get _draft {
    final tags = [..._establishmentSelected, ..._professionalSelected].toList();
    return ServiceReviewDraft(
      rating: _ratingFrom(_establishmentSelected, kEstablishmentReviewTags),
      ratingProfessional: _ratingFrom(
        _professionalSelected,
        kProfessionalReviewTags,
      ),
      tags: tags,
      comment: _comment.text.trim(),
    );
  }

  bool get _hasSelection =>
      _establishmentSelected.isNotEmpty || _professionalSelected.isNotEmpty;

  Future<void> _submit() async {
    final draft = _draft;
    if (draft.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elige una etiqueta o escribe un comentario'),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final error = await widget.onSubmit(draft);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _toggle(Set<String> target, String label) {
    setState(() {
      if (!target.remove(label)) target.add(label);
      // Con etiquetas elegidas el comentario es opcional: se oculta si está vacío.
      if (_hasSelection && _comment.text.trim().isEmpty) _showComment = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: existing == null
          ? _buildForm(theme)
          : _buildSubmitted(theme, existing),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final draft = _draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.rate_review_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Califica tu servicio',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: AppTypography.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildTagGroup(
          theme,
          title: widget.establishmentName,
          icon: Icons.storefront_outlined,
          tags: kEstablishmentReviewTags,
          selected: _establishmentSelected,
          rating: _ratingFrom(_establishmentSelected, kEstablishmentReviewTags),
        ),
        const SizedBox(height: 12),
        _buildTagGroup(
          theme,
          title: widget.professionalName,
          icon: Icons.person_outline,
          tags: kProfessionalReviewTags,
          selected: _professionalSelected,
          rating: _ratingFrom(_professionalSelected, kProfessionalReviewTags),
        ),
        const SizedBox(height: 4),
        if (_showComment || !_hasSelection)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _comment,
              maxLength: 500,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              style: theme.textTheme.bodySmall,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Cuéntanos con tus palabras (opcional)',
                counterText: '',
              ),
            ),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showComment = true),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 32),
              ),
              icon: const Icon(Icons.add_comment_outlined, size: 16),
              label: Text(
                'Añadir comentario',
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _hasSelection
                    ? 'Tu reseña se publica al enviarla'
                    : 'Elige etiquetas o escribe un comentario',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: _isSubmitting || draft.isEmpty ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 34),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Enviar reseña',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTagGroup(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required List<ReviewTag> tags,
    required Set<String> selected,
    required int? rating,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: AppTypography.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              rating == null ? 'Sin calificar' : '$rating/5',
              style: theme.textTheme.labelSmall?.copyWith(
                color: rating == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.secondary,
                fontWeight: AppTypography.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: tags
              .map(
                (tag) => FilterChip(
                  label: Text(tag.label, style: theme.textTheme.labelSmall),
                  selected: selected.contains(tag.label),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) => _toggle(selected, tag.label),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSubmitted(ThemeData theme, SubmittedReview review) {
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: AppColors.success),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Tu reseña de este servicio',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: AppTypography.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildRatedRow(
          theme,
          widget.establishmentName,
          Icons.storefront_outlined,
          review.rating,
        ),
        const SizedBox(height: 4),
        _buildRatedRow(
          theme,
          widget.professionalName,
          Icons.person_outline,
          review.ratingProfessional,
        ),
        if (review.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: review.tags
                .map(
                  (tag) => Chip(
                    label: Text(tag, style: theme.textTheme.labelSmall),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
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
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (review.rating == null && review.ratingProfessional == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Calificaste con etiquetas', style: muted),
          ),
      ],
    );
  }

  Widget _buildRatedRow(
    ThemeData theme,
    String label,
    IconData icon,
    int? rating,
  ) {
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (rating == null)
          Text(
            'Sin estrellas',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Row(
            children: List.generate(5, (index) {
              return Icon(
                index < rating ? Icons.star : Icons.star_border,
                size: 14,
                color: theme.colorScheme.secondary,
              );
            }),
          ),
      ],
    );
  }
}
