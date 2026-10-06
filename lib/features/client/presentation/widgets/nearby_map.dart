import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  const NearbyBarber({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.rating,
    this.address = '',
    this.phone = '',
  });
}

// ============================================================
// WIDGET DE MAPA CON BARBERÍAS CERCANAS
// ============================================================

class NearbyMap extends StatefulWidget {
  final List<NearbyBarber> barbers;
  final double? userLat;
  final double? userLng;
  final double height;
  final void Function(NearbyBarber)? onBarberTap;
  final ValueChanged<LatLng>? onCenterChanged;

  const NearbyMap({
    super.key,
    required this.barbers,
    this.userLat,
    this.userLng,
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
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () {
                        widget.onBarberTap?.call(barber);
                        _mapController.move(
                          LatLng(barber.lat, barber.lng),
                          15,
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.secondary,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.content_cut,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
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