// lib/features/reportes/reportes_create.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:get_it/get_it.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

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

  // Controllers
  final _tituloCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _veracidadCtrl = TextEditingController();

  // Coordenadas (se llenan automáticamente)
  double? _lat;
  double? _lon;
  bool _isGeocodingAddress = false;
  bool _isFetchingLocation = false;

  // Autocomplete/debounce
  Timer? _addrDebounce;
  int _geocodeSeq = 0;

  // Dropdowns
  final _categorias = const <String>[
    'Robo',
    'Asalto',
    'Vandalismo',
    'Acoso',
    'Accidente',
    'Asesinato',
    'Otro',
  ];
  final _estados = const <String>['ACTIVO', 'PENDIENTE', 'CERRADO'];

  String? _categoriaSel;
  String? _estadoSel = 'ACTIVO';

  bool _isSubmitting = false;

  static const String _endpoint = 'http://127.0.0.1:8000/Reportes';

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

  /// Geocodifica la dirección actual del campo (sin SnackBars)
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
    final myReq = ++_geocodeSeq; // descarta respuestas viejas

    try {
      final result = await _geocodingService.getCoordinatesFromAddress(address);

      if (!mounted || myReq != _geocodeSeq) return;

      if (result != null) {
        setState(() {
          _lat = result.latitude;
          _lon = result.longitude;
          // Opcional: normalizar texto mostrado
          // _direccionCtrl.text = result.formattedAddress;
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

  /// Obtiene la ubicación actual (sin SnackBars)
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una categoría')),
      );
      return;
    }
    if (_estadoSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un estado')),
      );
      return;
    }
    if (_lat == null || _lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Espera a que se geocodifique la dirección')),
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
        "estado": _estadoSel,
        "veracidad_porcentaje": _veracidadCtrl.text.trim().isEmpty
            ? null
            : double.parse(_veracidadCtrl.text.trim().replaceAll(',', '.')),
      };

      final res = await http.post(
        Uri.parse(_endpoint),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reporte creado con éxito ✅')),
        );
        _formKey.currentState!.reset();
        _categoriaSel = null;
        _estadoSel = 'ACTIVO';
        _tituloCtrl.clear();
        _descripcionCtrl.clear();
        _direccionCtrl.clear();
        _veracidadCtrl.clear();
        _lat = null;
        _lon = null;
        setState(() {});
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo conectar con el servidor: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

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
              decoration: _dec('Título', hint: 'Ej. ASALTO EN CASA DE MILEÑE'),
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
                if (q.length < 3) return const <String>[];   // 👈 mínimo 3 chars
                return await _geocodingService.searchAddresses(q);
              },

              // Construye el TextFormField que participa en tu Form
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
                await _onAddressChanged();       // geocodifica la seleccionada
                FocusScope.of(context).unfocus(); // cierra teclado
              },

              // Ayudas visuales para depurar
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

            // MOSTRAR COORDENADAS (SOLO VISUAL)
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
