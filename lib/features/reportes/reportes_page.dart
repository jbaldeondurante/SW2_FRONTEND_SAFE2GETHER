import 'package:flutter/material.dart';
import '../../core/api_client.dart';

class ReportesPage extends StatefulWidget {
  final ApiClient api;
  const ReportesPage({super.key, required this.api});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Crear reporte (TODO)')),
          );
        },
        label: const Text('Nuevo'),
        icon: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(child: ListTile(title: Text('Listado de reportes (TODO)'))),
          SizedBox(height: 8),
          Card(child: ListTile(title: Text('Detalle de reporte (TODO)'))),
        ],
      ),
    );
  }
}
