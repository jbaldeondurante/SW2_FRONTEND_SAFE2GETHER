import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/supabase_service.dart';
import '../../core/env.dart';
import '../../core/responsive_utils.dart';
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final maxWidth = ResponsiveHelper.getMaxContentWidth(context);
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.getVerticalSpacing(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe2Gether'),
        leading: IconButton(
          tooltip: 'Mi perfil',
          icon: const Icon(Icons.person_outline),
          onPressed: () => context.push('/profile'),
        ),
        actions: [
          // 👇 Nuevo botón para ir al mapa de calor
          IconButton(
            tooltip: 'Mapa de calor (Lima)',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => context.push('/mapa'),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: padding,
            children: [
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(user?.email ?? 'no autenticado'),
                  subtitle: Text('API: ${Env.apiBaseUrl}'),
                ),
              ),
              SizedBox(height: spacing * 0.75),
              FilledButton.icon(
                onPressed: _ping,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Probar conexión con FastAPI'),
              ),
              SizedBox(height: spacing * 0.75),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    _status,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
              SizedBox(height: spacing * 1.5),
              Wrap(
                spacing: spacing * 0.5,
                runSpacing: spacing * 0.5,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/reportes'),
                    icon: const Icon(Icons.report),
                    label: const Text('Reportes'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/mapa'),
                    icon: const Icon(Icons.map),
                    label: const Text('Mapa'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/alertas'),
                    icon: const Icon(Icons.notification_important),
                    label: const Text('Alertas'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/comparacion-distritos'),
                    icon: const Icon(Icons.analytics),
                    label: const Text('Comparar Distritos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/ranking-distritos'),
                    icon: const Icon(Icons.security),
                    label: const Text('Ranking Distritos'),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
