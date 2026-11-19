import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/network/api_config.dart';
import '../../../core/utils/image_urls.dart';
import 'widgets/barber_logo_avatar.dart';
import 'widgets/nearby_map.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  bool _nearbyOnly = false;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _loadError;
  List<NearbyBarber> _barbers = const [];
  double _mapLat = 10.920684;
  double _mapLng = -74.8097153;
  double? _userLat;
  double? _userLng;
  int _recenterMapId = 0;
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
        .where((barber) => _distanceToCenter(barber) <= 1000)
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

  String? _resolveBarberLogo(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final logo = value.trim();
    final uri = Uri.tryParse(logo);
    if (uri == null) return null;
    if (uri.hasScheme &&
        ((uri.scheme.toLowerCase() != 'http' &&
                uri.scheme.toLowerCase() != 'https') ||
            !uri.hasAuthority ||
            uri.host.isEmpty)) {
      return null;
    }
    return AppImageUrls.resolve(logo);
  }

  Future<Position> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Activa los servicios de ubicación para usar el GPS.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('No se concedió permiso para acceder a la ubicación.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _searchDebounce?.cancel();

    try {
      final position = await _getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _userLat = position.latitude;
        _userLng = position.longitude;
        _mapLat = position.latitude;
        _mapLng = position.longitude;
        _recenterMapId++;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo actualizar la ubicación GPS. Se buscará en el área actual.',
            ),
          ),
        );
      }
    }

    _searchDebounce?.cancel();
    try {
      await _loadNearbyBarbers();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

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
              logo: _resolveBarberLogo(item['logo']),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _isRefreshing ? null : _onRefresh,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
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

              Text(
                'Mapa de barberías',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              NearbyMap(
                barbers: _visibleBarbers,
                userLat: _userLat,
                userLng: _userLng,
                recenterId: _recenterMapId,
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
              Text(
                'Barberías cercanas',
                style: Theme.of(context).textTheme.titleLarge,
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
                    onPressed: _isRefreshing ? null : _onRefresh,
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
                      leading: BarberLogoAvatar(logoUrl: barber.logo),
                      title: Text(barber.name),
                      subtitle: Text(
                        barber.address.isEmpty
                            ? 'Barbería cercana'
                            : barber.address,
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
          ),
        ),
      ),
    );
  }
}
