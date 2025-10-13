// lib/features/mapa/mapa_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';
import '../../core/env.dart';

class Reporte {
  final int id;
  final String titulo;
  final String descripcion;
  final String categoria;
  final String direccion;
  final double lat;
  final double lon;

  Reporte({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.categoria,
    required this.direccion,
    required this.lat,
    required this.lon,
  });

  factory Reporte.fromJson(Map<String, dynamic> j) {
    return Reporte(
      id: (j['id'] as num).toInt(),
      titulo: (j['titulo'] ?? 'Sin título').toString(),
      descripcion: (j['descripcion'] ?? '').toString(),
      categoria: (j['categoria'] ?? 'Otro').toString(),
      direccion: (j['direccion'] ?? '').toString(),
      lat: (j['lat'] as num).toDouble(),
      lon: (j['lon'] as num).toDouble(),
    );
  }
}

class MapaPage extends StatefulWidget {
  final ApiClient api;
  const MapaPage({super.key, required this.api});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  Set<Circle> _circles = {};
  Set<Marker> _markers = {};
  final _mapCtl = Completer<GoogleMapController>();

  List<Reporte> _reportes = [];
  Map<String, int> _reportesPorZona = {};
  bool _loading = true;
  String _errorMessage = '';

  static const _limaCenter = LatLng(-12.046374, -77.042793);

  @override
  void initState() {
    super.initState();
    _loadReportes();
  }

  Future<void> _loadReportes() async {
    setState(() {
      _loading = true;
      _errorMessage = '';
    });

    try {
      debugPrint('🔄 Cargando reportes desde: ${Env.apiBaseUrl}/Reportes');
      
      final res = await http.get(Uri.parse('${Env.apiBaseUrl}/Reportes'));
      
      debugPrint('📡 Respuesta HTTP: ${res.statusCode}');
      
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final List<dynamic> data = jsonDecode(res.body);
      debugPrint('📊 Reportes recibidos: ${data.length}');

      final reportes = <Reporte>[];
      final markers = <Marker>{};
      final circles = <Circle>{};
      
      // Agrupar reportes por zona (aprox. 0.01 grados = ~1km)
      final Map<String, List<Reporte>> reportesPorZona = {};

      for (var i = 0; i < data.length; i++) {
        try {
          final r = Reporte.fromJson(data[i] as Map<String, dynamic>);
          
          debugPrint('📍 Reporte ${r.id}: ${r.titulo} en (${r.lat}, ${r.lon})');
          
          // Validar coordenadas
          if (r.lat.abs() > 90 || r.lon.abs() > 180) {
            debugPrint('⚠️ Coordenadas inválidas para reporte ${r.id}');
            continue;
          }

          reportes.add(r);

          // Crear marcador individual
          markers.add(Marker(
            markerId: MarkerId('rep-${r.id}'),
            position: LatLng(r.lat, r.lon),
            infoWindow: InfoWindow(
              title: r.titulo,
              snippet: '${r.categoria} • ${r.direccion}',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _getCategoryHue(r.categoria),
            ),
          ));

          // Agrupar por zona (redondear a 2 decimales)
          final zoneKey = '${(r.lat * 100).round()}_${(r.lon * 100).round()}';
          reportesPorZona.putIfAbsent(zoneKey, () => []).add(r);
          
        } catch (e) {
          debugPrint('❌ Error procesando reporte $i: $e');
        }
      }

      // Crear círculos de calor por zona
      reportesPorZona.forEach((key, reps) {
        final count = reps.length;
        final avgLat = reps.fold<double>(0, (sum, r) => sum + r.lat) / count;
        final avgLon = reps.fold<double>(0, (sum, r) => sum + r.lon) / count;
        
        final color = _getHeatColor(count);
        final radius = 300.0 + (count * 100.0).clamp(0, 1500);

        circles.add(
          Circle(
            circleId: CircleId('zone-$key'),
            center: LatLng(avgLat, avgLon),
            radius: radius,
            fillColor: color.withOpacity(0.3),
            strokeColor: color.withOpacity(0.7),
            strokeWidth: 2,
            consumeTapEvents: true,
            onTap: () => _showZoneInfo(reps),
          ),
        );

        debugPrint('🔥 Zona $key: $count reportes en ($avgLat, $avgLon) - Radio: $radius m');
      });

      setState(() {
        _reportes = reportes;
        _markers = markers;
        _circles = circles;
        _reportesPorZona = reportesPorZona.map((k, v) => MapEntry(k, v.length));
      });

      debugPrint('✅ Cargado: ${reportes.length} reportes, ${circles.length} zonas');

      // Centrar el mapa en los reportes
      if (reportes.isNotEmpty && _mapCtl.isCompleted) {
        _fitMapToReports(reportes);
      }

    } catch (e, stack) {
      debugPrint('❌ Error cargando reportes: $e');
      debugPrint('Stack: $stack');
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 📐 Ajusta el zoom del mapa para mostrar todos los reportes
  Future<void> _fitMapToReports(List<Reporte> reportes) async {
    if (reportes.isEmpty) return;

    try {
      double minLat = reportes.first.lat;
      double maxLat = reportes.first.lat;
      double minLon = reportes.first.lon;
      double maxLon = reportes.first.lon;

      for (final r in reportes) {
        if (r.lat < minLat) minLat = r.lat;
        if (r.lat > maxLat) maxLat = r.lat;
        if (r.lon < minLon) minLon = r.lon;
        if (r.lon > maxLon) maxLon = r.lon;
      }

      if (!_mapCtl.isCompleted) {
        debugPrint('⚠️ Mapa no está listo aún');
        return;
      }

      final controller = await _mapCtl.future;
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.01, minLon - 0.01),
            northeast: LatLng(maxLat + 0.01, maxLon + 0.01),
          ),
          50, // padding
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Error ajustando zoom: $e');
    }
  }

