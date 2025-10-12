import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/env.dart';
import 'core/api_client.dart';
import 'core/supabase_service.dart';
import 'features/home/home_page.dart';
import 'features/auth/auth_page.dart';
import 'features/reportes/reportes_page.dart';
import 'features/mapa/mapa_page.dart';
import 'features/alertas/alertas_page.dart';

final sl = GetIt.instance;

Future<void> _setup() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Carga 2 envs (web vs android)
  try {
    await dotenv.load(fileName: kIsWeb ? 'settings.env' : 'settings.android.env');
  } catch (_) {
    await dotenv.load(fileName: 'settings.env');
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  sl.registerLazySingleton<ApiClient>(() => ApiClient());
  sl.registerLazySingleton<SupabaseService>(() => SupabaseService(Supabase.instance.client));
}

/// Notificador para que GoRouter reaccione a cambios de sesión
class SupabaseAuthNotifier extends ChangeNotifier {
  late final StreamSubscription _sub;
  SupabaseAuthNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

void main() async {
  await _setup();
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final SupabaseAuthNotifier _authNotifier;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authNotifier = SupabaseAuthNotifier();

    _router = GoRouter(
      initialLocation: '/home',
      refreshListenable: _authNotifier,
      routes: [
        GoRoute(
          path: '/login',
          name: 'login',
          builder: (_, __) => AuthPage(auth: sl<SupabaseService>(), api: sl<ApiClient>()),
        ),
        GoRoute(
          path: '/home',
          name: 'home',
          builder: (_, __) => HomePage(api: sl<ApiClient>(), auth: sl<SupabaseService>()),
        ),
        GoRoute(
          path: '/reportes',
          name: 'reportes',
          builder: (_, __) => ReportesPage(api: sl<ApiClient>()),
        ),
        GoRoute(
          path: '/mapa',
          name: 'mapa',
          builder: (_, __) => MapaPage(api: sl<ApiClient>()),
        ),
        GoRoute(
          path: '/alertas',
          name: 'alertas',
          builder: (_, __) => AlertasPage(api: sl<ApiClient>()),
        ),
        GoRoute(path: '/', redirect: (_, __) => '/home'),
      ],
      redirect: (_, state) {
        final user = Supabase.instance.client.auth.currentUser;
        final loggingIn = state.matchedLocation == '/login';
        if (user == null && !loggingIn) return '/login';   // protege rutas
        if (user != null && loggingIn) return '/home';
        return null;
      },
    );
  }

  @override
  void dispose() {
    _authNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = const Color(0xFF0D47A1);
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light),
      textTheme: GoogleFonts.outfitTextTheme(),
      scaffoldBackgroundColor: const Color(0xFFF7F9FC),
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
    );

    return MaterialApp.router(
      title: 'Safe2Gether',
      theme: baseTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false, // Ocultar la señal de debug para que salga el logout
    );
  }
}
