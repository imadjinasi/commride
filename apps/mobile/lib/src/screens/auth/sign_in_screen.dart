import 'package:flutter/material.dart';

import '../../auth/auth_gateway.dart';
import '../../widgets/commride_brand.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({required this.authGateway, super.key});

  final AuthGateway authGateway;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _creatingAccount = false;
  bool _submitting = false;
  bool _resettingPassword = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Align(
                      alignment: Alignment.center,
                      child: CommRideBrandImage(
                        variant: CommRideBrandVariant.primary,
                        width: 220,
                        height: 96,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ride Connected.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    Text(
                      _creatingAccount ? 'Buat akun' : 'Masuk',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      autofillHints: const <String>[AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      autofillHints: const <String>[AutofillHints.password],
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Kata sandi',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (!_creatingAccount) ...<Widget>[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _submitting || _resettingPassword
                              ? null
                              : _resetPassword,
                          child: Text(
                            _resettingPassword
                                ? 'Mengirim…'
                                : 'Lupa kata sandi?',
                          ),
                        ),
                      ),
                    ],
                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(
                        _submitting
                            ? 'Memproses…'
                            : _creatingAccount
                            ? 'Buat akun'
                            : 'Masuk',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              setState(() {
                                _creatingAccount = !_creatingAccount;
                                _errorMessage = null;
                              });
                            },
                      child: Text(
                        _creatingAccount
                            ? 'Sudah punya akun? Masuk'
                            : 'Belum punya akun? Buat akun',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Izin lokasi tidak diminta saat membuat akun. '
                      'CommRide baru akan meminta izin lokasi ketika fitur '
                      'Ride yang membutuhkannya digunakan.',
                      style: Theme.of(context).textTheme.bodyMedium,
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

  Future<void> _resetPassword() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorMessage =
            'Masukkan email terlebih dahulu untuk reset kata sandi.';
      });
      return;
    }

    final AuthGateway authGateway = widget.authGateway;
    if (authGateway is! PasswordResetAuthGateway) {
      setState(() {
        _errorMessage = 'Reset kata sandi belum tersedia pada konfigurasi ini.';
      });
      return;
    }
    final PasswordResetAuthGateway passwordResetGateway =
        authGateway as PasswordResetAuthGateway;

    setState(() {
      _resettingPassword = true;
      _errorMessage = null;
    });

    try {
      await passwordResetGateway.sendPasswordResetEmail(email: email);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Jika email terdaftar, tautan reset kata sandi akan dikirim.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Reset kata sandi belum dapat dikirim. Periksa email dan koneksi.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _resettingPassword = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Email dan kata sandi wajib diisi.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      if (_creatingAccount) {
        await widget.authGateway.createAccount(
          email: email,
          password: password,
        );
      } else {
        await widget.authGateway.signIn(email: email, password: password);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'Tidak dapat melanjutkan. Periksa email, kata sandi, '
            'dan koneksi Anda.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}
