// lib/features/reportes/reporte_detalle_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:get_it/get_it.dart';
import '../../core/api_client.dart';
import '../../core/env.dart';
import '../../core/supabase_service.dart';

class ReporteDetallePage extends StatefulWidget {
  final int reporteId;
  final ApiClient api;

  const ReporteDetallePage({
    super.key,
    required this.reporteId,
    required this.api,
  });

  @override
  _ReporteDetallePageState createState() => _ReporteDetallePageState();
}

class _ReporteDetallePageState extends State<ReporteDetallePage> {
  bool _loading = true;
  String? _errorMessage;
  
  // Datos del reporte
  Map<String, dynamic>? _reporte;
  String? _userName;
  List<String> _imagenes = [];
  List<Map<String, dynamic>> _comentarios = [];
  
  // Reacciones
  int _upvotes = 0;
  int _downvotes = 0;
  String? _userReactionTipo;
  int? _userReactionId;

  @override
  void initState() {
    super.initState();
    _loadReporteDetalle();
  }

  Future<void> _loadReporteDetalle() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final base = Env.apiBaseUrl;
      final currentUserId = GetIt.instance<SupabaseService>().backendUserId;

      // 1. Obtener el reporte
      final reporteRes = await http.get(
        Uri.parse('$base/Reportes/${widget.reporteId}'),
      );

      if (reporteRes.statusCode != 200) {
        throw Exception('No se pudo cargar el reporte');
      }

      final reporte = jsonDecode(reporteRes.body) as Map<String, dynamic>;

      // 2. Obtener el nombre del usuario
      String userName = 'Usuario';
      try {
        final userId = reporte['user_id'] as int?;
        if (userId != null) {
          final userRes = await http.get(Uri.parse('$base/users/$userId'));
          if (userRes.statusCode == 200) {
            final userData = jsonDecode(userRes.body);
            userName = userData['user']?.toString() ?? 'Usuario $userId';
          }
        }
      } catch (_) {}

      // 3. Obtener adjuntos (imágenes)
      List<String> imagenes = [];
      try {
        final adjRes = await http.get(
          Uri.parse('$base/Adjunto/reporte/${widget.reporteId}'),
        );
        if (adjRes.statusCode == 200) {
          final adjuntos = jsonDecode(adjRes.body) as List<dynamic>;
          for (final adj in adjuntos) {
            if (adj is Map<String, dynamic> && adj['url'] != null) {
              final url = adj['url'].toString();
              final tipo = adj['tipo']?.toString().toLowerCase();
              const tiposValidos = {'foto', 'imagen', 'image', 'img', 'picture', 'photo'};
              const exts = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg'];
              final looksLikeImage = exts.any((e) => url.toLowerCase().contains(e));
              
              if ((tipo != null && tiposValidos.contains(tipo)) || looksLikeImage) {
                imagenes.add(url);
              }
            }
          }
        }
      } catch (_) {}

      // 4. Obtener comentarios
      List<Map<String, dynamic>> comentarios = [];
      try {
        final comRes = await http.get(
          Uri.parse('$base/Comentarios/reporte/${widget.reporteId}'),
        );
        if (comRes.statusCode == 200) {
          final comList = jsonDecode(comRes.body) as List<dynamic>;
          comentarios = comList.cast<Map<String, dynamic>>();
          
          // Obtener nombres de usuarios de comentarios
          for (var com in comentarios) {
            try {
              final userId = com['user_id'] as int?;
              if (userId != null) {
                final userRes = await http.get(Uri.parse('$base/users/$userId'));
                if (userRes.statusCode == 200) {
                  final userData = jsonDecode(userRes.body);
                  com['user_name'] = userData['user']?.toString() ?? 'Usuario $userId';
                }
              }
            } catch (_) {
              com['user_name'] = 'Usuario';
            }
          }
        }
      } catch (_) {}

      // 5. Obtener reacciones del usuario actual
      String? userReactionTipo;
      int? userReactionId;
      if (currentUserId != null) {
        try {
          final reacRes = await http.get(
            Uri.parse('$base/Reacciones/user/$currentUserId'),
          );
          if (reacRes.statusCode == 200) {
            final reacciones = jsonDecode(reacRes.body) as List<dynamic>;
            for (final reac in reacciones) {
              if (reac is Map<String, dynamic> &&
                  reac['reporte_id'] == widget.reporteId) {
                userReactionTipo = reac['tipo']?.toString().toLowerCase();
                userReactionId = reac['id'] as int?;
                break;
              }
            }
          }
        } catch (_) {}
      }

