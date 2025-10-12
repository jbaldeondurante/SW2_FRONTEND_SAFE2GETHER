import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? _missing('SUPABASE_URL');

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ?? _missing('SUPABASE_ANON_KEY');

  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? _missing('API_BASE_URL');

  /// URL adonde redirige el link del email de verificación (opcional, pero recomendado).
  /// Ej: http://localhost:5173 (web) o tu deeplink en mobile.
  static String? get supabaseRedirectUrl => dotenv.env['SUPABASE_REDIRECT_URL'];

  static String _missing(String key) {
    throw Exception('Falta $key en settings.env');
  }
}
