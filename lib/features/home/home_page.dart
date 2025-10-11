import 'package:flutter/material.dart';
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
  String _status = 'Presiona para probar el backend';

  Future<void> _ping() async {
    setState(() => _status = 'Consultando...');
    try {
      final res = await widget.api.checkBackend();
      setState(() => _status = res);
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe2Gether'),
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await widget.auth.signOut();
                if (mounted) setState(() {});
              },
            )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Usuario: ${user?.email ?? "no autenticado"}'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _ping,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Probar conexión con FastAPI'),
          ),
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
