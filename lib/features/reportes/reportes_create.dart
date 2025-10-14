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

import '../../core/supabase_service.dart';
import '../../core/geocoding_service.dart';

class ReportesCreate extends StatelessWidget {
  const ReportesCreate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear Reporte')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: ReportesCreateForm(),
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
  final _veracidadCtrl = TextEditingController();
  double? _lat;
  double? _lon;
  bool _isGeocodingAddress = false;
  bool _isFetchingLocation = false;
  Timer? _addrDebounce;
  int _geocodeSeq = 0;
  final _categorias = const <String>['Robo','Asalto','Vandalismo','Acoso','Accidente','Asesinato','Otro'];
  final _estados = const <String>['ACTIVO', 'PENDIENTE', 'CERRADO'];
  String? _categoriaSel;
  String? _estadoSel = 'ACTIVO';
  bool _isSubmitting = false;
  static const String _endpoint = 'http://127.0.0.1:8000/Reportes';
  static const String _adjuntoEndpoint = 'http://127.0.0.1:8000/Adjunto';
  String? _uploadedImageUrl;

  @override
  void dispose() {
    _addrDebounce?.cancel();
    _tituloCtrl.dispose();
    _descripcionCtrl.dispose();
    _direccionCtrl.dispose();
    _veracidadCtrl.dispose();
    super.dispose();
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

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  String? _optPercent(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número (0–100)';
    if (n < 0 || n > 100) return 'Debe estar entre 0 y 100';
    return null;
  }

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
        });
      } else {
        setState(() {
          _lat = null;
          _lon = null;
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
        });
      }
    } finally {
      if (mounted) setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _pickAndUploadImageWeb() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    // En Web, image.path puede no tener extensión (p.ej., 'blob'), usar image.name.
  String ext;
  final mimeHint = image.mimeType; // e.g., image/png, image/jpeg
    if (image.name.contains('.')) {
      ext = image.name.split('.').last.toLowerCase();
    } else {
      // fallback seguro para inline render
      ext = 'jpeg';
    }
    final bytes = await image.readAsBytes();
    // Si el mimeType viene del picker, úsalo para forzar content-type correcto
    // Prefer a valid image/* mime; if missing or octet-stream, compute from extension
    String? finalMime = mimeHint;
    if (finalMime == null || finalMime.isEmpty || finalMime == 'application/octet-stream' || !finalMime.startsWith('image/')) {
      finalMime = _mimeFromExt(ext);
    }
    await _uploadBytes(bytes, ext, originalName: image.name, overrideMime: finalMime);
  }

  Future<void> _pickAndUploadImageMobile() async {
    final picker = ImagePicker();
    // imageQuality fuerza re-encoding a JPEG en iOS/Android, evitando HEIC/HEIF
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (pickedFile == null) return;
    // Al comprimir (imageQuality) normalmente obtenemos JPEG; forzamos a JPG para servir inline
    String ext = 'jpg';
    final bytes = await File(pickedFile.path).readAsBytes();
    await _uploadBytes(bytes, ext, originalName: pickedFile.name, overrideMime: 'image/jpeg');
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

  Future<void> _uploadBytes(Uint8List bytes, String ext, {String? originalName, String? overrideMime}) async {
    // Opción B: RLS para anónimos en carpeta public/PostImages
  final ts = DateTime.now().microsecondsSinceEpoch;
    final sanitized = (originalName ?? 'image').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    // Asegurar extensión acorde al 'ext' provisto (evita .heic que el browser no muestra)
    final dot = sanitized.lastIndexOf('.');
    final base = dot > 0 ? sanitized.substring(0, dot) : sanitized;
    final fileName = '${ts}_$base.$ext';
    final path = 'public/PostImages/$fileName';
    final mime = overrideMime != null && overrideMime.isNotEmpty ? overrideMime : _mimeFromExt(ext);
    try {
      await Supabase.instance.client.storage.from('adjuntos').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: mime,
        ),
      );
      var imageUrl = Supabase.instance.client.storage.from('adjuntos').getPublicUrl(path);
      imageUrl = Uri.parse(imageUrl)
          .replace(queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()}).toString();
      if (!mounted) return;
      setState(() => _uploadedImageUrl = imageUrl);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Imagen subida correctamente')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo subir la imagen: ${e.toString()}')),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona una categoría')));
      return;
    }
    if (_estadoSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona un estado')));
      return;
    }
    if (_lat == null || _lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Espera a que se geocodifique la dirección')));
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final currentUserId = GetIt.instance<SupabaseService>().backendUserId;
      if (currentUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay usuario autenticado.')));
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
        "estado": _estadoSel,
        "veracidad_porcentaje": _veracidadCtrl.text.trim().isEmpty ? null : double.parse(_veracidadCtrl.text.trim().replaceAll(',', '.')),
      };
      final res = await http.post(
        Uri.parse(_endpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Paso 4: si hay imagen subida, registrar adjunto en backend
        try {
          final created = jsonDecode(res.body);
          final reporteId = created is Map ? created['id'] as int? : null;
          if (reporteId != null && _uploadedImageUrl != null) {
            final adjPayload = {
              'reporte_id': reporteId,
              'url': _uploadedImageUrl,
              'tipo': 'image',
            };
            final adjRes = await http.post(
              Uri.parse(_adjuntoEndpoint),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(adjPayload),
            );
            if (adjRes.statusCode < 200 || adjRes.statusCode >= 300) {
              // No bloquear el flujo si falla, solo avisar
              String msg = 'Adjunto no registrado (HTTP ${adjRes.statusCode})';
              try {
                final body = jsonDecode(adjRes.body);
                if (body is Map && body['detail'] != null) msg = body['detail'].toString();
              } catch (_) {}
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
            }
          }
        } catch (e) {
          // Continuar aunque falle el registro del adjunto
          debugPrint('Fallo al registrar adjunto: $e');
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reporte creado con éxito ✅')));
        setState(() {
          _formKey.currentState!.reset();
          _categoriaSel = null;
          _estadoSel = 'ACTIVO';
          _tituloCtrl.clear();
          _descripcionCtrl.clear();
          _direccionCtrl.clear();
          _veracidadCtrl.clear();
          _lat = null;
          _lon = null;
          _uploadedImageUrl = null;
        });
        widget.onSuccess?.call();
        if (mounted) Navigator.of(context).maybePop();
      } else {
        String msg = 'Error ${res.statusCode} al crear el reporte';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['detail'] != null) {
            msg = body['detail'].toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo conectar con el servidor: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Eliminado: no se usa registro de adjuntos por backend en este flujo

  @override
  Widget build(BuildContext context) {
    const spacing = 12.0;
    final svc = GetIt.instance<SupabaseService>();
    final descUser = svc.backendUsername ?? 'Usuario #${svc.backendUserId ?? '?'}';
      return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline),
                const SizedBox(width: 8),
                Text('Reportará: $descUser'),
              ],
            ),
            const SizedBox(height: spacing),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _estadoSel,
                    decoration: _dec('Estado'),
                    items: _estados.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _estadoSel = v),
                    validator: (v) => v == null ? 'Campo obligatorio' : null,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
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
              label: const Text('Adjuntar imagen'),
              onPressed: kIsWeb ? _pickAndUploadImageWeb : _pickAndUploadImageMobile,
            ),
            if (_uploadedImageUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Image.network(_uploadedImageUrl!, height: 120),
              ),
            const SizedBox(height: spacing),
            DropdownButtonFormField<String>(
              value: _categoriaSel,
              decoration: _dec('Categoría'),
              items: _categorias.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
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
                            icon: Icon(_isFetchingLocation ? Icons.location_searching : Icons.my_location),
                            onPressed: _isFetchingLocation ? null : _useCurrentLocation,
                            tooltip: 'Usar mi ubicación',
                          ),
                  ),
                  onChanged: (_) => _scheduleGeocode(),
                );
              },
                itemBuilder: (context, String suggestion) => ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(suggestion, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ubicación: ${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
              const SizedBox(height: spacing),
            TextFormField(
              controller: _veracidadCtrl,
              decoration: _dec('Veracidad (%) - Opcional', hint: '0 a 100'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: _optPercent,
            ),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}