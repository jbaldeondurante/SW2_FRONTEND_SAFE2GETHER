// lib/features/home/comparacion_distritos_page.dart
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/env.dart';
import '../../core/responsive_utils.dart';

class ComparacionDistritosPage extends StatefulWidget {
  const ComparacionDistritosPage({super.key});

  @override
  State<ComparacionDistritosPage> createState() =>
      _ComparacionDistritosPageState();
}

class _ComparacionDistritosPageState extends State<ComparacionDistritosPage> {
  Map<String, dynamic> _estadisticas = {};
  List<String> _distritosSeleccionados = [];
  bool _loading = true;
  String? _error;
  String? _categoriaFiltro;
  Set<String> _todasCategorias = {};

  @override
  void initState() {
    super.initState();
    _cargarEstadisticas();
  }

  Future<void> _cargarEstadisticas() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final url = '${Env.apiBaseUrl}/Reportes/estadisticas/distritos';
      debugPrint('📊 Cargando estadísticas desde: $url');

      final res = await http.get(Uri.parse(url));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final Map<String, dynamic> data = jsonDecode(res.body);
      debugPrint('✅ Estadísticas cargadas: ${data.keys.length} distritos');

      // Extraer todas las categorías únicas
      final categorias = <String>{};
      data.forEach((distrito, stats) {
        final porCategoria = stats['por_categoria'] as Map<String, dynamic>?;
        if (porCategoria != null) {
          categorias.addAll(porCategoria.keys.cast<String>());
        }
      });

      setState(() {
        _estadisticas = data;
        _todasCategorias = categorias;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando estadísticas: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<MapEntry<String, dynamic>> _getDistritosOrdenados() {
    final entries = _estadisticas.entries.toList();
    entries.sort((a, b) {
      final totalA = a.value['total'] as int;
      final totalB = b.value['total'] as int;
      return totalB.compareTo(totalA); // Descendente (más peligrosos primero)
    });
    return entries;
  }

  int _getReportesPorCategoria(String distrito, String? categoria) {
    if (categoria == null) {
      return (_estadisticas[distrito]?['total'] ?? 0) as int;
    }
    final porCategoria = _estadisticas[distrito]?['por_categoria'] as Map<String, dynamic>?;
    return (porCategoria?[categoria] ?? 0) as int;
  }

  void _toggleDistrito(String distrito) {
    setState(() {
      if (_distritosSeleccionados.contains(distrito)) {
        _distritosSeleccionados.remove(distrito);
      } else {
        _distritosSeleccionados.add(distrito);
      }
    });
  }

  Widget _buildDistritoCard(String distrito, int total) {
    final isSelected = _distritosSeleccionados.contains(distrito);
    final color = _getColorPorNivel(total);

    return Card(
      elevation: isSelected ? 8 : 2,
      color: isSelected ? color.withOpacity(0.1) : null,
      child: InkWell(
        onTap: () => _toggleDistrito(distrito),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleDistrito(distrito),
                activeColor: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distrito,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? color : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total reportes',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getNivelSeguridad(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparativa() {
    if (_distritosSeleccionados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.compare_arrows, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Selecciona dos o más distritos para compararlos',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filtro por categoría
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Filtrar por tipo de delito:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todos'),
                      selected: _categoriaFiltro == null,
                      onSelected: (_) => setState(() => _categoriaFiltro = null),
                    ),
                    ..._todasCategorias.map((cat) => ChoiceChip(
                          label: Text(cat),
                          selected: _categoriaFiltro == cat,
                          onSelected: (_) =>
                              setState(() => _categoriaFiltro = cat),
                        )),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          // Tabla comparativa
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Distrito')),
                const DataColumn(
                    label: Text('Reportes'), numeric: true),
                const DataColumn(label: Text('Nivel de Seguridad')),
              ],
              rows: _distritosSeleccionados.map((distrito) {
                final reportes =
                    _getReportesPorCategoria(distrito, _categoriaFiltro);
                final color = _getColorPorNivel(reportes);
                final nivel = _getNivelSeguridad(reportes);

                return DataRow(cells: [
                  DataCell(Text(
                    distrito,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  )),
                  DataCell(Text(
                    reportes.toString(),
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  )),
                  DataCell(Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      nivel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )),
                ]);
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Desglose por categoría
          if (_categoriaFiltro == null) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Desglose por tipo de delito:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  ..._distritosSeleccionados.map((distrito) {
                    final porCategoria =
                        _estadisticas[distrito]?['por_categoria'] as Map<String, dynamic>?;
                    if (porCategoria == null || porCategoria.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              distrito,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...porCategoria.entries.map((entry) {
                              final categoria = entry.key;
                              final cantidad = entry.value as int;
                              final total =
                                  _estadisticas[distrito]?['total'] as int;
                              final porcentaje =
                                  ((cantidad / total) * 100).round();

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(categoria),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: LinearProgressIndicator(
                                        value: cantidad / total,
                                        backgroundColor: Colors.grey[200],
                                        color: _getCategoriaColor(categoria),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        '$cantidad ($porcentaje%)',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getColorPorNivel(int reportes) {
    if (reportes >= 20) return Colors.red[700]!;
    if (reportes >= 10) return Colors.orange[700]!;
    if (reportes >= 5) return Colors.yellow[700]!;
    return Colors.green[700]!;
  }

  String _getNivelSeguridad(int reportes) {
    if (reportes >= 20) return 'Muy Peligroso';
    if (reportes >= 10) return 'Peligroso';
    if (reportes >= 5) return 'Moderado';
    return 'Seguro';
  }

  Color _getCategoriaColor(String categoria) {
    switch (categoria.toLowerCase()) {
      case 'robo':
        return Colors.red;
      case 'asalto':
        return Colors.orange;
      case 'vandalismo':
        return Colors.purple;
      case 'accidente':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparación de Distritos'),
        actions: [
          if (_distritosSeleccionados.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _distritosSeleccionados.clear()),
              icon: const Icon(Icons.clear_all),
              label: const Text('Limpiar'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarEstadisticas,
            tooltip: 'Recargar datos',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error: $_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _cargarEstadisticas,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : _estadisticas.isEmpty
                  ? Center(
                      child: Padding(
                        padding: ResponsiveHelper.getPadding(context, factor: 2),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_off,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No hay datos de distritos disponibles',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        // Lista de distritos (izquierda)
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                color: Colors.blue[50],
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_city,
                                        color: Colors.blue),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Distritos (${_estadisticas.length})',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _estadisticas.length,
                                  itemBuilder: (context, index) {
                                    final entry =
                                        _getDistritosOrdenados()[index];
                                    final distrito = entry.key;
                                    final total = entry.value['total'] as int;
                                    return _buildDistritoCard(distrito, total);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Comparativa (derecha)
                        Expanded(
                          flex: 3,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  color: Colors.green[50],
                                  child: Row(
                                    children: [
                                      const Icon(Icons.compare,
                                          color: Colors.green),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Comparativa (${_distritosSeleccionados.length} seleccionados)',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(child: _buildComparativa()),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
