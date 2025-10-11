import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _client;
  SupabaseService(this._client);

  Future<void> signUpWithEmail(String email, String password) async {
    final res = await _client.auth.signUp(email: email, password: password);
    if (res.user == null) {
      throw Exception('No se pudo registrar el usuario');
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (res.session == null) {
      throw Exception('No se pudo iniciar sesión');
    }
  }

  Future<void> signOut() => _client.auth.signOut();
}
