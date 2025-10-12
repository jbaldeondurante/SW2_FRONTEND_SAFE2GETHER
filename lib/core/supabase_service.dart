import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
  final SupabaseClient _client;
  bool _backendLoggedIn = false;
  // Notifier para que la UI / router pueda reaccionar a cambios del login del backend.
  final ValueNotifier<bool> backendLoginNotifier = ValueNotifier(false);

  SupabaseService(this._client);

  /// Marca que el usuario inició sesión correctamente en el backend propio.
  bool get backendLoggedIn => _backendLoggedIn;
  set backendLoggedIn(bool v) {
    _backendLoggedIn = v;
    backendLoginNotifier.value = v;
  }

  /// Envía correo de verificación. Si Supabase tiene "Confirm email" activado,
  /// no podrás iniciar sesión hasta confirmar.
  Future<void> signUpWithEmail(
    String email,
    String password, {
    String? redirectTo,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: redirectTo,
    );
    if (res.user == null) {
      throw Exception('No se pudo registrar el usuario en Supabase');
    }
  }

  /// Inicia sesión con email + password.
  /// Si [requireConfirmed] es true, exige que el correo esté verificado.
  Future<void> signInWithEmail(
    String email,
    String password, {
    bool requireConfirmed = true,
  }) async {
    final res = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (res.session == null) {
      throw Exception('No se pudo iniciar sesión en Supabase');
    }
    if (requireConfirmed) {
      final user = _client.auth.currentUser;
      final confirmed = user?.emailConfirmedAt != null;
      if (!confirmed) {
        await _client.auth.signOut();
        throw Exception('Debes confirmar tu correo antes de iniciar sesión.');
      }
    }
  }

  Future<void> signOut() => _client.auth.signOut();
}
