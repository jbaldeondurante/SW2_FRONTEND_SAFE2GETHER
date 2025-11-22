// lib/features/reportes/reportes_create.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:get_it/get_it.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/supabase_service.dart';
import '../../core/geocoding_service.dart';
import '../../core/env.dart';

class ReportesCreate extends StatelessWidget {
  const ReportesCreate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear Reporte')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: const ReportesCreateForm(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ReportesCreateForm extends StatefulWidget {
  final VoidCallback? onSuccess;
  const ReportesCreateForm({Key? key, this.onSuccess}) : super(key: key);

  @override
  State<ReportesCreateForm> createState() => _ReportesCreateFormState();
}

class _ReportesCreateFormState extends State<ReportesCreateForm> {
  final _formKey = GlobalKey<FormState>();
  final _geocodingService = GeocodingService();
  final _tituloCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  double? _lat;
  double? _lon;
  bool _isGeocodingAddress = false;
  bool _isFetchingLocation = false;
  Timer? _addrDebounce;
  int _geocodeSeq = 0;
  final _categorias = const <String>[
    'Robo',
    'Asalto',
    'Vandalismo',
    'Acoso',
    'Accidente',
    'Asesinato',
    'Otro',
  ];
  String? _categoriaSel;
  bool _isSubmitting = false;
  late final String _base;
  final List<String> _uploadedImageUrls = [];
  bool _isUploadingImages = false;
  
  // Variables para el mapa interactivo
  GoogleMapController? _mapController;
  bool _showMap = false;
  LatLng? _markerPosition;
  bool _isReverseGeocoding = false;

  @override
  void dispose() {
    _addrDebounce?.cancel();
    _mapController?.dispose();
    _tituloCtrl.dispose();
    _descripcionCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _base = Env.apiBaseUrl;
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      suffixIcon: suffix,
    );
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  void _scheduleGeocode() {
    _addrDebounce?.cancel();
    _addrDebounce = Timer(const Duration(milliseconds: 300), () {
      final txt = _direccionCtrl.text.trim();
      if (txt.length > 3) _onAddressChanged();
    });
  }

