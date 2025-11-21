import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';

class SupabaseService {
  Future<String?> uploadImage(File imageFile) async {
    try {
      final supabase = Supabase.instance.client;
      final fileName =
          'reportes/${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';
      final response = await supabase.storage
          .from('adjuntos')
          .upload(fileName, imageFile);
      if (response.isNotEmpty) {
        final publicUrl = supabase.storage
            .from('adjuntos')
            .getPublicUrl(fileName);
        return publicUrl;
      } else {
        print('Error al subir imagen: $response');
        return null;
      }
    } catch (e) {
      print('Excepción al subir imagen: $e');
      return null;
    }
  }

  Future<String?> uploadImageWeb() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return null;
      final supabase = Supabase.instance.client;
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final response = await supabase.storage
          .from('adjuntos')
          .uploadBinary(fileName, bytes);
      if (response.isNotEmpty) {
        final publicUrl = supabase.storage
            .from('adjuntos')
            .getPublicUrl(fileName);
        return publicUrl;
      } else {
        print('Error al subir imagen (web): $response');
        return null;
      }
    } catch (e) {
      print('Excepción al subir imagen (web): $e');
      return null;
    }
  }

  final SupabaseClient _client;
  bool _backendLoggedIn = false;
  int? _backendUserId;
  String? _backendUsername;
  String? _backendAccessToken;
  final ValueNotifier<bool> backendLoginNotifier = ValueNotifier(false);
  late final Future<void> ready;

  SupabaseService(this._client) {
    ready = _restoreBackendLogin();
  }

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

  String? get backendAccessToken => _backendAccessToken;
  set backendAccessToken(String? t) {
    _backendAccessToken = t;
    _persistBackendToken(t);
  }

  static const _kBackendLoginKey = 'backend_logged_in';
  static const _kBackendUserIdKey = 'backend_user_id';
  static const _kBackendUsernameKey = 'backend_username';
  static const _kBackendTokenKey = 'backend_token';
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

  Future<void> _persistBackendToken(String? t) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (t == null || t.isEmpty) {
        await sp.remove(_kBackendTokenKey);
      } else {
        await sp.setString(_kBackendTokenKey, t);
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
      _backendAccessToken = sp.getString(_kBackendTokenKey);
    } catch (_) {}
  }

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
    backendLoggedIn = false;
    backendUserId = null;
    backendUsername = null;
    backendAccessToken = null;
  }
}
