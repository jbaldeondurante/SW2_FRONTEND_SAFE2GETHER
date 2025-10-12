import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:get_it/get_it.dart';
import '../../core/supabase_service.dart';

// Página completa (con AppBar) que reutiliza el formulario embebible
class ReportesCreate extends StatelessWidget {
  const ReportesCreate({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Reporte'),
      ),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: ReportesCreateForm(),
      ),
    );
  }
}

// Form embebible para usar como popup o dentro de una página
class ReportesCreateForm extends StatefulWidget {
  final VoidCallback? onSuccess;
  const ReportesCreateForm({Key? key, this.onSuccess}) : super(key: key);

  @override
  State<ReportesCreateForm> createState() => _ReportesCreateFormState();
}

class _ReportesCreateFormState extends State<ReportesCreateForm> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _tituloCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _veracidadCtrl = TextEditingController(); // opcional

  // Dropdowns
  final _categorias = const <String>[
    'Robo',
    'Asalto',
    'Vandalismo',
    'Acoso',
    'Accidente',
    'Asesinato', // tal cual tu sample
    'Otro',
  ];
  final _estados = const <String>['ACTIVO', 'PENDIENTE', 'CERRADO'];

  String? _categoriaSel;
  String? _estadoSel = 'ACTIVO';

  bool _isSubmitting = false;

  // URL de tu API
  static const String _endpoint = 'http://127.0.0.1:8000/Reportes';

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descripcionCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
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

  // _reqInt eliminado: ya no se ingresa user_id manualmente.

  String? _reqDouble(String? v) {
    if (v == null || v.trim().isEmpty) return 'Campo obligatorio';
    final n = double.tryParse(v.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número (usa punto decimal)';
    return null;
  }

  String? _optPercent(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v.trim().replaceAll(',', '.'));
    if (n == null) return 'Debe ser un número (0–100)';
    if (n < 0 || n > 100) return 'Debe estar entre 0 y 100';
    return null;
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
        "lat": double.parse(_latCtrl.text.trim().replaceAll(',', '.')),
        "lon": double.parse(_lonCtrl.text.trim().replaceAll(',', '.')),
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
        // Limpia el formulario
        _formKey.currentState!.reset();
        _categoriaSel = null;
        _estadoSel = 'ACTIVO';
        _tituloCtrl.clear();
        _descripcionCtrl.clear();
        _latCtrl.clear();
        _lonCtrl.clear();
        _direccionCtrl.clear();
        _veracidadCtrl.clear();
        setState(() {});
        // Notifica éxito al padre (si está embebido en un popup)
        try {
          widget.onSuccess?.call();
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      } else {
        // Muestra el error de la API si existe
        String msg = 'Error ${res.statusCode} al crear el reporte';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['detail'] != null) {
            msg = body['detail'].toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
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
                    items: _estados
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _estadoSel = v),
                    validator: (v) => v == null ? 'Campo obligatorio' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: SizedBox.shrink()),
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
              items: _categorias
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _categoriaSel = v),
              validator: (v) => v == null ? 'Campo obligatorio' : null,
            ),
            const SizedBox(height: spacing),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    decoration: _dec('Latitud', hint: '-12.056'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    validator: _reqDouble,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lonCtrl,
                    decoration: _dec('Longitud', hint: '-77.084'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    validator: _reqDouble,
                  ),
                ),
              ],
            ),
            const SizedBox(height: spacing),
            TextFormField(
              controller: _direccionCtrl,
              decoration: _dec('Dirección', hint: 'Ej. LAMOLINGA'),
              validator: _req,
              textCapitalization: TextCapitalization.words,
            ),
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
