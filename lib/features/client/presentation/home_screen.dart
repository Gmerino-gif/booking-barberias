import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/network/api_config.dart';
import 'widgets/nearby_map.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  bool _nearbyOnly = false;
  bool _isLoading = true;
  String? _loadError;
  List<NearbyBarber> _barbers = const [];
  double _mapLat = 10.920684;
  double _mapLng = -74.8097153;
  Timer? _searchDebounce;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadNearbyBarbers();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  List<NearbyBarber> get _visibleBarbers {
    final barbers = _barbers.toList()
      ..sort((a, b) => _distanceToCenter(a).compareTo(_distanceToCenter(b)));
    if (!_nearbyOnly) return barbers;
    return barbers
        .where(
          (barber) =>
              _distanceToCenter(barber) <= 1000,
        )
        .toList();
  }

  double _distanceToCenter(NearbyBarber barber) {
    const earthRadiusMeters = 6371000.0;
    final latitudeDelta = _radians(barber.lat - _mapLat);
    final longitudeDelta = _radians(barber.lng - _mapLng);
    final centerLatitude = _radians(_mapLat);
    final barberLatitude = _radians(barber.lat);
    final haversine =
        math.pow(math.sin(latitudeDelta / 2), 2) +
        math.cos(centerLatitude) *
            math.cos(barberLatitude) *
            math.pow(math.sin(longitudeDelta / 2), 2);
    final boundedHaversine = haversine.clamp(0.0, 1.0);
    return earthRadiusMeters *
        2 *
        math.atan2(
          math.sqrt(boundedHaversine),
          math.sqrt(1 - boundedHaversine),
        );
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  void _onMapCenterChanged(LatLng center) {
    _mapLat = center.latitude;
    _mapLng = center.longitude;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadNearbyBarbers();
    });
    if (_nearbyOnly && mounted) setState(() {});
  }

  Future<void> _loadNearbyBarbers() async {
    final requestId = ++_requestId;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/establishments/nearby')
          .replace(
            queryParameters: {
              'lat': _mapLat.toString(),
              'lng': _mapLng.toString(),
              'radius': '5000',
            },
          );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const FormatException('No se pudieron cargar las barberías');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final establishments = body['establishments'] as List<dynamic>? ?? [];
      final barbers = establishments
          .whereType<Map<String, dynamic>>()
          .where((item) => item['location'] is Map<String, dynamic>)
          .map((item) {
            final location = item['location'] as Map<String, dynamic>;
            final coordinates = location['coordinates'] as List<dynamic>;
            return NearbyBarber(
              id: item['_id']?.toString() ?? '',
              name: item['name'] as String? ?? 'Barbería',
              lat: (coordinates[1] as num).toDouble(),
              lng: (coordinates[0] as num).toDouble(),
              rating: (item['rating'] as num?)?.toDouble() ?? 0,
              address: item['address'] as String? ?? '',
              phone: item['phone'] as String? ?? '',
            );
          })
          .where((barber) => barber.id.isNotEmpty)
          .toList();

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _barbers = barbers;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loadError = 'No fue posible cargar las barberías cercanas';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(
              _nearbyOnly
                    ? 'Barberías a menos de 1 km del mapa'
                  : 'Barberías cerca de ti',
            ),
            subtitle: Text(
                  _isLoading
                    ? 'Buscando en el área visible...'
                    : '${_visibleBarbers.length} resultados en el área visible',
            ),
            trailing: Icon(
              _nearbyOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            onTap: () => setState(() => _nearbyOnly = !_nearbyOnly),
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'Mapa de barberías',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        NearbyMap(
          barbers: _visibleBarbers,
          height: 350,
          onCenterChanged: _onMapCenterChanged,
          onBarberTap: (barber) {
            context.go(
              '/client/establishment/${barber.id}'
              '?name=${Uri.encodeComponent(barber.name)}'
              '&phone=${Uri.encodeComponent(barber.phone)}',
            );
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'Barberías cercanas',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_loadError != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_loadError!),
            trailing: IconButton(
              tooltip: 'Reintentar',
              onPressed: _loadNearbyBarbers,
              icon: const Icon(Icons.refresh),
            ),
          )
        else if (_visibleBarbers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No hay barberías registradas en esta zona.'),
          )
        else
          ..._visibleBarbers.map(
            (barber) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.content_cut)),
                title: Text(barber.name),
                subtitle: Text(
                  barber.address.isEmpty ? 'Barbería cercana' : barber.address,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(barber.rating.toStringAsFixed(1)),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => context.go(
                  '/client/establishment/${barber.id}'
                  '?name=${Uri.encodeComponent(barber.name)}'
                  '&phone=${Uri.encodeComponent(barber.phone)}',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
