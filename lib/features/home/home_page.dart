// lib/features/home/home_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';
import '../../core/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatefulWidget {
  final ApiClient api;
  final SupabaseService auth;
  const HomePage({super.key, required this.api, required this.auth});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Circle> _heatCircles = {};
  bool _isLoadingReports = false;
  int _reportCount = 0;

  // Centro de Lima
  static const LatLng _centerLima = LatLng(-12.0464, -77.0428);

  @override
  void initState() {
    super.initState();
    _loadHeatmapData();
  }

  Future<void> _loadHeatmapData() async {
    setState(() => _isLoadingReports = true);

    try {
      final res = await http.get(Uri.parse('http://127.0.0.1:8000/Reportes'));
      
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        final markers = <Marker>{};
        final circles = <Circle>{};

        for (var i = 0; i < data.length; i++) {
          final report = data[i];
          final lat = report['lat'];
          final lon = report['lon'];

          if (lat != null && lon != null) {
            final position = LatLng(
              (lat is num) ? lat.toDouble() : double.parse('$lat'),
              (lon is num) ? lon.toDouble() : double.parse('$lon'),
            );

            // Marcador
            markers.add(Marker(
              markerId: MarkerId('report_$i'),
              position: position,
              infoWindow: InfoWindow(
                title: report['titulo'] ?? 'Reporte ${report['id']}',
                snippet: report['categoria'] ?? '',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(_getHueByCategory(report['categoria'])),
            ));

            // Círculo de calor
            circles.add(Circle(
              circleId: CircleId('heat_$i'),
              center: position,
              radius: 300, // 300 metros
              fillColor: _getColorByCategory(report['categoria']).withOpacity(0.2),
              strokeColor: _getColorByCategory(report['categoria']).withOpacity(0.5),
              strokeWidth: 2,
            ));
          }
        }

        setState(() {
          _markers = markers;
          _heatCircles = circles;
          _reportCount = data.length;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando reportes: $e')),
      );
    } finally {
      setState(() => _isLoadingReports = false);
    }
  }

  Color _getColorByCategory(String? categoria) {
    switch (categoria?.toUpperCase()) {
      case 'ROBO':
        return Colors.red;
      case 'ASALTO':
        return Colors.orange;
      case 'VANDALISMO':
        return Colors.purple;
      case 'ACOSO':
        return Colors.pink;
      case 'ACCIDENTE':
        return Colors.blue;
      case 'ASESINATO':
      case 'ACHECHINATO':
        return Colors.deepPurple;
      default:
        return Colors.grey;
    }
  }

  double _getHueByCategory(String? categoria) {
    switch (categoria?.toUpperCase()) {
      case 'ROBO':
        return BitmapDescriptor.hueRed;
      case 'ASALTO':
        return BitmapDescriptor.hueOrange;
      case 'VANDALISMO':
        return BitmapDescriptor.hueViolet;
      case 'ACOSO':
        return BitmapDescriptor.hueMagenta;
      case 'ACCIDENTE':
        return BitmapDescriptor.hueBlue;
      case 'ASESINATO':
      case 'ACHECHINATO':
        return BitmapDescriptor.hueRose;
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  Future<void> _logout() async {
    await widget.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0E2D52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08192D),
        foregroundColor: Colors.white,
        title: SizedBox(
          height: 36,
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
        centerTitle: true,
        actions: [
          // BOTONES DE NAVEGACIÓN
          IconButton(
            tooltip: 'Reportes',
            icon: const Icon(Icons.report),
            onPressed: () => context.go('/reportes'),
          ),
          IconButton(
            tooltip: 'Alertas',
            icon: const Icon(Icons.notification_important),
            onPressed: () => context.go('/alertas'),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // INFO BAR
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF08192D),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  child: Icon(Icons.person, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.email ?? 'Usuario',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$_reportCount reportes en el mapa',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingReports)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: _loadHeatmapData,
                    tooltip: 'Actualizar mapa',
                  ),
              ],
            ),
          ),

          // MAPA
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  onMapCreated: (controller) => _mapController = controller,
                  initialCameraPosition: const CameraPosition(
                    target: _centerLima,
                    zoom: 12,
                  ),
                  markers: _markers,
                  circles: _heatCircles,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: true,
                  compassEnabled: true,
                ),

                // LEYENDA
                Positioned(
                  top: 16,
                  right: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Leyenda',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          _buildLegendItem('Robo', Colors.red),
                          _buildLegendItem('Asalto', Colors.orange),
                          _buildLegendItem('Vandalismo', Colors.purple),
                          _buildLegendItem('Acoso', Colors.pink),
                          _buildLegendItem('Accidente', Colors.blue),
                          _buildLegendItem('Asesinato', Colors.deepPurple),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // BOTÓN DE CREAR REPORTE
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF08192D),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => context.go('/reportes'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Ver todos los reportes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF08192D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
            width: 16,
            height: 16,
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
    _mapController?.dispose();
    super.dispose();
  }
}