import 'package:flutter/material.dart';
import 'district_ranking_widget.dart';

class DistrictRankingPage extends StatelessWidget {
  const DistrictRankingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FC),
      appBar: AppBar(
        title: const Text('Ranking de Seguridad'),
        backgroundColor: const Color(0xFF0E2D52),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header informativo
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0E2D52), Color(0xFF2E5266)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0E2D52).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.verified_user,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '¿Dónde es más seguro vivir?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Descubre los distritos con menos incidentes reportados',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Widget principal de ranking
                const DistrictRankingWidget(),
                const SizedBox(height: 20),
                // Footer informativo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4A7C9E), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E2D52),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.info_outline, 
                              color: Colors.white, 
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '¿Cómo se calcula el ranking?',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF0E2D52),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline, color: Color(0xFF4A7C9E), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Solo se consideran reportes con veracidad ≥33% y estado activo',
                              style: TextStyle(fontSize: 12, color: Color(0xFF1A3A52)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.trending_down, color: Color(0xFF4A7C9E), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Los distritos con menos delitos reportados son más seguros',
                              style: TextStyle(fontSize: 12, color: Color(0xFF1A3A52)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.calendar_today, color: Color(0xFF4A7C9E), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Filtra por semana, mes o año para ver tendencias temporales',
                              style: TextStyle(fontSize: 12, color: Color(0xFF1A3A52)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
