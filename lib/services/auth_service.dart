import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Auth flows (PRD §5.1).
/// - Signup: username 3–24 [a-z0-9_], email, password min 12 + confirm.
///   Server (GOTRUE_PASSWORD_MIN_LENGTH) enforces 12 instance-wide.
///   No email confirmation; session starts immediately; a `profiles` row is
///   created with username_normalized = lowercase.
/// - Login: username-or-email. Bare usernames are resolved to an email
///   server-side by the `financemuse-login` Edge Function; errors are
///   always generic.
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
    // Server minimum is 12 (GOTRUE_PASSWORD_MIN_LENGTH instance-wide);
    // the old min-8 client check let 8-11 char passwords through, only for
    // Supabase Auth to reject them with a hidden generic error.
    if (value.length < 12) return 'Kata sandi minimal 12 karakter.';
    // PRD §5.1: password must not EQUAL username/email, not merely
    // contain it. The old substring check rejected good passwords such
    // as 'Kuat-adoetz-2026' for username 'adoetz'.
    final pw = value.trim().toLowerCase();
    if (username != null && username.trim().isNotEmpty &&
        pw == username.trim().toLowerCase()) {
      return 'Kata sandi tidak boleh sama dengan username.';
    }
    if (email != null && email.trim().isNotEmpty) {
      final mail = email.trim().toLowerCase();
      final local = mail.split('@').first;
      if (pw == mail || (local.isNotEmpty && pw == local)) {
        return 'Kata sandi tidak boleh sama dengan email.';
      }
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
    // An APK built without the anon key can never reach Auth. Say so
    // plainly instead of letting the call fail as 'Pendaftaran gagal'.
    if (!SupabaseConfig.isConfigured) {
      throw SupabaseFailure(
        'APK ini tidak memiliki kunci server. Install APK terbaru '
        '(build terbaru) lalu coba lagi.',
      );
    }
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'app': 'financemuse',
          'username': normalized,
          'display_name': normalized,
        },
      );
      // With email auto-confirm the session is returned immediately.
      final user = res.user ?? res.session?.user;
      if (user == null) {
        throw SupabaseFailure('Pendaftaran gagal. Coba lagi.');
      }
      // The profile row is created by the adoetz_signup trigger (scoped
      // financemuse branch) -- the trigger is the single writer. Verify
      // it exists, with retries for trigger/PostgREST timing.
      //
      // CRITICAL: once the account + session exist, signup SUCCEEDED.
      // A slow/unreadable profile row must NEVER be reported as
      // 'Pendaftaran gagal' -- the account exists, so a retry would only
      // hit 'Email sudah terdaftar' and the user is stuck. The dashboard
      // loads the profile lazily instead.
      var found = false;
      for (var attempt = 0; attempt < 3 && !found; attempt++) {
        if (attempt > 0) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
        try {
          final profile = await _client
              .table('profiles')
              .select('user_id')
              .eq('user_id', user.id)
              .limit(1);
          found = profile.isNotEmpty;
        } catch (_) {
          // Transient PostgREST/JWT error: retry, do not fail signup.
        }
      }
      // found == false + valid session: proceed anyway (see above).
    } catch (e) {
      if (e is SupabaseFailure) rethrow;
      // Signup errors are specific and actionable (see mapSignupError);
      // only login stays generic per PRD §5.1.
      throw mapSignupError(e);
    }
  }

  /// Login with username or email. Generic error on any failure.
  /// Bare usernames are resolved to an email server-side by the
  /// `financemuse-login` Edge Function (financemuse.resolve_login_email);
  /// the email is never returned to the client and never queried from
  /// the app. Email logins go through the same function so every failure
  /// — unknown username, unknown email, wrong password — is an identical
  /// generic 401 with no enumeration leak.
  Future<void> signIn({required String login, required String password}) async {
    final input = login.trim();
    try {
      final res = await _client.functions.invoke(
        'financemuse-login',
        body: {'identifier': input, 'password': password},
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        throw SupabaseFailure('Email atau kata sandi salah.');
      }
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      if (accessToken == null || refreshToken == null) {
        throw SupabaseFailure('Email atau kata sandi salah.');
      }
      // gotrue 2.x: refresh token is positional, access token named.
      final session = await _client.auth.setSession(refreshToken, accessToken: accessToken);
      final user = session.user;
      if (user == null) {
        throw SupabaseFailure('Email atau kata sandi salah.');
      }
      await _assertNotSuspended(user.id);
    } on SupabaseFailure {
      rethrow;
    } on FunctionException {
      // Edge Function returned 4xx (unknown user / wrong password) or
      // 5xx — either way the login failed; stay generic, no enumeration.
      throw SupabaseFailure('Email atau kata sandi salah.');
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
      // If profiles cannot be read, do not block login on a check we
      // cannot perform — the server must enforce suspension (PRD §5.1:
      // status dipastikan server-side).
    }
  }

  /// Change password with the old password (reauthenticate first).
  Future<void> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    final passwordError = validatePassword(newPassword);
    if (passwordError != null) throw SupabaseFailure(passwordError);
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: oldPassword,
      );
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      if (e is SupabaseFailure) rethrow;
      if (e is AuthException) {
        final msg = e.message.toLowerCase();
        if ((e.code ?? '').toLowerCase() == 'weak_password' ||
            msg.contains('at least 12') ||
            msg.contains('too short') ||
            msg.contains('password should be')) {
          throw SupabaseFailure('Kata sandi minimal 12 karakter.', raw: e);
        }
      }
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
