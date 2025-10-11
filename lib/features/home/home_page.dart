import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/supabase_service.dart';
import '../../core/env.dart';
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

  Future<void> _logout() async {
    await widget.auth.signOut();
    if (mounted) context.go('/login');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe2Gether'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(user?.email ?? 'no autenticado'),
                  subtitle: Text('API: ${Env.apiBaseUrl}'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _ping,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Probar conexión con FastAPI'),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(_status, style: const TextStyle(fontFamily: 'monospace')),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _toast('Ir a Reportes (TODO)'),
                    icon: const Icon(Icons.report),
                    label: const Text('Reportes'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _toast('Ir a Mapa (TODO)'),
                    icon: const Icon(Icons.map),
                    label: const Text('Mapa'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _toast('Ir a Alertas (TODO)'),
                    icon: const Icon(Icons.notification_important),
                    label: const Text('Alertas'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
