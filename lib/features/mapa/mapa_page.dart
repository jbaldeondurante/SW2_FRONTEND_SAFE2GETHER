// lib/features/mapa/mapa_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';
import '../../core/env.dart';
import '../../core/responsive_utils.dart';
import '../reportes/reporte_detalle_page.dart';

class Reporte {
  final int id;
  final String titulo;
  final String descripcion;
  final String categoria;
  final String direccion;
  final double lat;
  final double lon;
  final DateTime? createdAt;
  final double veracidadPorcentaje;

  Reporte({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.categoria,
    required this.direccion,
    required this.lat,
    required this.lon,
    this.createdAt,
    this.veracidadPorcentaje = 0,
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
      createdAt: j['created_at'] != null 
          ? DateTime.tryParse(j['created_at'].toString()) 
          : null,
      veracidadPorcentaje: (j['veracidad_porcentaje'] as num?)?.toDouble() ?? 0,
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
  List<Reporte> _reportesFiltrados = [];
  Map<String, int> _reportesPorZona = {};
  bool _loading = true;
  String _errorMessage = '';

  // Filtros
  Set<String> _categoriasFiltradas = {};
  DateTimeRange? _rangoFechas;
  double _veracidadMinima = 33.0;

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
          markers.add(
            Marker(
              markerId: MarkerId('rep-${r.id}'),
              position: LatLng(r.lat, r.lon),
              infoWindow: InfoWindow(
                title: r.titulo,
                snippet: '${r.categoria} • ${r.direccion}',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                _getCategoryHue(r.categoria),
              ),
            ),
          );

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

        debugPrint(
          '🔥 Zona $key: $count reportes en ($avgLat, $avgLon) - Radio: $radius m',
        );
      });

      setState(() {
        _reportes = reportes;
        _reportesFiltrados = reportes;
        _markers = markers;
        _circles = circles;
        _reportesPorZona = reportesPorZona.map((k, v) => MapEntry(k, v.length));
      });

      debugPrint(
        '✅ Cargado: ${reportes.length} reportes, ${circles.length} zonas',
      );

      // Aplicar filtros
      _aplicarFiltros();

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

