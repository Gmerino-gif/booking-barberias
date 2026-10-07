import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_config.dart';
import '../../auth/providers/auth_provider.dart';

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({super.key});

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _locationSearchCtrl = TextEditingController();
  final _mapController = MapController();
  final _mapKey = GlobalKey();
  final _locationFieldKey = GlobalKey<FormFieldState<LatLng>>();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSearchingLocation = false;
  bool _isGettingLocation = false;
  bool _mapReady = false;
  bool _locationConfirmed = true;
  bool _locationSearchHasError = false;
  String? _locationSearchMessage;
  LatLng? _selectedLocation;
  int _searchRequestSequence = 0;
  DateTime? _lastNominatimRequestAt;

  static const _defaultMapCenter = LatLng(10.920684, -74.8097153);
  static const _nominatimUserAgent =
      'booking_app/1.0 (OpenStreetMap Nominatim location search)';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEstablishment());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _descriptionCtrl.dispose();
    _locationSearchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().length < 2) {
      return 'El nombre del negocio debe tener al menos 2 caracteres';
    }
    if (value.trim().length > 100) {
      return 'El nombre es demasiado largo';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\+?[0-9\s().-]+$').hasMatch(phone) ||
        digits.length < 7 ||
        digits.length > 15 ||
        phone.length > 20) {
      return 'Ingresa un número válido';
    }
    return null;
  }

  String? _validateRequired(String? value, String label, int maxLength) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Ingresa $label';
    if (text.length > maxLength) return '$label es demasiado largo';
    return null;
  }

  Future<void> _loadEstablishment() async {
    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      _showLocationMessage(
        'No hay sesión activa para cargar tu negocio.',
        isError: true,
      );
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/establishments/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final decoded = _decodeResponse(response.body);

      if (response.statusCode != 200 || decoded is! Map<String, dynamic>) {
        final message = decoded is Map<String, dynamic>
            ? decoded['message'] as String?
            : null;
        _showLocationMessage(
          message ?? 'No se pudo cargar la información del negocio.',
          isError: true,
        );
        setState(() => _isLoading = false);
        return;
      }

      final establishment = decoded['establishment'];
      if (establishment is! Map<String, dynamic>) {
        setState(() => _isLoading = false);
        return;
      }

      final lat = establishment['lat'];
      final lng = establishment['lng'];
      final initialPoint = lat is num && lng is num
          ? LatLng(lat.toDouble(), lng.toDouble())
          : null;

      _nameCtrl.text = (establishment['name'] ?? '').toString();
      _phoneCtrl.text = (establishment['phone'] ?? '').toString();
      _addressCtrl.text = (establishment['address'] ?? '').toString();
      _cityCtrl.text = (establishment['city'] ?? '').toString();
      _descriptionCtrl.text = (establishment['description'] ?? '').toString();
      _selectedLocation = initialPoint ?? _defaultMapCenter;
      _locationConfirmed = initialPoint != null;
      _locationFieldKey.currentState?.didChange(_selectedLocation);

      if (_mapReady && _selectedLocation != null) {
        _mapController.move(_selectedLocation!, 15);
      }

      if (mounted) setState(() => _isLoading = false);
    } on TimeoutException {
      if (mounted) {
        _showLocationMessage(
          'La carga tardó demasiado. Inténtalo de nuevo.',
          isError: true,
        );
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        _showLocationMessage(
          'No fue posible cargar el negocio.',
          isError: true,
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final token = context.read<AuthProvider>().accessToken;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu sesión expiró. Inicia sesión otra vez.'),
        ),
      );
      return;
    }

    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la ubicación del negocio en el mapa.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final response = await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}/establishments/me'),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'name': _nameCtrl.text.trim(),
              'address': _addressCtrl.text.trim(),
              'city': _cityCtrl.text.trim(),
              'lat': _selectedLocation!.latitude,
              'lng': _selectedLocation!.longitude,
              'description': _descriptionCtrl.text.trim(),
              'phone': _phoneCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final decoded = _decodeResponse(response.body);
      if (!mounted) return;

      if (response.statusCode == 200 && decoded is Map<String, dynamic>) {
        _locationConfirmed = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Negocio actualizado correctamente.')),
        );
      } else {
        final message = decoded is Map<String, dynamic>
            ? decoded['message'] as String?
            : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message ?? 'No se pudo actualizar el negocio.'),
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El servidor tardó demasiado en responder.'),
          ),
        );
      }
    } on http.ClientException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible conectar con el servidor.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ocurrió un error al guardar el negocio.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showLocationMessage(
          'Activa la ubicación del dispositivo o elige el punto manualmente.',
          isError: true,
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showLocationMessage(
          'No se puede usar GPS. Puedes mover el pin manualmente en el mapa.',
          isError: true,
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _setLocation(
        LatLng(position.latitude, position.longitude),
        confirmed: false,
      );
      _showLocationMessage(
        'Ubicación GPS sugerida. Confirma que el pin coincide con tu negocio.',
      );
    } catch (_) {
      _showLocationMessage(
        'No se pudo obtener la ubicación. Puedes elegir manualmente en el mapa.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _searchLocation() async {
    if (_isSearchingLocation) return;
    final query = _locationSearchCtrl.text.trim();
    if (query.isEmpty) {
      setState(() {
        _locationSearchMessage = 'Escribe una ciudad o un barrio para buscar.';
        _locationSearchHasError = true;
      });
      return;
    }

    final requestSequence = ++_searchRequestSequence;
    setState(() {
      _isSearchingLocation = true;
      _locationSearchMessage = null;
      _locationSearchHasError = false;
    });

    try {
      final lastRequestAt = _lastNominatimRequestAt;
      if (lastRequestAt != null) {
        final elapsed = DateTime.now().difference(lastRequestAt);
        if (elapsed < const Duration(seconds: 1)) {
          await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
        }
      }
      _lastNominatimRequestAt = DateTime.now();

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '1',
      });

      final response = await http
          .get(uri, headers: const {'User-Agent': _nominatimUserAgent})
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw const FormatException('Nominatim search failed');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) {
        throw const FormatException('No results');
      }
      final result = decoded.first;
      if (result is! Map<String, dynamic>) {
        throw const FormatException('Invalid response');
      }

      final latitude = double.tryParse(result['lat']?.toString() ?? '');
      final longitude = double.tryParse(result['lon']?.toString() ?? '');
      if (latitude == null ||
          longitude == null ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        throw const FormatException('Invalid coordinates');
      }

      if (!mounted || requestSequence != _searchRequestSequence) return;
      _setLocation(LatLng(latitude, longitude), confirmed: false);
      setState(() {
        _locationSearchMessage = 'Lugar encontrado. Ajusta el pin hasta la ubicación exacta del negocio.';
        _locationSearchHasError = false;
      });
    } on TimeoutException {
      if (mounted && requestSequence == _searchRequestSequence) {
        setState(() {
          _locationSearchMessage =
              'La búsqueda tardó demasiado. Inténtalo de nuevo o mueve el pin.';
          _locationSearchHasError = true;
        });
      }
    } catch (_) {
      if (mounted && requestSequence == _searchRequestSequence) {
        setState(() {
          _locationSearchMessage = 'No se pudo buscar la ubicación. Revisa tu conexión o mueve el pin manualmente.';
          _locationSearchHasError = true;
        });
      }
    } finally {
      if (mounted && requestSequence == _searchRequestSequence) {
        setState(() => _isSearchingLocation = false);
      }
    }
  }

  void _setLocation(LatLng point, {required bool confirmed}) {
    setState(() {
      _selectedLocation = point;
      _locationConfirmed = confirmed;
    });
    _locationFieldKey.currentState?.didChange(point);
    if (_mapReady) _mapController.move(point, 15);
  }

  void _showLocationMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _locationSearchMessage = message;
      _locationSearchHasError = isError;
    });
  }

  void _onPinDrag(DragUpdateDetails details) {
    final renderObject = _mapKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;
    final localPosition = renderObject.globalToLocal(details.globalPosition);
    final point = _mapController.camera.offsetToCrs(localPosition);
    _setLocation(point, confirmed: true);
  }

  dynamic _decodeResponse(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi negocio'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/business'),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Información del negocio',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del establecimiento',
                          prefixIcon: Icon(Icons.store_outlined),
                        ),
                        validator: _validateName,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Celular del establecimiento',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: _validatePhone,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        validator: (value) =>
                            _validateRequired(value, 'la dirección', 200),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cityCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Ciudad',
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                        validator: (value) =>
                            _validateRequired(value, 'la ciudad', 100),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionCtrl,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Descripción del negocio',
                          prefixIcon: Icon(Icons.description_outlined),
                        ),
                        validator: (value) =>
                            _validateRequired(value, 'la descripción', 1000),
                      ),
                      const SizedBox(height: 20),
                      FormField<LatLng>(
                        key: _locationFieldKey,
                        validator: (_) => _selectedLocation == null
                            ? 'Selecciona la ubicación del establecimiento'
                            : !_locationConfirmed
                            ? 'Confirma que el pin esté en el negocio'
                            : null,
                        builder: (field) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Ubicación del negocio',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Busca la zona o mueve el pin hasta la ubicación exacta del local.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _locationSearchCtrl,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.search,
                                    decoration: const InputDecoration(
                                      labelText: 'Ciudad o barrio',
                                      prefixIcon: Icon(Icons.search),
                                    ),
                                    onSubmitted: (_) => _searchLocation(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: _isSearchingLocation
                                      ? null
                                      : _searchLocation,
                                  tooltip: 'Buscar en OpenStreetMap',
                                  icon: _isSearchingLocation
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.search),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _isGettingLocation
                                  ? null
                                  : _useCurrentLocation,
                              icon: _isGettingLocation
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.my_location),
                              label: Text(
                                _isGettingLocation
                                    ? 'Obteniendo ubicación…'
                                    : 'Sugerir mi ubicación',
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 260,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: FlutterMap(
                                  key: _mapKey,
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter:
                                        _selectedLocation ?? _defaultMapCenter,
                                    initialZoom: 14,
                                    minZoom: 3,
                                    maxZoom: 19,
                                    interactionOptions:
                                        const InteractionOptions(
                                          flags:
                                              InteractiveFlag.all &
                                              ~InteractiveFlag.rotate,
                                        ),
                                    onMapReady: () {
                                      _mapReady = true;
                                      if (_selectedLocation != null) {
                                        _mapController.move(
                                          _selectedLocation!,
                                          15,
                                        );
                                      }
                                    },
                                    onTap: (_, point) =>
                                        _setLocation(point, confirmed: true),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.buking.booking_app',
                                    ),
                                    if (_selectedLocation != null)
                                      MarkerLayer(
                                        markers: [
                                          Marker(
                                            point: _selectedLocation!,
                                            width: 52,
                                            height: 58,
                                            alignment: Alignment.topCenter,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () => _setLocation(
                                                _selectedLocation!,
                                                confirmed: true,
                                              ),
                                              onPanUpdate: _onPinDrag,
                                              child: const Icon(
                                                Icons.location_pin,
                                                color: Colors.red,
                                                size: 48,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    RichAttributionWidget(
                                      attributions: [
                                        TextSourceAttribution(
                                          '© OpenStreetMap contributors',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_selectedLocation != null)
                              Text(
                                'Pin ${_locationConfirmed ? 'confirmado' : 'sugerido'} · '
                                '${_selectedLocation!.latitude.toStringAsFixed(6)}, '
                                '${_selectedLocation!.longitude.toStringAsFixed(6)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _locationConfirmed
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else
                              Text(
                                'Toca el mapa para colocar el pin.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (_locationSearchMessage != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _locationSearchMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _locationSearchHasError
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (_selectedLocation != null &&
                                !_locationConfirmed) ...[
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: () => _setLocation(
                                  _selectedLocation!,
                                  confirmed: true,
                                ),
                                icon: const Icon(Icons.check),
                                label: const Text('Confirmar este punto'),
                              ),
                            ],
                            if (field.hasError) ...[
                              const SizedBox(height: 6),
                              Text(
                                field.errorText!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _isSaving ? 'Guardando...' : 'Guardar cambios',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

