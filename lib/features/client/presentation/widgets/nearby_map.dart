import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_theme.dart';
import 'barber_logo_avatar.dart';

// ============================================================
// MODELO DE BARBERÍA CON UBICACIÓN
// ============================================================

class NearbyBarber {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double rating;
  final String address;
  final String phone;

  /// URL absoluta del logo del negocio, lista para mostrarse en el mapa.
  final String? logo;

  const NearbyBarber({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.rating,
    this.address = '',
    this.phone = '',
    this.logo,
  });
}

// ============================================================
// WIDGET DE MAPA CON BARBERÍAS CERCANAS
// ============================================================

class NearbyMap extends StatefulWidget {
  final List<NearbyBarber> barbers;
  final double? userLat;
  final double? userLng;
  final int recenterId;
  final double height;
  final void Function(NearbyBarber)? onBarberTap;
  final ValueChanged<LatLng>? onCenterChanged;

  const NearbyMap({
    super.key,
    required this.barbers,
    this.userLat,
    this.userLng,
    this.recenterId = 0,
    this.height = 220,
    this.onBarberTap,
    this.onCenterChanged,
  });

  @override
  State<NearbyMap> createState() => _NearbyMapState();
}

class _NearbyMapState extends State<NearbyMap> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NearbyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recenterId != oldWidget.recenterId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(_center, 14);
      });
    }
  }

  static const _barranquillaCenter = LatLng(10.920684, -74.8097153);

  LatLng get _center {
    if (widget.userLat != null && widget.userLng != null) {
      return LatLng(widget.userLat!, widget.userLng!);
    }
    if (widget.barbers.isNotEmpty) {
      return LatLng(widget.barbers.first.lat, widget.barbers.first.lng);
    }
    return _barranquillaCenter;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13.5,
              minZoom: 10,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) widget.onCenterChanged?.call(camera.center);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.booking_barberias',
              ),

              // Marcador del usuario
              if (widget.userLat != null && widget.userLng != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(widget.userLat!, widget.userLng!),
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),

              // Marcadores de barberías
              MarkerLayer(
                markers: widget.barbers.map((barber) {
                  return Marker(
                    point: LatLng(barber.lat, barber.lng),
                    width: 136,
                    height: 68,
                    alignment: Alignment.topCenter,
                    child: _BarberMapMarker(
                      key: ValueKey(barber.id),
                      barber: barber,
                      onTap: () {
                        widget.onBarberTap?.call(barber);
                        _mapController.move(LatLng(barber.lat, barber.lng), 15);
                      },
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // Botón centrar
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _mapController.move(_center, 14),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.my_location,
                    size: 20,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),

          // Etiqueta
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.place,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.barbers.length} barberías cerca',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarberMapMarker extends StatelessWidget {
  const _BarberMapMarker({
    super.key,
    required this.barber,
    required this.onTap,
  });

  final NearbyBarber barber;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: BarberLogoAvatar(logoUrl: barber.logo, radius: 17),
        ),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(maxWidth: 132),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.darkSurface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.45)),
          ),
          child: Text(
            barber.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.darkTextPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    ),
  );
}
