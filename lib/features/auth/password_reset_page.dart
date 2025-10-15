// lib/features/auth/password_reset_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../core/env.dart';

class PasswordResetPage extends StatefulWidget {
  final String? token;
  const PasswordResetPage({super.key, this.token});

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isLoading = false;
  String? _message;
  bool _isError = false;
  bool _isResetMode = false;
  String? _validatedEmail;

  @override
  void initState() {
    super.initState();
    if (widget.token != null) {
      _validateToken();
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  /// Valida el token de recuperación
  Future<void> _validateToken() async {
    setState(() => _isLoading = true);

    try {
      final res = await http.get(
        Uri.parse(
          '${Env.apiBaseUrl}/users/password/validate-token/${widget.token}',
        ),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _isResetMode = true;
          _validatedEmail = data['email'];
          _message = 'Token válido. Ingresa tu nueva contraseña.';
          _isError = false;
        });
      } else {
        final error = jsonDecode(res.body);
        setState(() {
          _message = error['detail'] ?? 'Token inválido o expirado';
          _isError = true;
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error validando token: $e';
        _isError = true;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Solicita el reset de contraseña
  Future<void> _requestReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${Env.apiBaseUrl}/users/password/request-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _emailCtrl.text.trim()}),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        setState(() {
          _message = data['message'];
          _isError = false;
        });

        // 🔧 SOLO PARA DESARROLLO: mostrar el link
        if (data['reset_link'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Link de prueba: ${data['reset_link']}'),
              duration: const Duration(seconds: 10),
              action: SnackBarAction(
                label: 'Copiar',
                onPressed: () {
                  // Implementar copiar al portapapeles
                },
              ),
            ),
          );
        }
      } else {
        setState(() {
          _message = data['detail'] ?? 'Error al solicitar reset';
          _isError = true;
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error: $e';
        _isError = true;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Resetea la contraseña con el token
  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() {
        _message = 'Las contraseñas no coinciden';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${Env.apiBaseUrl}/users/password/reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.token,
          'new_password': _passwordCtrl.text,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        setState(() {
          _message = data['message'];
          _isError = false;
        });

        // Redirigir al login después de 2 segundos
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) context.go('/login');
        });
      } else {
        setState(() {
          _message = data['detail'] ?? 'Error al resetear contraseña';
          _isError = true;
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error: $e';
        _isError = true;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08192D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/SS.png',
                    height: 85,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const FlutterLogo(size: 96),
                  ),
                ),
                const SizedBox(height: 24),

                // Card principal
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _isLoading
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Validando...'),
                              ],
                            ),
                          )
                        : _isResetMode
                        ? _buildResetForm()
                        : _buildRequestForm(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Formulario para solicitar reset
  Widget _buildRequestForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_reset, size: 64, color: Color(0xFF9B080C)),
          const SizedBox(height: 16),
          Text(
            '¿Olvidaste tu contraseña?',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Ingresa tu email y te enviaremos un link para recuperarla',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Email
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Ingresa tu email';
              if (!v.contains('@')) return 'Email no válido';
              return null;
            },
          ),

          const SizedBox(height: 24),

          // Mensaje
          if (_message != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isError
                    ? Colors.red.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isError ? Colors.red : Colors.green),
              ),
              child: Row(
                children: [
                  Icon(
                    _isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: _isError ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _isError ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Botón
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9B080C),
                foregroundColor: Colors.white,
              ),
              onPressed: _isLoading ? null : _requestReset,
              child: const Text('Enviar link de recuperación'),
            ),
          ),

          const SizedBox(height: 8),

          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text(
              'Volver al inicio de sesión',
              style: TextStyle(color: Color(0xFF9B080C)),
            ),
          ),
        ],
      ),
    );
  }

  /// Formulario para resetear contraseña
  Widget _buildResetForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_open, size: 64, color: Color(0xFF9B080C)),
          const SizedBox(height: 16),
          Text(
            'Nueva contraseña',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (_validatedEmail != null)
            Text(
              'Para: $_validatedEmail',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 24),

          // Nueva contraseña
          TextFormField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Nueva contraseña',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Ingresa tu contraseña';
              if (v.length < 6) return 'Mínimo 6 caracteres';
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Confirmar contraseña
          TextFormField(
            controller: _confirmPasswordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirmar contraseña',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Confirma tu contraseña';
              if (v != _passwordCtrl.text)
                return 'Las contraseñas no coinciden';
              return null;
            },
          ),

          const SizedBox(height: 24),

          // Mensaje
          if (_message != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isError
                    ? Colors.red.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isError ? Colors.red : Colors.green),
              ),
              child: Row(
                children: [
                  Icon(
                    _isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: _isError ? Colors.red : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _isError ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Botón
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9B080C),
                foregroundColor: Colors.white,
              ),
              onPressed: _isLoading ? null : _resetPassword,
              child: const Text('Cambiar contraseña'),
            ),
          ),
        ],
      ),
    );
  }
}
