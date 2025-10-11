import 'package:flutter/material.dart';
import '../../core/supabase_service.dart';

class AuthPage extends StatefulWidget {
  final SupabaseService auth;
  const AuthPage({super.key, required this.auth});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;
  String? _msg;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      if (_isLogin) {
        await widget.auth.signInWithEmail(_email.text.trim(), _password.text);
      } else {
        await widget.auth.signUpWithEmail(_email.text.trim(), _password.text);
      }
      setState(() => _msg = 'OK');
    } catch (e) {
      setState(() => _msg = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_isLogin ? 'Iniciar sesión' : 'Registrarse',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 8),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 12),
          if (_msg != null) Text(_msg!, style: TextStyle(color: _msg == 'OK' ? Colors.green : Colors.red)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const CircularProgressIndicator() : Text(_isLogin ? 'Entrar' : 'Crear cuenta'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? '¿Crear cuenta?' : '¿Ya tengo cuenta?'),
              ),
            ],
          )
        ]),
      ),
    );
  }
}
