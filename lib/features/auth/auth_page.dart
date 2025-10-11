import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // LogicalKeyboardKey
import '../../core/supabase_service.dart';

class AuthPage extends StatefulWidget {
  final SupabaseService auth;
  const AuthPage({super.key, required this.auth});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  final _emailNode = FocusNode();
  final _passNode = FocusNode();

  bool _isLogin = true;
  bool _busy = false;
  String? _msg;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailNode.dispose();
    _passNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    // validaciones simples
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final email = _email.text.trim();
      final pass = _password.text;

      if (_isLogin) {
        await widget.auth.signInWithEmail(email, pass);
        setState(() => _msg = 'OK');
      } else {
        await widget.auth.signUpWithEmail(email, pass);
        setState(() => _msg = 'Cuenta creada. Revisa tu correo.');
      }
      // No navegamos manualmente: el router reacciona al cambio de sesión.
    } catch (e) {
      setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Atajo global: Enter / NumpadEnter => submit
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
      },
      child: FocusTraversalGroup(
        child: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // LOGO
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/safe2gether_logo.png',
                        height: 96,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const FlutterLogo(size: 96),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Safe2Gether',
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 24),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_isLogin ? 'Iniciar sesión' : 'Crear cuenta',
                                  style: theme.textTheme.titleLarge),
                              const SizedBox(height: 12),

                              // Email
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
                                  if (v == null || v.trim().isEmpty) return 'Ingresa tu email';
                                  if (!v.contains('@')) return 'Email no válido';
                                  return null;
                                },
                                onFieldSubmitted: (_) {
                                  // Enter en email => mover foco a password
                                  _passNode.requestFocus();
                                },
                              ),
                              const SizedBox(height: 8),

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
                                  if (v == null || v.isEmpty) return 'Ingresa tu contraseña';
                                  if (v.length < 6) return 'Mínimo 6 caracteres';
                                  return null;
                                },
                                onFieldSubmitted: (_) => _submit(), // Enter en password => enviar
                              ),
                              const SizedBox(height: 12),

                              if (_msg != null)
                                Text(
                                  _msg!,
                                  style: TextStyle(
                                    color: _msg == 'OK' ? Colors.green : Colors.red,
                                  ),
                                ),
                              const SizedBox(height: 12),

                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _busy ? null : _submit,
                                      child: _busy
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : Text(_isLogin ? 'Entrar' : 'Crear cuenta'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _busy ? null : () => setState(() => _isLogin = !_isLogin),
                                child: Text(_isLogin ? '¿Crear cuenta?' : '¿Ya tengo cuenta?'),
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
    );
  }
}
