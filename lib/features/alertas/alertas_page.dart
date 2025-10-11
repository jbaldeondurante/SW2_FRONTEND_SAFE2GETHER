import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class AlertasPage extends StatelessWidget {
  final ApiClient api;
  const AlertasPage({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas')),
      body: const Center(
        child: Text('Alertas y notificaciones (TODO)'),
      ),
    );
  }
}
