import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// Settings (PRD §8.4): profile, theme, base currency IDR,
/// timezone Asia/Jakarta, week start, change password.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  String? _msg;
  int _weekStart = DateTime.monday;

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.email == null) {
      setState(() => _msg = 'Email pengguna tidak tersedia.');
      return;
    }
    try {
      await AppState.instance.auth.changePassword(
        email: user!.email!,
        oldPassword: _oldCtrl.text,
        newPassword: _newCtrl.text,
      );
      setState(() => _msg = 'Kata sandi berhasil diubah.');
    } on SupabaseFailure catch (e) {
      setState(() => _msg = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final user = Supabase.instance.client.auth.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pengaturan',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Profil',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    Text('Email: ${user?.email ?? '-'}'),
                    Text('User ID: ${user?.id ?? '-'}'),
                    Text('Role: ${state.role}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tampilan & Regional',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    DropdownButtonFormField<ThemeMode>(
                      initialValue: state.themeMode,
                      decoration:
                          const InputDecoration(labelText: 'Tema'),
                      items: const [
                        DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('Sistem')),
                        DropdownMenuItem(
                            value: ThemeMode.dark, child: Text('Gelap')),
                        DropdownMenuItem(
                            value: ThemeMode.light, child: Text('Terang')),
                      ],
                      onChanged: (v) {
                        if (v != null) state.setTheme(v);
                      },
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    const Text('Mata uang dasar: IDR (tetap di v1)'),
                    const Text('Zona waktu: Asia/Jakarta'),
                    const SizedBox(height: AppSpacing.s12),
                    DropdownButtonFormField<int>(
                      initialValue: _weekStart,
                      decoration: const InputDecoration(
                          labelText: 'Awal minggu'),
                      items: const [
                        DropdownMenuItem(
                            value: DateTime.monday, child: Text('Senin')),
                        DropdownMenuItem(
                            value: DateTime.sunday, child: Text('Minggu')),
                      ],
                      onChanged: (v) =>
                          setState(() => _weekStart = v ?? DateTime.monday),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ubah Kata Sandi',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    TextField(
                      controller: _oldCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Kata sandi lama'),
                      obscureText: true,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    TextField(
                      controller: _newCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Kata sandi baru (min. 8 karakter)'),
                      obscureText: true,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    ElevatedButton(
                      onPressed: _changePassword,
                      child: const Text('Ubah Kata Sandi'),
                    ),
                    if (_msg != null) ...[
                      const SizedBox(height: AppSpacing.s8),
                      Text(_msg!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
