import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/api_client.dart';
import 'core/supabase_service.dart';
import 'features/home/home_page.dart';
import 'features/auth/auth_page.dart';

final sl = GetIt.instance;

Future<void> _setup() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'settings.env');
  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  sl.registerLazySingleton<ApiClient>(() => ApiClient());
  sl.registerLazySingleton<SupabaseService>(() => SupabaseService(Supabase.instance.client));
}

void main() async {
  await _setup();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final api = sl<ApiClient>();
    final auth = sl<SupabaseService>();

    return MaterialApp(
      title: 'Safe2Gether',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0D47A1)),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              children: [
                const SizedBox(height: 24),
                Image.network(
                  'https://raw.githubusercontent.com/flutter/website/main/src/_assets/image/flutter-lockup-bg.jpg',
                  height: 80,
                  errorBuilder: (_, __, ___) => const FlutterLogo(size: 80),
                ),
                const SizedBox(height: 16),
                AuthPage(auth: auth),
                const SizedBox(height: 16),
                HomePage(api: api, auth: auth),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