  /// 🔍 Aplica los filtros seleccionados a los reportes
  void _aplicarFiltros() {
    List<Reporte> filtrados = _reportes;

    // Filtrar por categorías
    if (_categoriasFiltradas.isNotEmpty) {
      filtrados = filtrados.where((r) => _categoriasFiltradas.contains(r.categoria)).toList();
    }

    // Filtrar por rango de fechas
    if (_rangoFechas != null) {
      filtrados = filtrados.where((r) {
        if (r.createdAt == null) return false;
        final fecha = r.createdAt!;
        return fecha.isAfter(_rangoFechas!.start.subtract(const Duration(days: 1))) &&
               fecha.isBefore(_rangoFechas!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // Filtrar por veracidad mínima
    filtrados = filtrados.where((r) => r.veracidadPorcentaje >= _veracidadMinima).toList();

    // Recalcular círculos y marcadores con reportes filtrados
    final markers = <Marker>{};
    final circles = <Circle>{};
    final Map<String, List<Reporte>> reportesPorZona = {};

    for (final r in filtrados) {
      markers.add(
        Marker(
          markerId: MarkerId('rep-${r.id}'),
          position: LatLng(r.lat, r.lon),
          infoWindow: InfoWindow(
            title: r.titulo,
            snippet: '${r.categoria} • ${r.direccion}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _getCategoryHue(r.categoria),
          ),
        ),
      );

      final zoneKey = '${(r.lat * 100).round()}_${(r.lon * 100).round()}';
      reportesPorZona.putIfAbsent(zoneKey, () => []).add(r);
    }

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
    });

    setState(() {
      _reportesFiltrados = filtrados;
      _markers = markers;
      _circles = circles;
      _reportesPorZona = reportesPorZona.map((k, v) => MapEntry(k, v.length));
    });

    debugPrint('🔍 Filtros aplicados: ${filtrados.length}/${_reportes.length} reportes');
  }

  /// 🎛️ Muestra el diálogo de filtros
  Future<void> _mostrarFiltros() async {
    final categorias = _reportes.map((r) => r.categoria).toSet().toList()..sort();
    final dialogPadding = ResponsiveHelper.getPadding(context, factor: 0.75);
    
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          contentPadding: dialogPadding,
          title: const Row(
            children: [
              Icon(Icons.filter_list, color: Colors.blue),
              SizedBox(width: 8),
              Text('Filtros del Mapa'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filtro por categorías
                const Text(
                  'Tipos de Evento:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: categorias.map((cat) {
                    final seleccionado = _categoriasFiltradas.contains(cat);
                    return FilterChip(
                      label: Text(cat),
                      selected: seleccionado,
                      onSelected: (selected) {
                        setDialogState(() {
                          if (selected) {
                            _categoriasFiltradas.add(cat);
                          } else {
                            _categoriasFiltradas.remove(cat);
                          }
                        });
                      },
                      avatar: Icon(
                        _getCategoryIcon(cat),
                        size: 16,
                        color: seleccionado ? Colors.white : _getCategoryColor(cat),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Filtro por rango de fechas
                const Text(
                  'Rango de Fechas:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final rango = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: _rangoFechas,
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF08192D),
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (rango != null) {
                      setDialogState(() => _rangoFechas = rango);
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    _rangoFechas == null
                        ? 'Seleccionar fechas'
                        : '${_rangoFechas!.start.day}/${_rangoFechas!.start.month}/${_rangoFechas!.start.year} - ${_rangoFechas!.end.day}/${_rangoFechas!.end.month}/${_rangoFechas!.end.year}',
                  ),
                ),
                if (_rangoFechas != null)
                  TextButton.icon(
                    onPressed: () {
                      setDialogState(() => _rangoFechas = null);
                    },
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Limpiar fechas'),
                  ),
                const SizedBox(height: 16),

                // Filtro por veracidad
                const Text(
                  'Porcentaje de Validación Mínimo:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _veracidadMinima,
                        min: 33,
                        max: 100,
                        divisions: 67,
                        label: '${_veracidadMinima.round()}%',
                        activeColor: const Color(0xFF08192D),
                        onChanged: (value) {
                          setDialogState(() => _veracidadMinima = value);
                        },
                      ),
                    ),
                    Text(
                      '${_veracidadMinima.round()}%',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Nota: El porcentaje mínimo permitido es 33%',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Limpiar todos los filtros
                setState(() {
                  _categoriasFiltradas.clear();
                  _rangoFechas = null;
                  _veracidadMinima = 33.0;
                });
                setDialogState(() {});
                _aplicarFiltros();
              },
              child: const Text('Limpiar Todo'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                _aplicarFiltros();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF08192D),
                foregroundColor: Colors.white,
              ),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  /// 📅 Muestra el resumen semanal de eventos importantes
  Future<void> _mostrarResumenSemanal() async {
    // Calcular fecha de hace 7 días
    final ahora = DateTime.now();
    final haceSieteDias = ahora.subtract(const Duration(days: 7));

    // Filtrar reportes de la última semana con veracidad >= 33%
    final reportesSemana = _reportes.where((r) {
      if (r.createdAt == null) return false;
      return r.createdAt!.isAfter(haceSieteDias) && 
             r.veracidadPorcentaje >= 33.0;
    }).toList();

    // Agrupar por zona
    final Map<String, List<Reporte>> reportesPorZona = {};
    for (final r in reportesSemana) {
      final zoneKey = '${(r.lat * 100).round()}_${(r.lon * 100).round()}';
      reportesPorZona.putIfAbsent(zoneKey, () => []).add(r);
    }

    // Calcular estadísticas por zona
    final zonasConEstadisticas = <Map<String, dynamic>>[];
    reportesPorZona.forEach((zoneKey, reportes) {
      final avgLat = reportes.fold<double>(0, (sum, r) => sum + r.lat) / reportes.length;
      final avgLon = reportes.fold<double>(0, (sum, r) => sum + r.lon) / reportes.length;
      
      // Encontrar categoría más frecuente
      final categorias = <String, int>{};
      for (final r in reportes) {
        categorias[r.categoria] = (categorias[r.categoria] ?? 0) + 1;
      }
      String categoriaTop = 'N/A';
      int maxCount = 0;
      categorias.forEach((cat, count) {
        if (count > maxCount) {
          maxCount = count;
          categoriaTop = cat;
        }
      });

      // Calcular promedio de veracidad
      final promedioVeracidad = reportes.fold<double>(
        0, 
        (sum, r) => sum + r.veracidadPorcentaje
      ) / reportes.length;

      zonasConEstadisticas.add({
        'zona': zoneKey,
        'lat': avgLat,
        'lon': avgLon,
        'cantidad': reportes.length,
        'categoriaTop': categoriaTop,
        'promedioVeracidad': promedioVeracidad,
        'reportes': reportes,
      });
    });

    // Ordenar zonas por cantidad de reportes (más críticas primero)
    zonasConEstadisticas.sort((a, b) => 
      (b['cantidad'] as int).compareTo(a['cantidad'] as int)
    );

    // Mostrar diálogo con el resumen
    final dialogPadding = ResponsiveHelper.getPadding(context, factor: 0.75);
    final isMobile = ResponsiveHelper.isMobile(context);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: dialogPadding,
        title: Row(
          children: [
            Icon(Icons.calendar_view_week, color: Colors.blue[700]),
            const SizedBox(width: 8),
            Text('Resumen Semanal', style: TextStyle(fontSize: isMobile ? 16 : 18)),
          ],
        ),
        content: SizedBox(
          width: isMobile ? MediaQuery.of(ctx).size.width * 0.9 : double.maxFinite,
          child: reportesSemana.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No hay eventos en los últimos 7 días',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Resumen general
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Período: ${haceSieteDias.day}/${haceSieteDias.month}/${haceSieteDias.year} - ${ahora.day}/${ahora.month}/${ahora.year}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '📊 Total de eventos: ${reportesSemana.length}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              '📍 Zonas afectadas: ${zonasConEstadisticas.length}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              '✅ Todos con veracidad ≥ 33%',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Lista de zonas críticas
                      const Text(
                        'Zonas más críticas:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      ...zonasConEstadisticas.take(10).map((zona) {
                        final cantidad = zona['cantidad'] as int;
                        final categoriaTop = zona['categoriaTop'] as String;
                        final promedioVeracidad = zona['promedioVeracidad'] as double;
                        final reportes = zona['reportes'] as List<Reporte>;
                        final color = _getHeatColor(cantidad);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _showZoneInfo(reportes);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$cantidad',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              _getCategoryIcon(categoriaTop),
                                              size: 16,
                                              color: _getCategoryColor(categoriaTop),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              categoriaTop,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$cantidad ${cantidad == 1 ? "evento" : "eventos"} • ${promedioVeracidad.toStringAsFixed(0)}% veracidad',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 16),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
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
      case 'ASESINATO':
        return BitmapDescriptor.hueRose;
      case 'OTRO':
        return BitmapDescriptor.hueYellow;
      default:
        return BitmapDescriptor.hueYellow;
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
      case 'ASESINATO':
        return Colors.redAccent;
      case 'OTRO':
        return Colors.grey;
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
      case 'ASESINATO':
        return Icons.dangerous;
      case 'OTRO':
        return Icons.report;
      default:
        return Icons.report;
    }
  }

  void _showResumenZona(List<Reporte> reportes) {
    // Calcular estadísticas de la zona específica
    final reportesPorCategoria = <String, int>{};
    for (final r in reportes) {
      reportesPorCategoria[r.categoria] = (reportesPorCategoria[r.categoria] ?? 0) + 1;
    }
    
    String categoriaTop = 'N/A';
    int maxCount = 0;
    reportesPorCategoria.forEach((cat, count) {
      if (count > maxCount) {
        maxCount = count;
        categoriaTop = cat;
      }
    });

    final color = _getHeatColor(reportes.length);
    final nivelRiesgo = reportes.length > 10 ? 'Alto' : reportes.length > 5 ? 'Medio' : 'Bajo';

    final dialogPadding = ResponsiveHelper.getPadding(context, factor: 0.75);
    final isMobile = ResponsiveHelper.isMobile(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: dialogPadding,
        title: Row(
          children: [
            Icon(Icons.analytics, color: Colors.blue[700]),
            const SizedBox(width: 8),
            Text('Resumen de la Zona', style: TextStyle(fontSize: isMobile ? 16 : 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total de reportes en esta zona
              _buildStatRow(
                icon: Icons.report,
                label: 'Reportes en esta Zona',
                value: '${reportes.length}',
                color: Colors.blue,
              ),
              const Divider(),
              
              // Categoría más frecuente en esta zona
              _buildStatRow(
                icon: Icons.warning_amber,
                label: 'Delito más Frecuente',
                value: categoriaTop,
                color: Colors.orange,
              ),
              const Divider(),
              
              // Nivel de riesgo de esta zona
              _buildStatRow(
                icon: Icons.shield,
                label: 'Nivel de Riesgo',
                value: nivelRiesgo,
                color: color,
              ),
              const SizedBox(height: 16),
              
              // Desglose por categoría de esta zona
              const Text(
                'Desglose por Categoría:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...reportesPorCategoria.entries.map((entry) {
                final percentage = (reportes.isNotEmpty) 
                    ? (entry.value / reportes.length * 100).toStringAsFixed(1)
                    : '0.0';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getCategoryIcon(entry.key),
                            size: 16,
                            color: _getCategoryColor(entry.key),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.key,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      Text(
                        '${entry.value} ($percentage%)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
                      onPressed: () => _showResumenZona(reportes),
                      icon: const Icon(Icons.analytics),
                      tooltip: 'Ver estadísticas de la zona',
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
                        backgroundColor: _getCategoryColor(
                          r.categoria,
                        ).withOpacity(0.2),
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
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      dense: true,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReporteDetallePage(
                              reporteId: r.id,
                              api: widget.api,
                            ),
                          ),
                        );
                      },
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
            icon: Stack(
              children: [
                const Icon(Icons.filter_list),
                if (_categoriasFiltradas.isNotEmpty || 
                    _rangoFechas != null || 
                    _veracidadMinima > 33)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 8,
                        minHeight: 8,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _mostrarFiltros,
            tooltip: 'Filtrar reportes',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_view_week),
            onPressed: _mostrarResumenSemanal,
            tooltip: 'Resumen Semanal',
          ),
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
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
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
                            _reportesFiltrados.length != _reportes.length
                                ? '${_reportesFiltrados.length}/${_reportes.length} reportes'
                                : '${_reportes.length} reportes',
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