  Future<void> _onAddressChanged() async {
    final address = _direccionCtrl.text.trim();
    if (address.isEmpty) {
      setState(() {
        _lat = null;
        _lon = null;
        _markerPosition = null;
      });
      return;
    }
    setState(() => _isGeocodingAddress = true);
    final myReq = ++_geocodeSeq;
    try {
      final result = await _geocodingService.getCoordinatesFromAddress(address);
      if (!mounted || myReq != _geocodeSeq) return;
      if (result != null) {
        setState(() {
          _lat = result.latitude;
          _lon = result.longitude;
          _markerPosition = LatLng(_lat!, _lon!);
        });
        // Si el mapa está visible, mover la cámara al nuevo marcador
        if (_showMap && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(_markerPosition!),
          );
        }
      } else {
        setState(() {
          _lat = null;
          _lon = null;
          _markerPosition = null;
        });
      }
    } finally {
      if (mounted) setState(() => _isGeocodingAddress = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isFetchingLocation = true);
    try {
      final result = await _geocodingService.getCurrentLocation();
      if (result != null && mounted) {
        setState(() {
          _lat = result.latitude;
          _lon = result.longitude;
          _direccionCtrl.text = result.formattedAddress;
          _markerPosition = LatLng(_lat!, _lon!);
        });
        // Si el mapa está visible, mover la cámara
        if (_showMap && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(_markerPosition!),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  // Método para actualizar la posición desde el mapa
  Future<void> _onMarkerDragEnd(LatLng newPosition) async {
    setState(() {
      _markerPosition = newPosition;
      _lat = newPosition.latitude;
      _lon = newPosition.longitude;
      _isReverseGeocoding = true;
    });

    try {
      // Reverse geocoding: obtener dirección desde coordenadas
      final address = await _geocodingService.getAddressFromCoordinates(
        newPosition.latitude,
        newPosition.longitude,
      );
      
      if (!mounted) return;
      
      setState(() {
        if (address != null && address.isNotEmpty) {
          _direccionCtrl.text = address;
        }
        _isReverseGeocoding = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isReverseGeocoding = false);
      }
      debugPrint('Error en reverse geocoding: $e');
    }
  }

  // Método para abrir/cerrar el selector de mapa
  void _toggleMapSelector() {
    setState(() {
      _showMap = !_showMap;
      // Si se abre el mapa y ya hay coordenadas, posicionar el marcador
      if (_showMap && _lat != null && _lon != null) {
        _markerPosition = LatLng(_lat!, _lon!);
      }
    });
  }

  Future<void> _pickAndUploadImagesWeb() async {
    setState(() => _isUploadingImages = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
      );
      if (result == null || result.files.isEmpty) return;
      // Limitar a 10 para evitar cargas enormes
      final files = result.files.take(10 - _uploadedImageUrls.length);
      for (final f in files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        final name = f.name;
        final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpeg';
        final mime = _mimeFromExt(ext);
        final url = await _uploadBytes(bytes, ext, originalName: name, overrideMime: mime);
        if (!mounted) return;
        if (url != null) {
          setState(() => _uploadedImageUrls.add(url));
        }
      }
      if (mounted && files.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_uploadedImageUrls.length} imagen(es) listas')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron seleccionar imágenes: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingImages = false);
    }
  }

  Future<void> _pickAndUploadImagesMobile() async {
    setState(() => _isUploadingImages = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(imageQuality: 90);
      if (picked.isEmpty) return;
      final slots = 10 - _uploadedImageUrls.length;
      for (final x in picked.take(slots)) {
        final bytes = await File(x.path).readAsBytes();
        final url = await _uploadBytes(bytes, 'jpg', originalName: x.name, overrideMime: 'image/jpeg');
        if (!mounted) return;
        if (url != null) {
          setState(() => _uploadedImageUrls.add(url));
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_uploadedImageUrls.length} imagen(es) listas')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron seleccionar imágenes: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingImages = false);
    }
  }

  String _mimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'jpe':
      case 'jfif':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        // fallback a imagen para evitar descarga como archivo
        return 'image/jpeg';
    }
  }

  Future<String?> _uploadBytes(
    Uint8List bytes,
    String ext, {
    String? originalName,
    String? overrideMime,
  }) async {
    // Opción B: RLS para anónimos en carpeta public/PostImages
    final ts = DateTime.now().microsecondsSinceEpoch;
    final sanitized = (originalName ?? 'image').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    // Asegurar extensión acorde al 'ext' provisto (evita .heic que el browser no muestra)
    final dot = sanitized.lastIndexOf('.');
    final base = dot > 0 ? sanitized.substring(0, dot) : sanitized;
    final fileName = '${ts}_$base.$ext';
    final path = 'public/PostImages/$fileName';
    final mime = overrideMime != null && overrideMime.isNotEmpty
        ? overrideMime
        : _mimeFromExt(ext);
    try {
      await Supabase.instance.client.storage
          .from('adjuntos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: mime),
          );
      var imageUrl = Supabase.instance.client.storage
          .from('adjuntos')
          .getPublicUrl(path);
      imageUrl = Uri.parse(imageUrl)
          .replace(
            queryParameters: {
              't': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          )
          .toString();
      return imageUrl;
    } catch (e) {
      // Log y continuar; el caller mostrará feedback general
      debugPrint('Error subiendo imagen: $e');
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaSel == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona una categoría')));
      return;
    }
    if (_lat == null || _lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Espera a que se geocodifique la dirección'),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final currentUserId = GetIt.instance<SupabaseService>().backendUserId;
      if (currentUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay usuario autenticado.')),
        );
        return;
      }
      final payload = {
        "user_id": currentUserId,
        "titulo": _tituloCtrl.text.trim(),
        "descripcion": _descripcionCtrl.text.trim(),
        "categoria": _categoriaSel,
        "lat": _lat,
        "lon": _lon,
        "direccion": _direccionCtrl.text.trim(),
        "cantidad_upvotes": 0,
        "cantidad_downvotes": 0,
      };
      final res = await http.post(
        Uri.parse('$_base/Reportes'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Parsear respuesta para obtener el ID del reporte creado
        final created = jsonDecode(res.body);
        final reporteId = created is Map ? created['id'] as int? : null;

        // Paso 4: si hay imágenes subidas, registrar adjuntos en backend
        if (reporteId != null && _uploadedImageUrls.isNotEmpty) {
          for (final url in _uploadedImageUrls) {
            try {
              final adjPayload = {
                'reporte_id': reporteId,
                'url': url,
                'tipo': 'image',
              };
              final adjRes = await http.post(
                Uri.parse('$_base/Adjunto'),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode(adjPayload),
              );
              if (adjRes.statusCode < 200 || adjRes.statusCode >= 300) {
                debugPrint('Adjunto no registrado (HTTP ${adjRes.statusCode})');
              }
            } catch (e) {
              debugPrint('Error registrando adjunto: $e');
            }
          }
        }
        // Mostrar ventana emergente de confirmación con número de reporte y resumen
        if (mounted) {
          final titulo = _tituloCtrl.text.trim();
          final categoria = _categoriaSel ?? '-';
          final direccion = _direccionCtrl.text.trim();
          final coords = (_lat != null && _lon != null)
              ? '(${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)})'
              : null;
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Reporte registrado'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reporteId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'N° de reporte: #$reporteId',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  Text('Título: $titulo'),
                  Text('Categoría: $categoria'),
                  if (direccion.isNotEmpty) Text('Dirección: $direccion'),
                  if (coords != null) Text('Ubicación: $coords'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
          );
        }
        setState(() {
          _formKey.currentState!.reset();
          _categoriaSel = null;
          _tituloCtrl.clear();
          _descripcionCtrl.clear();
          _direccionCtrl.clear();
          _lat = null;
          _lon = null;
          _uploadedImageUrls.clear();
        });
        if (mounted) Navigator.of(context).pop(true);
      } else {
        String msg = 'Error ${res.statusCode} al crear el reporte';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['detail'] != null) {
            msg = body['detail'].toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo conectar con el servidor: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Eliminado: no se usa registro de adjuntos por backend en este flujo

  @override
  Widget build(BuildContext context) {
    const spacing = 12.0;
    final svc = GetIt.instance<SupabaseService>();
    final descUser =
        svc.backendUsername ?? 'Usuario #${svc.backendUserId ?? '?'}';
    return SafeArea(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Row(
              children: [
                const Icon(Icons.person_outline),
                const SizedBox(width: 8),
                Text('Reportará: $descUser'),
              ],
            ),
            const SizedBox(height: spacing),
            // Separador inicial
            const SizedBox(height: spacing),
            TextFormField(
              controller: _tituloCtrl,
              decoration: _dec('Título', hint: 'Ej. ASALTO EN CASA DE EÑE'),
              validator: _req,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: spacing),
            TextFormField(
              controller: _descripcionCtrl,
              decoration: _dec('Descripción', hint: 'Describe lo ocurrido...'),
              validator: _req,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: Text(_isUploadingImages
                  ? 'Subiendo imágenes...'
                  : 'Adjuntar imágenes'),
              onPressed: _isUploadingImages
                  ? null
                  : (kIsWeb ? _pickAndUploadImagesWeb : _pickAndUploadImagesMobile),
            ),
            if (_uploadedImageUrls.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _uploadedImageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final url = _uploadedImageUrls[i];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              url,
                              height: 100,
                              width: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: InkWell(
                              onTap: () {
                                setState(() => _uploadedImageUrls.removeAt(i));
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: spacing),
            DropdownButtonFormField<String>(
              value: _categoriaSel,
              decoration: _dec('Categoría'),
              items: _categorias
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _categoriaSel = v),
              validator: (v) => v == null ? 'Campo obligatorio' : null,
            ),
            const SizedBox(height: spacing),
            TypeAheadField<String>(
              controller: _direccionCtrl,
              suggestionsCallback: (pattern) async {
                final q = pattern.trim();
                if (q.length < 3) return const <String>[];
                return await _geocodingService.searchAddresses(q);
              },
              builder: (context, controller, focusNode) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  validator: _req,
                  textCapitalization: TextCapitalization.words,
                  decoration: _dec(
                    'Dirección',
                    hint: 'Ej. Av. San José 263, Bellavista, Callao, Perú',
                    suffix: _isGeocodingAddress
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: Icon(
                              _isFetchingLocation
                                  ? Icons.location_searching
                                  : Icons.my_location,
                            ),
                            onPressed: _isFetchingLocation
                                ? null
                                : _useCurrentLocation,
                            tooltip: 'Usar mi ubicación',
                          ),
                  ),
                  onChanged: (_) => _scheduleGeocode(),
                );
              },
              itemBuilder: (context, String suggestion) => ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(
                  suggestion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onSelected: (String suggestion) async {
                _direccionCtrl.text = suggestion;
                await _onAddressChanged();
                FocusScope.of(context).unfocus();
              },
              loadingBuilder: (_) => const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              emptyBuilder: (_) => const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Sin sugerencias'),
              ),
              hideOnEmpty: true,
            ),
            if (_lat != null && _lon != null) ...[
              const SizedBox(height: spacing),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ubicación: ${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: spacing),
            
            // Botón para mostrar/ocultar el selector de mapa
            OutlinedButton.icon(
              onPressed: _toggleMapSelector,
              icon: Icon(_showMap ? Icons.map_outlined : Icons.map),
              label: Text(_showMap ? 'Ocultar mapa' : 'Seleccionar en mapa'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            
            // Mapa interactivo
            if (_showMap) ...[
              const SizedBox(height: spacing),
              Container(
                height: 280,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _markerPosition ?? const LatLng(-12.0464, -77.0428), // Lima por defecto
                          zoom: _markerPosition != null ? 15 : 12,
                        ),
                        markers: _markerPosition != null
                            ? {
                                Marker(
                                  markerId: const MarkerId('incident-location'),
                                  position: _markerPosition!,
                                  draggable: true,
                                  onDragEnd: _onMarkerDragEnd,
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueRed,
                                  ),
                                ),
                              }
                            : {},
                        onMapCreated: (controller) {
                          _mapController = controller;
                        },
                        onTap: (position) {
                          // Al tocar el mapa, mover el marcador allí
                          _onMarkerDragEnd(position);
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: true,
                        mapToolbarEnabled: false,
                      ),
                      // Indicador de carga durante reverse geocoding
                      if (_isReverseGeocoding)
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: Card(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(width: 16),
                                    Text('Obteniendo dirección...'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Instrucciones
                      if (!_isReverseGeocoding)
                        Positioned(
                          top: 10,
                          left: 10,
                          right: 10,
                          child: Card(
                            color: Colors.white.withOpacity(0.9),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Toca o arrastra el marcador para seleccionar la ubicación',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_isSubmitting ? 'Enviando...' : 'Crear reporte'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
