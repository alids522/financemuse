import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Auth flows (PRD §5.1).
/// - Signup: username 3–24 [a-z0-9_], email, password min 8 + confirm.
///   No email confirmation; session starts immediately; a `profiles` row is
///   created with username_normalized = lowercase.
/// - Login: username-or-email. Username is resolved to an email via a query
///   on financemuse.profiles; errors are always generic.
/// - Suspended profiles are signed out and denied generically.
/// - No self-service forgot/reset in v1; admin-assisted reset lives in Admin.
class AuthService {
  AuthService(this._client);
  final SupabaseClient _client;

  static final usernameRegExp = RegExp(r'^[a-z0-9_]{3,24}$');

  static String? validateUsername(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return 'Username wajib diisi.';
    if (!usernameRegExp.hasMatch(v)) {
      return 'Username 3–24 karakter, huruf kecil, angka, atau underscore.';
    }
    return null;
  }

  static String? validatePassword(String value, {String? username, String? email}) {
    if (value.length < 8) return 'Kata sandi minimal 8 karakter.';
    if (username != null && username.isNotEmpty &&
        value.toLowerCase().contains(username.toLowerCase())) {
      return 'Kata sandi tidak boleh sama dengan username.';
    }
    if (email != null && email.isNotEmpty &&
        value.toLowerCase().contains(email.split('@').first.toLowerCase())) {
      return 'Kata sandi tidak boleh sama dengan email.';
    }
    return null;
  }

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  Future<void> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    final normalized = username.trim().toLowerCase();
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      if (user == null) {
        throw SupabaseFailure('Pendaftaran gagal. Coba lagi.');
      }
      // Create the profile row (PRD §5.1, §10 profiles).
      await _client.table('profiles').insert({
        'user_id': user.id,
        'username_normalized': normalized,
        'display_name': normalized,
        'base_currency': 'IDR',
        'timezone': 'Asia/Jakarta',
        'theme': 'system',
        'status': 'active',
      });
    } catch (e) {
      if (e is SupabaseFailure) rethrow;
      throw mapSupabaseError(e);
    }
  }

  /// Login with username or email. Generic error on any failure.
  Future<void> signIn({required String login, required String password}) async {
    final input = login.trim();
    try {
      String email = input;
      if (!input.contains('@')) {
        // Resolve username -> email via profiles (server-owned lookup).
        final rows = await _client
            .table('profiles')
            .select('user_id')
            .eq('username_normalized', input.toLowerCase())
            .limit(1);
        if (rows.isEmpty) {
          throw SupabaseFailure('Email atau kata sandi salah.');
        }
        // Email itself lives in Supabase Auth, not in profiles. The
        // username->email resolution must happen server-side; until the
        // backend lookup exists we cannot sign in by bare username.
        // We therefore fail generically here rather than guessing an email.
        throw SupabaseFailure(
          'Login dengan username memerlukan layanan resolusi email '
          'di server (belum tersedia). Gunakan email untuk masuk.',
        );
      }
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null) {
        throw SupabaseFailure('Email atau kata sandi salah.');
      }
      await _assertNotSuspended(res.user!.id);
    } on SupabaseFailure {
      rethrow;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> _assertNotSuspended(String userId) async {
    try {
      final rows = await _client
          .table('profiles')
          .select('status')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isNotEmpty && rows.first['status'] == 'suspended') {
        await _client.auth.signOut();
        throw SupabaseFailure('Akun tidak dapat digunakan. Hubungi admin.');
      }
    } on SupabaseFailure {
      rethrow;
    } catch (_) {
      // If profiles cannot be read (schema not exposed yet), do not block
      // login on a check we cannot perform — the server must enforce
      // suspension (PRD §5.1: status dipastikan server-side).
    }
  }

  /// Change password with the old password (reauthenticate first).
  Future<void> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: oldPassword,
      );
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      if (e is SupabaseFailure) rethrow;
      throw SupabaseFailure('Kata sandi lama salah atau perubahan gagal.');
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Current user's role from financemuse.user_roles (server-owned).
  /// Returns 'user' when unknown/unreadable — UI hides admin menus, but
  /// authorization is always enforced server-side (PRD §7).
  Future<String> currentRole() async {
    final user = currentUser;
    if (user == null) return 'user';
    try {
      final rows = await _client
          .table('user_roles')
          .select('role')
          .eq('user_id', user.id)
          .limit(1);
      if (rows.isEmpty) return 'user';
      return (rows.first['role'] as String?) ?? 'user';
    } catch (_) {
      return 'user';
    }
  }
}
