import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';
import '../../core/api_client.dart';
import '../../core/responsive_utils.dart';

class AreasInteresPage extends StatefulWidget {
  final ApiClient api;
  final int userId;

  const AreasInteresPage({
    super.key,
    required this.api,
    required this.userId,
  });

  @override
  State<AreasInteresPage> createState() => _AreasInteresPageState();
}

class _AreasInteresPageState extends State<AreasInteresPage> {
  List<dynamic> _areas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getJson('/AreasInteres/user/${widget.userId}');
      if (res['status'] < 400) {
        final data = res['data'];
        setState(() {
          _areas = data is List ? data : [];
          _loading = false;
        });
      } else {
        throw Exception('Error ${res['status']}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar áreas: $e')),
        );
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteArea(int areaId) async {
    try {
      final res = await widget.api.deleteJson('/AreasInteres/$areaId');
      if (res['status'] >= 400) {
        throw Exception('Error al eliminar');
      }
      await _loadAreas();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Área eliminada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      builder: (context) => _AreaDialog(
        api: widget.api,
        userId: widget.userId,
        onSaved: _loadAreas,
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> area) {
    showDialog(
      context: context,
      builder: (context) => _AreaDialog(
        api: widget.api,
        userId: widget.userId,
        area: area,
        onSaved: _loadAreas,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveHelper.getPadding(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF0E2D52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08192D),
        foregroundColor: Colors.white,
        title: const Text('Mis Áreas de Interés'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _areas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_off, size: 64, color: Colors.white54),
                      const SizedBox(height: 16),
                      const Text(
                        'No tienes áreas de interés',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Agrega una para recibir alertas',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: padding,
                  itemCount: _areas.length,
                  itemBuilder: (context, index) {
                    final area = _areas[index];
                    final activo = area['activo'] == true;
                    final frecuencia = area['frecuencia_notificacion'] ?? 'semanal';
                    
                    return Card(
                      color: const Color(0xFF0C2542),
                      margin: EdgeInsets.only(bottom: ResponsiveHelper.getVerticalSpacing(context) * 0.75),
                      child: ListTile(
                        leading: Icon(
                          activo ? Icons.notifications_active : Icons.notifications_off,
                          color: activo ? Colors.green : Colors.grey,
                        ),
                        title: Text(
                          area['nombre'] ?? 'Sin nombre',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Radio: ${area['radio_metros'] ?? 1000}m',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Text(
                              'Frecuencia: ${frecuencia == "diario" ? "📅 Diaria" : "📆 Semanal"}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Text(
                              activo ? '✅ Activo' : '❌ Inactivo',
                              style: TextStyle(color: activo ? Colors.green : Colors.grey),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white70),
                              onPressed: () => _showEditDialog(area),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Confirmar'),
                                    content: const Text('¿Eliminar esta área?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Eliminar'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  _deleteArea(area['id']);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: const Color(0xFF9B080C),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _AreaDialog extends StatefulWidget {
  final ApiClient api;
  final int userId;
  final Map<String, dynamic>? area;
  final VoidCallback onSaved;

  const _AreaDialog({
    required this.api,
    required this.userId,
    this.area,
    required this.onSaved,
  });

  @override
  State<_AreaDialog> createState() => _AreaDialogState();
}

class _AreaDialogState extends State<_AreaDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreCtrl;
  late double _lat;
  late double _lon;
  late String _frecuencia;
  late bool _activo;
  bool _saving = false;
  static const int _radioMetros = 500; // Radio fijo de 500 metros

  @override
  void initState() {
    super.initState();
    final area = widget.area;
    _nombreCtrl = TextEditingController(text: area?['nombre'] ?? '');
    _lat = area?['lat']?.toDouble() ?? -12.0464;
    _lon = area?['lon']?.toDouble() ?? -77.0428;
    _frecuencia = area?['frecuencia_notificacion'] ?? 'semanal';
    _activo = area?['activo'] ?? true;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final payload = {
        'user_id': widget.userId,
        'nombre': _nombreCtrl.text.trim(),
        'lat': _lat,
        'lon': _lon,
        'radio_metros': _radioMetros,
        'frecuencia_notificacion': _frecuencia,
        'activo': _activo,
      };

      final isEdit = widget.area != null;
      final res = isEdit
          ? await widget.api.patchJson(
              '/AreasInteres/${widget.area!['id']}',
              payload,
            )
          : await widget.api.postJson('/AreasInteres', payload);

      if (res['status'] >= 400) {
        throw Exception('Error ${res['status']}');
      }

      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'Área actualizada' : 'Área creada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _pickLocation() {
    showDialog(
      context: context,
      builder: (context) => _MapPicker(
        initialLat: _lat,
        initialLon: _lon,
        onLocationPicked: (lat, lon) {
          setState(() {
            _lat = lat;
            _lon = lon;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.area == null ? 'Nueva Área' : 'Editar Área'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('Ubicación: ${_lat.toStringAsFixed(4)}, ${_lon.toStringAsFixed(4)}'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.map),
                    onPressed: _pickLocation,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Radio de monitoreo: $_radioMetros metros',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _frecuencia,
                decoration: const InputDecoration(labelText: 'Frecuencia'),
                items: const [
                  DropdownMenuItem(value: 'diario', child: Text('📅 Diaria')),
                  DropdownMenuItem(value: 'semanal', child: Text('📆 Semanal')),
                ],
                onChanged: (v) => setState(() => _frecuencia = v!),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Activo'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _MapPicker extends StatefulWidget {
  final double initialLat;
  final double initialLon;
  final Function(double, double) onLocationPicked;

  const _MapPicker({
    required this.initialLat,
    required this.initialLon,
    required this.onLocationPicked,
  });

  @override
  State<_MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<_MapPicker> {
  late LatLng _selectedLocation;

  @override
  void initState() {
    super.initState();
    _selectedLocation = LatLng(widget.initialLat, widget.initialLon);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            AppBar(
              title: const Text('Seleccionar Ubicación'),
              automaticallyImplyLeading: false,
            ),
            Expanded(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _selectedLocation,
                  zoom: 14,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('selected'),
                    position: _selectedLocation,
                  ),
                },
                onTap: (pos) => setState(() => _selectedLocation = pos),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      widget.onLocationPicked(_selectedLocation.latitude, _selectedLocation.longitude);
                      Navigator.pop(context);
                    },
                    child: const Text('Seleccionar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
