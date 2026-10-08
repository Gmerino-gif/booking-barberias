import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/network/api_config.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _establishmentNameCtrl = TextEditingController();
  final _establishmentPhoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _locationSearchCtrl = TextEditingController();
  final _locationFieldKey = GlobalKey<FormFieldState<LatLng>>();
  final _mapKey = GlobalKey();
  final _mapController = MapController();

  bool _isBusiness = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _acceptTerms = false;
  bool _isLoading = false;
  bool _isSearchingLocation = false;
  bool _isGettingLocation = false;
  bool _mapReady = false;
  bool _locationConfirmed = false;
  String? _locationSearchMessage;
  bool _locationSearchHasError = false;
  LatLng? _selectedLocation;
  int _searchRequestSequence = 0;
  DateTime? _lastNominatimRequestAt;
  String? _pendingOwnerToken;

  static const _defaultMapCenter = LatLng(10.920684, -74.8097153);
  static const _nominatimUserAgent =
      'booking_app/1.0 (OpenStreetMap Nominatim location search)';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryInitialGpsSuggestion();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _establishmentNameCtrl.dispose();
    _establishmentPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _descriptionCtrl.dispose();
    _locationSearchCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().length < 2) {
      return 'El nombre debe tener al menos 2 caracteres';
    }
    if (v.trim().length > 80) {
      return 'El nombre es demasiado largo';
    }
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.isEmpty) return 'Ingresa tu correo';
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!regex.hasMatch(v.trim())) return 'Correo inválido';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\+?[0-9\s().-]+$').hasMatch(phone) ||
        digits.length < 7 ||
        digits.length > 15 ||
        phone.length > 20) {
      return 'Ingresa un número válido (7 a 15 dígitos)';
    }
    return null;
  }

  String? _validateRequired(String? value, String label, int maxLength) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Ingresa $label';
    if (text.length > maxLength) return '$label es demasiado largo';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Ingresa una contraseña';
    if (v.length < 8) return 'Mínimo 8 caracteres';
    if (v.length > 72) return 'Máximo 72 caracteres';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v != _passwordCtrl.text) return 'Las contraseñas no coinciden';
    return null;
  }

  Future<void> _tryInitialGpsSuggestion() async {
    if (!mounted) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 7),
        ),
      );
      if (!mounted) return;
      _setLocation(
        LatLng(position.latitude, position.longitude),
        confirmed: false,
      );
    } catch (_) {
      // GPS is optional: manual selection remains available.
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
          'No hay permiso de ubicación. Puedes elegir el punto directamente en el mapa.',
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
      if (!mounted) return;
      _setLocation(
        LatLng(position.latitude, position.longitude),
        confirmed: false,
      );
      _showLocationMessage(
        'Ubicación GPS sugerida. Confirma que el pin esté en tu local o muévelo antes de continuar.',
      );
    } catch (_) {
      _showLocationMessage(
        'No se pudo obtener la ubicación. Puedes elegir el punto directamente en el mapa.',
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
        throw const FormatException('Invalid Nominatim response');
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
        _locationSearchMessage = 'Lugar encontrado. Confirma o ajusta el pin para indicar la ubicación exacta del establecimiento.';
        _locationSearchHasError = false;
      });
    } on TimeoutException {
      if (mounted && requestSequence == _searchRequestSequence) {
        setState(() {
          _locationSearchMessage = 'La búsqueda tardó demasiado. Inténtalo de nuevo o coloca el pin manualmente.';
          _locationSearchHasError = true;
        });
      }
    } catch (_) {
      if (mounted && requestSequence == _searchRequestSequence) {
        setState(() {
          _locationSearchMessage = 'No se pudo buscar el lugar. Revisa tu conexión o selecciona la ubicación en el mapa.';
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar los términos y condiciones'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    var registered = false;
    String? errorMessage;

    try {
      if (_pendingOwnerToken == null) {
        final response = await http
            .post(
              Uri.parse('${ApiConfig.baseUrl}/auth/register'),
              headers: const {
                'Content-Type': 'application/json; charset=UTF-8',
              },
              body: jsonEncode({
                'name': _nameCtrl.text.trim(),
                'phone': _phoneCtrl.text.trim(),
                'email': _emailCtrl.text.trim(),
                'password': _passwordCtrl.text,
                'role': _isBusiness ? 'owner' : 'client',
              }),
            )
            .timeout(const Duration(seconds: 15));

        final responseBody = _decodeResponse(response.body);
        if (response.statusCode != 201) {
          errorMessage =
              _responseMessage(responseBody) ?? 'No se pudo crear la cuenta';
        } else if (_isBusiness) {
          final token = responseBody is Map<String, dynamic>
              ? responseBody['token'] as String?
              : null;
          if (token == null || token.isEmpty) {
            errorMessage = 'La cuenta se creó, pero el servidor no devolvió el token para registrar el establecimiento.';
          } else {
            _pendingOwnerToken = token;
          }
        } else {
          registered = true;
        }
      }

      if (_isBusiness && _pendingOwnerToken != null) {
        final establishmentResponse = await http
            .post(
              Uri.parse('${ApiConfig.baseUrl}/establishments'),
              headers: {
                'Content-Type': 'application/json; charset=UTF-8',
                'Authorization': 'Bearer $_pendingOwnerToken',
              },
              body: jsonEncode({
                'name': _establishmentNameCtrl.text.trim(),
                'address': _addressCtrl.text.trim(),
                'city': _cityCtrl.text.trim(),
                'lat': _selectedLocation!.latitude,
                'lng': _selectedLocation!.longitude,
                'description': _descriptionCtrl.text.trim(),
                'phone': _establishmentPhoneCtrl.text.trim(),
              }),
            )
            .timeout(const Duration(seconds: 15));
        final establishmentBody = _decodeResponse(establishmentResponse.body);
        if (establishmentResponse.statusCode == 200 ||
            establishmentResponse.statusCode == 201) {
          registered = true;
          _pendingOwnerToken = null;
        } else {
          errorMessage =
              'La cuenta se creó, pero no se pudo registrar el establecimiento: '
              '${_responseMessage(establishmentBody) ?? 'revisa los datos e inténtalo de nuevo'}.';
        }
      }

      if (errorMessage != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El servidor tardó demasiado en responder'),
          ),
        );
      }
    } on http.ClientException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible conectar con el servidor'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _pendingOwnerToken != null
                  ? 'La cuenta ya se creó, pero no fue posible registrar el establecimiento. Revisa tu conexión e inténtalo de nuevo.'
                  : 'Ocurrió un error al crear la cuenta',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    if (!mounted || !registered) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 8),
            Text('¡Cuenta creada!'),
          ],
        ),
        content: Text(
          'Tu cuenta de ${_isBusiness ? 'Negocio' : 'Cliente'} ha sido creada exitosamente.\n\n'
          '${_isBusiness ? 'El establecimiento también quedó registrado.' : 'Ya puedes iniciar sesión.'}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/login');
            },
            child: const Text('Ir al login'),
          ),
        ],
      ),
    );
  }

  dynamic _decodeResponse(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  String? _responseMessage(dynamic response) {
    return response is Map<String, dynamic>
        ? response['message'] as String?
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
        title: const Text('Crear cuenta'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.content_cut,
                        size: 60,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Únete a Booking App',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reserva tu próximo corte en segundos',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTypeButton(
                          label: 'Cliente',
                          icon: Icons.person_outline,
                          selected: !_isBusiness,
                          onTap: _pendingOwnerToken == null
                              ? () => setState(() => _isBusiness = false)
                              : () {},
                        ),
                      ),
                      Expanded(
                        child: _buildTypeButton(
                          label: 'Negocio',
                          icon: Icons.store_outlined,
                          selected: _isBusiness,
                          onTap: _pendingOwnerToken == null
                              ? () => setState(() => _isBusiness = true)
                              : () {},
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: _validateName,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Celular',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: _validatePhone,
                ),
                const SizedBox(height: 16),
                if (_isBusiness) ...[
                  TextFormField(
                    controller: _establishmentNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del establecimiento',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                    validator: (value) {
                      final error = _validateRequired(
                        value,
                        'el nombre del establecimiento',
                        100,
                      );
                      if (error != null) return error;
                      if (value!.trim().length < 2) {
                        return 'El nombre debe tener al menos 2 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _establishmentPhoneCtrl,
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
                  FormField<LatLng>(
                    key: _locationFieldKey,
                    validator: (_) => _selectedLocation == null
                        ? 'Selecciona la ubicación del establecimiento'
                        : !_locationConfirmed
                        ? 'Confirma que el pin esté en el establecimiento'
                        : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Ubicación del establecimiento',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Busca tu ciudad o barrio y ajusta el mapa. Toca el mapa o arrastra el pin hasta la entrada de tu local. La ubicación GPS o de búsqueda es solo una sugerencia: debes confirmar que el punto sea correcto.',
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
                                textCapitalization: TextCapitalization.words,
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
                              tooltip: 'Buscar en OpenStreetMap',
                              onPressed: _isSearchingLocation
                                  ? null
                                  : _searchLocation,
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
                                : 'Sugerir mi ubicación por GPS',
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 250,
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
                                interactionOptions: const InteractionOptions(
                                  flags:
                                      InteractiveFlag.all &
                                      ~InteractiveFlag.rotate,
                                ),
                                onMapReady: () {
                                  _mapReady = true;
                                  final point = _selectedLocation;
                                  if (point != null) {
                                    _mapController.move(point, 15);
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
                            'Pin ${_locationConfirmed ? 'confirmado' : 'sugerido, pendiente de confirmar'} · '
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
                            'Toca el mapa para colocar el pin. Aún no hay una ubicación seleccionada.',
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
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordCtrl,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: _validateConfirm,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acceptTerms,
                      onChanged: (value) =>
                          setState(() => _acceptTerms = value ?? false),
                    ),
                    Expanded(
                      child: Text(
                        'Acepto los términos y condiciones y la política de privacidad.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _submit,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    _isLoading ? 'Creando cuenta...' : 'Crear cuenta',
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Ya tengo una cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
