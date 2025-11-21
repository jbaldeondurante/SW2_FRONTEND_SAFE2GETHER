import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class DistrictRankingWidget extends StatefulWidget {
  const DistrictRankingWidget({super.key});

  @override
  State<DistrictRankingWidget> createState() => _DistrictRankingWidgetState();
}

class _DistrictRankingWidgetState extends State<DistrictRankingWidget> {
  final _api = ApiClient();
  String _period = 'week';
  bool _loading = true;
  List<dynamic> _rows = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.getDistrictRanking(period: _period);
      setState(() { _rows = data; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Color _getSafetyColor(int index, int total) {
    if (index < 3) return const Color(0xFF4A7C9E); // Top 3 más seguros (azul claro)
    if (index > total - 4) return const Color(0xFF1A3A52); // Bottom 3 menos seguros (azul oscuro)
    return const Color(0xFF2E5266); // Medio (tono intermedio)
  }

  IconData _getRankIcon(int position) {
    switch (position) {
      case 1: return Icons.emoji_events; // Trofeo oro
      case 2: return Icons.workspace_premium; // Medalla plata
      case 3: return Icons.military_tech; // Medalla bronce
      default: return Icons.location_city;
    }
  }

  String _getPeriodLabel() {
    switch (_period) {
      case 'week': return 'última semana';
      case 'month': return 'último mes';
      case 'year': return 'último año';
      default: return _period;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.security, size: 24, color: Color(0xFF0E2D52)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ranking de Seguridad',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Distritos más seguros en ${_getPeriodLabel()}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF5A7A8E)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0F5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF4A7C9E)),
                  ),
                  child: DropdownButton<String>(
                    value: _period,
                    underline: const SizedBox(),
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'week', child: Text('📅 Semana')),
                      DropdownMenuItem(value: 'month', child: Text('📅 Mes')),
                      DropdownMenuItem(value: 'year', child: Text('📅 Año')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() { _period = v; });
                      _fetch();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              Container(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0E2D52)),
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cargando ranking de ${_getPeriodLabel()}...',
                      style: const TextStyle(
                        color: Color(0xFF5A7A8E),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3F3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1A3A52), width: 2),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFF1A3A52), size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFF1A3A52),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _fetch,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E2D52),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            if (!_loading && _error == null)
              _rows.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.info_outline, size: 48, color: Color(0xFF5A7A8E)),
                            const SizedBox(height: 8),
                            const Text(
                              'Sin datos para el período seleccionado',
                              style: TextStyle(color: Color(0xFF3A5A6E)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Leyenda
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F9FC),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildLegendItem(const Color(0xFF4A7C9E), 'Muy seguro'),
                              _buildLegendItem(const Color(0xFF2E5266), 'Moderado'),
                              _buildLegendItem(const Color(0xFF1A3A52), 'Menos seguro'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final r = _rows[i] as Map<String, dynamic>;
                            final distrito = r['distrito'] ?? '—';
                            final total = r['total_delitos'] ?? 0;
                            final resueltos = r['resoluciones_autoridades'] ?? 0;
                            final porc = r['porcentaje_resoluciones'] ?? 0;
                            final position = i + 1;

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _getSafetyColor(i, _rows.length),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: i < 3 ? const Color(0xFF6A9FBE) : const Color(0xFF5A7A8E),
                                  width: i < 3 ? 2.5 : 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(i < 3 ? 0.15 : 0.08),
                                    blurRadius: i < 3 ? 8 : 4,
                                    offset: Offset(0, i < 3 ? 4 : 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Posición con ícono
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: i < 3 ? Colors.white : const Color(0xFFD8E8F0),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: i < 3
                                          ? Icon(
                                              _getRankIcon(position),
                                              color: i == 0
                                                  ? const Color(0xFFFFB300)
                                                  : i == 1
                                                      ? const Color(0xFF757575)
                                                      : const Color(0xFF8D6E63),
                                              size: 24,
                                            )
                                          : Text(
                                              '$position',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: Color(0xFF0E2D52),
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Nombre distrito
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          distrito,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Nivel: ${i < 3 ? 'Alto' : i > _rows.length - 4 ? 'Bajo' : 'Medio'}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFFE8F0F5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Métricas
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFE8F0F5)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.report_problem,
                                              size: 14,
                                              color: Color(0xFFFF6B35),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$total delitos',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF0E2D52),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE8F5F0),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF4CAF50)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.check_circle,
                                              size: 14,
                                              color: Color(0xFF2E7D32),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$resueltos ($porc%)',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF1B5E20),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF3A5A6E))),
      ],
    );
  }
}
