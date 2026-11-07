import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.isSignUp});
  final bool isSignUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = AppState.instance.auth;
      if (widget.isSignUp) {
        await auth.signUp(
          username: _usernameCtrl.text,
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
      } else {
        await auth.signIn(
          login: _usernameCtrl.text,
          password: _passwordCtrl.text,
        );
      }
      await AppState.instance.refreshRole();
      if (mounted) context.go('/dashboard');
    } on SupabaseFailure catch (e) {
      setState(() => _error = e.message);
    } on AuthException {
      setState(() => _error = 'Email atau kata sandi salah.');
    } catch (e) {
      setState(() => _error = mapSupabaseError(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignUp = widget.isSignUp;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.account_balance, size: 48),
                  const SizedBox(height: AppSpacing.s16),
                  Text(
                    isSignUp ? 'Buat Akun' : 'Masuk',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    isSignUp
                        ? 'Username + email + kata sandi. Tanpa konfirmasi email.'
                        : 'Masuk dengan username atau email.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.s24),
                  const ConfigNotice(),
                  if (_error != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: context.finance.negative)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                  ],
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: InputDecoration(
                      labelText:
                          isSignUp ? 'Username' : 'Username atau Email',
                      helperText: isSignUp
                          ? '3–24 karakter: huruf kecil, angka, underscore.'
                          : null,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Wajib diisi.';
                      }
                      if (isSignUp) {
                        return AuthService.validateUsername(v);
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  if (isSignUp) ...[
                    TextFormField(
                      controller: _emailCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || !v.contains('@')) {
                          return 'Format email tidak valid.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.s16),
                  ],
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Kata Sandi'),
                    obscureText: true,
                    validator: (v) => AuthService.validatePassword(
                      v ?? '',
                      username: _usernameCtrl.text,
                      email: isSignUp ? _emailCtrl.text : null,
                    ),
                  ),
                  if (isSignUp) ...[
                    const SizedBox(height: AppSpacing.s16),
                    TextFormField(
                      controller: _confirmCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Konfirmasi Kata Sandi'),
                      obscureText: true,
                      validator: (v) {
                        if (v != _passwordCtrl.text) {
                          return 'Konfirmasi kata sandi tidak cocok.';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s24),
                  ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy
                        ? 'Memproses…'
                        : (isSignUp ? 'Daftar' : 'Masuk')),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  TextButton(
                    onPressed: () => context.go(
                        isSignUp ? '/auth/login' : '/auth/sign-up'),
                    child: Text(isSignUp
                        ? 'Sudah punya akun? Masuk'
                        : 'Belum punya akun? Daftar'),
                  ),
                  if (!isSignUp) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Tidak ada pemulihan kata sandi mandiri di v1. '
                      'Hubungi admin untuk reset.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