      setState(() {
        _reporte = reporte;
        _userName = userName;
        _imagenes = imagenes;
        _comentarios = comentarios;
        _upvotes = (reporte['cantidad_upvotes'] as int?) ?? 0;
        _downvotes = (reporte['cantidad_downvotes'] as int?) ?? 0;
        _userReactionTipo = userReactionTipo;
        _userReactionId = userReactionId;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleReaction(String tipo) async {
    final currentUserId = GetIt.instance<SupabaseService>().backendUserId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión para reaccionar')),
      );
      return;
    }

    final base = Env.apiBaseUrl;

    try {
      // Si ya existe la misma reacción, eliminarla
      if (_userReactionTipo == tipo && _userReactionId != null) {
        await http.delete(Uri.parse('$base/Reacciones/$_userReactionId'));
        setState(() {
          if (tipo == 'upvote') {
            _upvotes--;
          } else {
            _downvotes--;
          }
          _userReactionTipo = null;
          _userReactionId = null;
        });
      } 
      // Si existe otra reacción, actualizarla
      else if (_userReactionTipo != null && _userReactionId != null) {
        final oldTipo = _userReactionTipo;
        await http.patch(
          Uri.parse('$base/Reacciones/$_userReactionId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'tipo': tipo}),
        );
        setState(() {
          if (oldTipo == 'upvote') {
            _upvotes--;
          } else {
            _downvotes--;
          }
          if (tipo == 'upvote') {
            _upvotes++;
          } else {
            _downvotes++;
          }
          _userReactionTipo = tipo;
        });
      } 
      // Si no existe, crear nueva
      else {
        final res = await http.post(
          Uri.parse('$base/Reacciones'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': currentUserId,
            'reporte_id': widget.reporteId,
            'tipo': tipo,
          }),
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          final data = jsonDecode(res.body);
          setState(() {
            if (tipo == 'upvote') {
              _upvotes++;
            } else {
              _downvotes++;
            }
            _userReactionTipo = tipo;
            _userReactionId = data['id'] as int?;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar reacción: $e')),
      );
    }
  }

  Widget _buildImageGallery() {
    if (_imagenes.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _imagenes.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _imagenes[index],
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image, size: 48),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMap() {
    final lat = _reporte?['lat'];
    final lon = _reporte?['lon'];

    if (lat == null || lon == null) return const SizedBox.shrink();

    final position = LatLng(
      (lat as num).toDouble(),
      (lon as num).toDouble(),
    );

    return Container(
      height: 200,
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: position,
            zoom: 15,
          ),
          markers: {
            Marker(
              markerId: MarkerId('reporte-${widget.reporteId}'),
              position: position,
            ),
          },
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E2D52),
      appBar: AppBar(
        title: const Text('Detalle del Reporte'),
        backgroundColor: const Color(0xFF08192D),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadReporteDetalle,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Card principal del reporte
                      Card(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Usuario y categoría
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.blue[100],
                                    child: Text(
                                      _userName?.substring(0, 1).toUpperCase() ?? 'U',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _userName ?? 'Usuario',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          _reporte?['categoria'] ?? '',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Badge de estado
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getEstadoColor(
                                        _reporte?['estado'] ?? '',
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _reporte?['estado'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              // Título
                              Text(
                                _reporte?['titulo'] ?? '',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              
                              // Descripción
                              Text(
                                _reporte?['descripcion'] ?? '',
                                style: TextStyle(
                                  color: Colors.grey[800],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // Dirección
                              if (_reporte?['direccion'] != null &&
                                  _reporte!['direccion'].toString().isNotEmpty)
                                Row(
                                  children: [
                                    Icon(Icons.location_on,
                                        size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _reporte!['direccion'].toString(),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 16),
                              
                              // Galería de imágenes
                              _buildImageGallery(),
                              
                              // Mapa
                              _buildMap(),
                              
                              const Divider(),
                              
                              // Reacciones
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildReactionButton(
                                    icon: Icons.thumb_up,
                                    count: _upvotes,
                                    tipo: 'upvote',
                                    isActive: _userReactionTipo == 'upvote',
                                  ),
                                  _buildReactionButton(
                                    icon: Icons.thumb_down,
                                    count: _downvotes,
                                    tipo: 'downvote',
                                    isActive: _userReactionTipo == 'downvote',
                                  ),
                                  _buildInfoChip(
                                    icon: Icons.comment,
                                    label: '${_comentarios.length}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Sección de comentarios
                      const Text(
                        'Comentarios',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      if (_comentarios.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                'No hay comentarios aún',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          ),
                        )
                      else
                        ..._comentarios.map((com) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue[100],
                                  child: Text(
                                    com['user_name']
                                            ?.toString()
                                            .substring(0, 1)
                                            .toUpperCase() ??
                                        'U',
                                  ),
                                ),
                                title: Text(
                                  com['user_name']?.toString() ?? 'Usuario',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  com['mensaje']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _buildReactionButton({
    required IconData icon,
    required int count,
    required String tipo,
    required bool isActive,
  }) {
    return InkWell(
      onTap: () => _toggleReaction(tipo),
      child: Row(
        children: [
          Icon(
            icon,
            color: isActive ? Colors.blue : Colors.grey[600],
            size: 20,
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              color: isActive ? Colors.blue : Colors.grey[600],
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey[600], size: 20),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Color _getEstadoColor(String estado) {
    switch (estado.toLowerCase()) {
      case 'pendiente':
        return Colors.orange;
      case 'verificado':
        return Colors.green;
      case 'rechazado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