  Color _getHeatColor(int count) {
    if (count > 10) return Colors.red;
    if (count > 5) return Colors.amber;
    return Colors.grey;
  }

  double _getCategoryHue(String categoria) {
    switch (categoria.toUpperCase()) {
      case 'ROBO':
        return BitmapDescriptor.hueRed;
      case 'ASALTO':
        return BitmapDescriptor.hueOrange;
      case 'ACOSO':
        return BitmapDescriptor.hueMagenta;
      case 'VANDALISMO':
        return BitmapDescriptor.hueViolet;
      case 'ACCIDENTE':
        return BitmapDescriptor.hueBlue;
      case 'ACHECHINATO':
      case 'ASESINATO':
        return BitmapDescriptor.hueRose;
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  Color _getCategoryColor(String categoria) {
    switch (categoria.toUpperCase()) {
      case 'ROBO':
        return Colors.red;
      case 'ASALTO':
        return Colors.orange;
      case 'ACOSO':
        return Colors.pink;
      case 'VANDALISMO':
        return Colors.purple;
      case 'ACCIDENTE':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String categoria) {
    switch (categoria.toUpperCase()) {
      case 'ROBO':
        return Icons.shopping_bag;
      case 'ASALTO':
        return Icons.warning;
      case 'ACOSO':
        return Icons.people;
      case 'VANDALISMO':
        return Icons.broken_image;
      case 'ACCIDENTE':
        return Icons.car_crash;
      default:
        return Icons.report;
    }
  }

  void _showZoneInfo(List<Reporte> reportes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final sorted = [...reportes]..sort((a, b) => b.id.compareTo(a.id));
        final color = _getHeatColor(reportes.length);

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (ctx, controller) => Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(color: color.withOpacity(0.3)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${reportes.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Zona de Incidentes',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            '${reportes.length} ${reportes.length == 1 ? "reporte" : "reportes"}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) {
                    final r = sorted[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getCategoryColor(r.categoria).withOpacity(0.2),
                        child: Icon(
                          _getCategoryIcon(r.categoria),
                          color: _getCategoryColor(r.categoria),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        r.titulo,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('${r.categoria} • ${r.direccion}'),
                      dense: true,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Calor - Lima'),
        backgroundColor: const Color(0xFF08192D),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReportes,
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando reportes...'),
                ],
              ),
            )
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Error cargando el mapa',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadReportes,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: _limaCenter,
                        zoom: 11.5,
                      ),
                      myLocationButtonEnabled: true,
                      zoomControlsEnabled: true,
                      mapToolbarEnabled: false,
                      markers: _markers,
                      circles: _circles,
                      onMapCreated: (c) {
                        _mapCtl.complete(c);
                        if (_reportes.isNotEmpty) {
                          Future.delayed(const Duration(milliseconds: 500), () {
                            _fitMapToReports(_reportes);
                          });
                        }
                      },
                    ),

                    // Leyenda
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Nivel de Riesgo',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildLegendItem('Bajo (≤5)', Colors.grey),
                              _buildLegendItem('Medio (6-10)', Colors.amber),
                              _buildLegendItem('Alto (>10)', Colors.red),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Contador de reportes
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.report, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '${_reportes.length} reportes',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '• ${_reportesPorZona.length} zonas',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color.withOpacity(0.3),
              border: Border.all(color: color, width: 2),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapCtl.future.then((c) => c.dispose()).catchError((_) {});
    super.dispose();
  }
}