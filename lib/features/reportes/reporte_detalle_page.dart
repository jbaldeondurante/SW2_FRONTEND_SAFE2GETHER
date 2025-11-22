// lib/features/reportes/reporte_detalle_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:get_it/get_it.dart';
import '../../core/api_client.dart';
import '../../core/env.dart';
import '../../core/supabase_service.dart';
import '../../core/responsive_utils.dart';

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
  
  // Notas de comunidad
  List<Map<String, dynamic>> _notasComunidad = [];
  bool _loadingNotas = false;
  bool _postingNota = false;
  final TextEditingController _notaCtrl = TextEditingController();
  int? _editingNotaId;
  bool? _esVeraz; // null = neutral, true = veraz, false = falso

  @override
  void initState() {
    super.initState();
    _loadReporteDetalle();
  }

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
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

      // 6. Obtener notas de comunidad
      await _loadNotasComunidad();

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

  Future<void> _loadNotasComunidad() async {
    setState(() => _loadingNotas = true);
    try {
      final base = Env.apiBaseUrl;
      final notasRes = await http.get(
        Uri.parse('$base/Notas_Comunidad/reporte/${widget.reporteId}'),
      );
      
      if (notasRes.statusCode == 200) {
        final notasList = jsonDecode(notasRes.body) as List<dynamic>;
        final notas = notasList.cast<Map<String, dynamic>>();
        
        // Obtener nombres de usuarios
        for (var nota in notas) {
          try {
            final userId = nota['user_id'] as int?;
            if (userId != null) {
              final userRes = await http.get(Uri.parse('$base/users/$userId'));
              if (userRes.statusCode == 200) {
                final userData = jsonDecode(userRes.body);
                nota['user_name'] = userData['user']?.toString() ?? 'Usuario $userId';
              }
            }
          } catch (_) {
            nota['user_name'] = 'Usuario';
          }
        }
        
        setState(() => _notasComunidad = notas);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar notas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingNotas = false);
    }
  }

  Future<void> _submitNota() async {
    final currentUserId = GetIt.instance<SupabaseService>().backendUserId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión para agregar notas')),
      );
      return;
    }

    final text = _notaCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La nota no puede estar vacía')),
      );
      return;
    }

    setState(() => _postingNota = true);
    try {
      final base = Env.apiBaseUrl;
      
      if (_editingNotaId != null) {
        // Editar nota existente
        final body = {
          'nota': text,
          if (_esVeraz != null) 'es_veraz': _esVeraz,
        };
        final res = await http.patch(
          Uri.parse('$base/Notas_Comunidad/$_editingNotaId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        
        if (res.statusCode == 200) {
          setState(() {
            _notaCtrl.clear();
            _editingNotaId = null;
          });
          await _loadNotasComunidad();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Nota actualizada exitosamente')),
            );
          }
        } else {
          throw Exception('Error al actualizar nota');
        }
      } else {
        // Crear nueva nota
        final body = {
          'reporte_id': widget.reporteId,
          'user_id': currentUserId,
          'nota': text,
          if (_esVeraz != null) 'es_veraz': _esVeraz,
        };
        final res = await http.post(
          Uri.parse('$base/Notas_Comunidad'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        
        if (res.statusCode == 201) {
          setState(() => _notaCtrl.clear());
          await _loadNotasComunidad();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Nota agregada exitosamente')),
            );
          }
        } else {
          throw Exception('Error al crear nota');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _postingNota = false);
    }
  }

  Future<void> _deleteNota(int notaId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: const Text('¿Estás seguro de que deseas eliminar esta nota?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final base = Env.apiBaseUrl;
      final res = await http.delete(
        Uri.parse('$base/Notas_Comunidad/$notaId'),
      );
      
      if (res.statusCode == 200) {
        await _loadNotasComunidad();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nota eliminada exitosamente')),
          );
        }
      } else {
        throw Exception('Error al eliminar nota');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _editNota(Map<String, dynamic> nota) {
    setState(() {
      _editingNotaId = nota['id'] as int?;
      _notaCtrl.text = nota['nota']?.toString() ?? '';
      _esVeraz = nota['es_veraz'] as bool?;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingNotaId = null;
      _notaCtrl.clear();
      _esVeraz = null;
    });
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
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.getVerticalSpacing(context);
    
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
                  child: Padding(
                    padding: padding,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        SizedBox(height: spacing),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: spacing),
                        ElevatedButton(
                          onPressed: _loadReporteDetalle,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: padding,
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
                      
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white24, thickness: 2),
                      const SizedBox(height: 24),
                      
                      // Sección de Notas de Comunidad
                      Row(
                        children: [
                          const Icon(Icons.verified_user, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          const Text(
                            'Notas de Veracidad de la Comunidad',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Card(
                        color: Colors.blue[50],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'La comunidad puede agregar notas para verificar o cuestionar la veracidad de este reporte.',
                                  style: TextStyle(
                                    color: Colors.blue[900],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Campo para nueva nota o edición
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _editingNotaId != null
                                    ? 'Editar Nota de Veracidad'
                                    : 'Agregar Nota de Veracidad',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 12),
                              
                              // Selector de veracidad
                              Text(
                                '¿Consideras que este reporte es veraz?',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Diseño responsivo: fila en pantallas grandes, columna en móvil
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final isMobile = constraints.maxWidth < 400;
                                  
                                  final buttons = [
                                    _buildVeracityButton(
                                      label: 'Sí, es veraz',
                                      icon: Icons.check_circle,
                                      isSelected: _esVeraz == true,
                                      color: Colors.green,
                                      onTap: _postingNota ? null : () {
                                        setState(() => _esVeraz = true);
                                      },
                                    ),
                                    _buildVeracityButton(
                                      label: 'No estoy seguro',
                                      icon: Icons.help_outline,
                                      isSelected: _esVeraz == null,
                                      color: Colors.orange,
                                      onTap: _postingNota ? null : () {
                                        setState(() => _esVeraz = null);
                                      },
                                    ),
                                    _buildVeracityButton(
                                      label: 'No, es falso',
                                      icon: Icons.cancel,
                                      isSelected: _esVeraz == false,
                                      color: Colors.red,
                                      onTap: _postingNota ? null : () {
                                        setState(() => _esVeraz = false);
                                      },
                                    ),
                                  ];
                                  
                                  if (isMobile) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: buttons.map((btn) => Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: btn,
                                      )).toList(),
                                    );
                                  }
                                  
                                  return Row(
                                    children: buttons.map((btn) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: btn,
                                      ),
                                    )).toList(),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              
                              TextField(
                                controller: _notaCtrl,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText: 'Escribe tu análisis sobre la veracidad de este reporte...',
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                enabled: !_postingNota,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (_editingNotaId != null) ...[
                                    TextButton(
                                      onPressed: _postingNota ? null : _cancelEdit,
                                      child: const Text('Cancelar'),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  ElevatedButton.icon(
                                    onPressed: _postingNota ? null : _submitNota,
                                    icon: _postingNota
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : Icon(_editingNotaId != null ? Icons.save : Icons.send),
                                    label: Text(_editingNotaId != null ? 'Actualizar' : 'Publicar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Lista de notas de comunidad
                      if (_loadingNotas)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        )
                      else if (_notasComunidad.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                'No hay notas de veracidad aún. ¡Sé el primero en agregar una!',
                                style: TextStyle(color: Colors.grey[600]),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._notasComunidad.map((nota) {
                          final currentUserId = GetIt.instance<SupabaseService>().backendUserId;
                          final isAuthor = nota['user_id'] == currentUserId;
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.green[100],
                                        child: Icon(
                                          Icons.verified_user,
                                          color: Colors.green[700],
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nota['user_name']?.toString() ?? 'Usuario',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (nota['created_at'] != null)
                                              Text(
                                                _formatDate(nota['created_at'].toString()),
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            // Badge de verificación
                                            if (nota['es_veraz'] != null)
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: nota['es_veraz'] == true
                                                      ? Colors.green[100]
                                                      : Colors.red[100],
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: nota['es_veraz'] == true
                                                        ? Colors.green
                                                        : Colors.red,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      nota['es_veraz'] == true
                                                          ? Icons.check_circle
                                                          : Icons.cancel,
                                                      size: 14,
                                                      color: nota['es_veraz'] == true
                                                          ? Colors.green[700]
                                                          : Colors.red[700],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      nota['es_veraz'] == true
                                                          ? 'Considera veraz'
                                                          : 'Considera falso',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: nota['es_veraz'] == true
                                                            ? Colors.green[700]
                                                            : Colors.red[700],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (isAuthor) ...[
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 20),
                                          onPressed: () => _editNota(nota),
                                          tooltip: 'Editar',
                                          color: Colors.blue,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, size: 20),
                                          onPressed: () => _deleteNota(nota['id'] as int),
                                          tooltip: 'Eliminar',
                                          color: Colors.red,
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: Text(
                                      nota['nota']?.toString() ?? '',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                  ),
                ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inDays > 365) {
        return 'Hace ${(diff.inDays / 365).floor()} año${(diff.inDays / 365).floor() > 1 ? 's' : ''}';
      } else if (diff.inDays > 30) {
        return 'Hace ${(diff.inDays / 30).floor()} mes${(diff.inDays / 30).floor() > 1 ? 'es' : ''}';
      } else if (diff.inDays > 0) {
        return 'Hace ${diff.inDays} día${diff.inDays > 1 ? 's' : ''}';
      } else if (diff.inHours > 0) {
        return 'Hace ${diff.inHours} hora${diff.inHours > 1 ? 's' : ''}';
      } else if (diff.inMinutes > 0) {
        return 'Hace ${diff.inMinutes} minuto${diff.inMinutes > 1 ? 's' : ''}';
      } else {
        return 'Hace un momento';
      }
    } catch (_) {
      return dateStr;
    }
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

  Widget _buildVeracityButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required MaterialColor color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color[100] : Colors.grey[100],
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? color[700] : Colors.grey[600],
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color[700] : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
