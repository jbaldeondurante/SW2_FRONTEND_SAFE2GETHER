// lib/features/auth/auth_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // LogicalKeyboardKey
import '../../core/supabase_service.dart';
import '../../core/api_client.dart';
import 'package:go_router/go_router.dart';
import '../../core/env.dart';
import '../../core/responsive_utils.dart';

class AuthPage extends StatefulWidget {
  final SupabaseService auth;
  final ApiClient api;
  const AuthPage({super.key, required this.auth, required this.api});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  final _userNode = FocusNode();
  final _emailNode = FocusNode();
  final _passNode = FocusNode();

  bool _isLogin = true;
  bool _busy = false;
  String? _msg;
  String _fase = '';

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _userNode.dispose();
    _emailNode.dispose();
    _passNode.dispose();
    super.dispose();
  }

  Future<T> _withPhase<T>(String fase, Future<T> Function() run) async {
    setState(() => _fase = fase);
    return await run();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _msg = null;
      _fase = '';
    });

    final user = _username.text.trim();
    final email = _email.text.trim();
    final pass = _password.text;

    try {
      if (_isLogin) {
        // LOGIN: solo backend con user + psswd (no pedimos email en la UI)
        final backend = await _withPhase('Login API', () async {
          return await widget.api.loginBackend(user: user, psswd: pass);
        });

        // Éxito si viene access_token y no hay detail
        final code = backend['status'] as int?; // lo inyecta ApiClient
        String? detail;
        if (backend['detail'] is String) {
          detail = backend['detail'] as String;
        } else if (backend['data'] is Map) {
          final m = backend['data'] as Map;
          if (m['detail'] is String) detail = m['detail'] as String;
        } else if (backend['data'] is List) {
          final list = backend['data'] as List;
          if (list.isNotEmpty &&
              list.first is Map &&
              (list.first as Map)['detail'] is String) {
            detail = (list.first as Map)['detail'] as String;
          }
        }

        final token =
            backend['access_token'] as String? ??
            (backend['data'] is Map
                ? (backend['data'] as Map)['access_token'] as String?
                : null);
        final hasToken = token != null && token.isNotEmpty;
        final ok = (code == 200 || code == null) && hasToken && detail == null;
        if (!ok) {
          setState(
            () => _msg =
                'Login fallido: ${detail ?? 'respuesta inválida de la API'}',
          );
          return;
        }

        // Éxito: guardar datos y navegar
        setState(() => _msg = 'Login OK');
        if (mounted) {
          try {
            widget.auth.backendLoggedIn = true;

            // ID de usuario
            dynamic id =
                backend['user_id'] ?? backend['id'] ?? backend['userId'];
            if (id == null && backend['data'] is Map) {
              final m = backend['data'] as Map;
              id =
                  m['user_id'] ??
                  m['id'] ??
                  m['userId'] ??
                  (m['user'] is Map
                      ? (m['user']['id'] ??
                            m['user']['user_id'] ??
                            m['user']['userId'])
                      : null);
            }
            if (id == null && backend['user'] is Map) {
              final um = backend['user'] as Map;
              id = um['id'] ?? um['user_id'] ?? um['userId'];
            }
            if (id is int) {
              widget.auth.backendUserId = id;
            } else if (id is String) {
              final parsed = int.tryParse(id);
              if (parsed != null) widget.auth.backendUserId = parsed;
            }

            // Username (puede venir en user.user / user.username / name)
            String? uname;
            if (backend['user'] is Map) {
              final um = backend['user'] as Map;
              final candidate = um['user'] ?? um['username'] ?? um['name'];
              if (candidate is String) uname = candidate;
            }
            uname ??= (backend['username'] ?? backend['name']) as String?;
            if (uname != null && uname.isNotEmpty)
              widget.auth.backendUsername = uname;

            // Guardar access_token del backend
            if (hasToken) {
              widget.auth.backendAccessToken = token;
              ApiClient.backendAccessToken = token;
            }
          } catch (_) {}
          context.go('/reportes');
        }
      } else {
        // REGISTRO: primero Supabase (envía correo), luego tu API (crea fila)
        await _withPhase('Registro Supabase', () async {
          return await widget.auth.signUpWithEmail(
            email,
            pass,
            redirectTo: Env.supabaseRedirectUrl,
          );
        });

        final created = await _withPhase('Registro API', () async {
          return await widget.api.createUser(
            user: user,
            email: email,
            psswd: pass,
          );
        });

        setState(
          () => _msg =
              'Te enviamos un correo para confirmar. Luego podrás iniciar sesión.\n(API: ${created['status'] ?? '201'})',
        );
      }
    } catch (e) {
      // Si algo falla después de haber creado sesión en Supabase, asegura limpiar.
      await widget.auth.signOut();
      setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deviceType = ResponsiveHelper.getDeviceType(context);
    final maxWidth = deviceType == DeviceType.mobile 
        ? double.infinity 
        : deviceType == DeviceType.tablet 
            ? 500.0 
            : 460.0;
    final padding = ResponsiveHelper.getPadding(context, factor: 0.75);
    final logoSize = ResponsiveHelper.getFontSize(context, 85);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
      },
      child: FocusTraversalGroup(
        child: Scaffold(
          backgroundColor: const Color(0xFF08192D),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: padding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/SS.png',
                            height: logoSize,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                FlutterLogo(size: logoSize),
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.getVerticalSpacing(context) * 0.75),

                        Card(
                          child: Padding(
                            padding: ResponsiveHelper.getPadding(context, factor: 0.67),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _isLogin ? 'Iniciar sesión' : 'Crear cuenta',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 12),

                                // Usuario (tu backend lo requiere)
                                TextFormField(
                                  controller: _username,
                                  focusNode: _userNode,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Usuario',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty)
                                      return 'Ingresa tu usuario';
                                    if (v.trim().length < 3)
                                      return 'Mínimo 3 caracteres';
                                    return null;
                                  },
                                  onFieldSubmitted: (_) => _isLogin
                                      ? _passNode.requestFocus()
                                      : _emailNode.requestFocus(),
                                ),
                                const SizedBox(height: 8),
                                if (!_isLogin) ...[
                                  // Email (necesario solo para registro en Supabase)
                                  TextFormField(
                                    controller: _email,
                                    focusNode: _emailNode,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon: Icon(Icons.email_outlined),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty)
                                        return 'Ingresa tu email';
                                      if (!v.contains('@'))
                                        return 'Email no válido';
                                      return null;
                                    },
                                    onFieldSubmitted: (_) =>
                                        _passNode.requestFocus(),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                // Password
                                TextFormField(
                                  controller: _password,
                                  focusNode: _passNode,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: Icon(Icons.lock_outline),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty)
                                      return 'Ingresa tu contraseña';
                                    if (v.length < 6)
                                      return 'Mínimo 6 caracteres';
                                    return null;
                                  },
                                  onFieldSubmitted: (_) => _submit(),
                                ),
                                // 🆕 Botón de recuperar contraseña (solo en modo login)
                                if (_isLogin) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => context.go('/password-reset'),
                                      child: const Text(
                                        '¿Olvidaste tu contraseña?',
                                        style: TextStyle(
                                          color: Color(0xFF9B080C),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 12),

                                const SizedBox(height: 12),

                                if (_fase.isNotEmpty)
                                  Text(
                                    'Fase: $_fase',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                if (_msg != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _msg!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          _msg!.startsWith('Login OK') ||
                                              _msg!.startsWith('Te enviamos')
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),

                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF9B080C,
                                          ),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: _busy ? null : _submit,
                                        child: _busy
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : Text(
                                                _isLogin
                                                    ? 'Entrar'
                                                    : 'Crear cuenta',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                          _isLogin = !_isLogin;
                                          _msg = null;
                                          _fase = '';
                                        }),
                                  child: Text(
                                    _isLogin
                                        ? '¿Crear cuenta?'
                                        : '¿Ya tengo cuenta?',
                                    style: const TextStyle(
                                      color: Color(0xFF9B080C),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
