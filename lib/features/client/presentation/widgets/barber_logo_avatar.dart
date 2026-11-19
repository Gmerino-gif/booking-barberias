import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class BarberLogoAvatar extends StatelessWidget {
  const BarberLogoAvatar({super.key, required this.logoUrl, this.radius = 20});

  final String? logoUrl;
  final double radius;

  String? _validatedImageUrl() {
    final value = logoUrl?.trim() ?? '';
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  Widget _fallbackIcon() =>
      const Icon(Icons.content_cut, color: AppColors.accent, size: 20);

  @override
  Widget build(BuildContext context) {
    final imageUrl = _validatedImageUrl();

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.darkSurface,
      child: imageUrl == null
          ? _fallbackIcon()
          : ClipOval(
              child: SizedBox(
                width: radius * 2,
                height: radius * 2,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    final totalBytes = progress.expectedTotalBytes;
                    return Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          value: totalBytes == null
                              ? null
                              : progress.cumulativeBytesLoaded / totalBytes,
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) =>
                      Center(child: _fallbackIcon()),
                ),
              ),
            ),
    );
  }
}
