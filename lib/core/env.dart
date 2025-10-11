import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? _missing('SUPABASE_URL');

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ?? _missing('SUPABASE_ANON_KEY');

  static String get apiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? _missing('API_BASE_URL');

  static String _missing(String key) {
    throw Exception('Falta $key en settings.env');
  }
}
