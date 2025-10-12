import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SupabaseService {
  final SupabaseClient _client;
  bool _backendLoggedIn = false;
  int? _backendUserId;
  String? _backendUsername;
  // Notifier para que la UI / router pueda reaccionar a cambios del login del backend.
  final ValueNotifier<bool> backendLoginNotifier = ValueNotifier(false);
  // Señal para indicar que la restauración inicial terminó
  late final Future<void> ready;

  SupabaseService(this._client) {
    ready = _restoreBackendLogin();
  }

  /// Marca que el usuario inició sesión correctamente en el backend propio.
  bool get backendLoggedIn => _backendLoggedIn;
  set backendLoggedIn(bool v) {
    _backendLoggedIn = v;
    backendLoginNotifier.value = v;
    _persistBackendLogin(v);
  }

  int? get backendUserId => _backendUserId;
  set backendUserId(int? id) {
    _backendUserId = id;
    _persistBackendUserId(id);
  }

  String? get backendUsername => _backendUsername;
  set backendUsername(String? u) {
    _backendUsername = u;
    _persistBackendUsername(u);
  }

  static const _kBackendLoginKey = 'backend_logged_in';
  static const _kBackendUserIdKey = 'backend_user_id';
  static const _kBackendUsernameKey = 'backend_username';
  Future<void> _persistBackendLogin(bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kBackendLoginKey, v);
    } catch (_) {}
  }

  Future<void> _persistBackendUserId(int? id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (id == null) {
        await sp.remove(_kBackendUserIdKey);
      } else {
        await sp.setInt(_kBackendUserIdKey, id);
      }
    } catch (_) {}
  }

  Future<void> _persistBackendUsername(String? u) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (u == null || u.isEmpty) {
        await sp.remove(_kBackendUsernameKey);
      } else {
        await sp.setString(_kBackendUsernameKey, u);
      }
    } catch (_) {}
  }

  Future<void> _restoreBackendLogin() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getBool(_kBackendLoginKey) ?? false;
      _backendLoggedIn = v;
      backendLoginNotifier.value = v;
      _backendUserId = sp.getInt(_kBackendUserIdKey);
      _backendUsername = sp.getString(_kBackendUsernameKey);
    } catch (_) {}
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

  Future<void> signOut() async {
    await _client.auth.signOut();
    backendLoggedIn = false; // will persist and notify
    backendUserId = null;
    backendUsername = null;
  }
}
