// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/api_client.dart';
import 'core/supabase_service.dart';

import 'features/auth/auth_page.dart';
import 'features/home/home_page.dart';
import 'features/reportes/reportes_page.dart';
import 'features/mapa/mapa_page.dart';
import 'features/alertas/alertas_page.dart';

final sl = GetIt.instance;

/// Carga variables de entorno, inicializa servicios y Supabase.
Future<void> _setup() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Cargar .env (prioriza web vs android; fallback a settings.env)
  try {
    await dotenv.load(fileName: kIsWeb ? 'settings.env' : 'settings.android.env');
  } catch (_) {
    // Fallback si no existe el específico
    await dotenv.load(fileName: 'settings.env');
  }

  // (Opcional) Si tu Env tiene validaciones/prints, descomenta:
  // Env.validate();
  // Env.printConfig();

  // 2) Inicializar Supabase
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  // 3) Registrar dependencias
  if (!sl.isRegistered<ApiClient>()) {
    // Si tu ApiClient acepta baseUrl desde Env, cámbialo a: ApiClient(baseUrl: Env.apiBaseUrl)
    sl.registerLazySingleton<ApiClient>(() => ApiClient());
  }
  if (!sl.isRegistered<SupabaseService>()) {
    sl.registerLazySingleton<SupabaseService>(
      () => SupabaseService(Supabase.instance.client),
    );
  }
}

/// Notificador para que GoRouter reaccione a cambios de sesión
class SupabaseAuthNotifier extends ChangeNotifier {
  late final StreamSubscription _sub;
  VoidCallback? _backendListener;

  SupabaseAuthNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
    // Escucha cambios en el login del backend para refrescar el router
    if (sl.isRegistered<SupabaseService>()) {
      final svc = sl<SupabaseService>();
      _backendListener = () => notifyListeners();
      svc.backendLoginNotifier.addListener(_backendListener!);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    if (_backendListener != null && sl.isRegistered<SupabaseService>()) {
      sl<SupabaseService>().backendLoginNotifier.removeListener(_backendListener!);
    }
    super.dispose();
  }
}

void main() async {
  await _setup();
  // Espera a que SupabaseService restaure el estado de login del backend
  try {
    await sl<SupabaseService>().ready;
  } catch (_) {}
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
        final backendOk = sl<SupabaseService>().backendLoggedIn;
        final loggingIn = state.matchedLocation == '/login';

        // Si no hay sesión Supabase y backend no ha confirmado, fuerza /login
        if (user == null && !loggingIn && !backendOk) return '/login';
        // Si ya hay sesión (o backend OK) y estás en /login, redirige a /home
        if ((user != null || backendOk) && loggingIn) return '/home';
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
      debugShowCheckedModeBanner: false,
    );
  }
}
