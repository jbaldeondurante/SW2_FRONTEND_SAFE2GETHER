import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class MapaPage extends StatelessWidget {
  final ApiClient api;
  const MapaPage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mapa')),
      body: const Center(
        child: Text('Mapa de calor (TODO)'),
      ),
    );
  }
}
