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
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(16.0),
            child: DistrictRankingWidget(),
          ),
        ),
      ),
    );
  }
}
