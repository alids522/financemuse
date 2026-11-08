import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase bootstrap.
///
/// Config comes from --dart-define SUPABASE_URL / SUPABASE_ANON_KEY.
/// The anon key is never stored in the repo, never printed, and never
/// committed — it is passed only at build/run time.
///
/// The `financemuse` Postgres schema IS exposed via PostgREST
/// (PGRST_DB_SCHEMAS includes financemuse since 2026-11-07). Anon has
/// USAGE only, so unauthenticated calls fail; signed-in users work under
/// owner-only RLS. The app surfaces a clear in-app notice on failure
/// instead of faking data — see [SupabaseFailure.isSchemaNotExposed].
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://supabase.adoetz52.my.id',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => anonKey.isNotEmpty;

  /// Build marker, passed by CI as --dart-define APP_COMMIT=`<short sha>`.
  /// Shown in Settings and on the auth screen so a bug report can be
  /// tied to the exact APK build installed on the phone.
  static const String appCommit = String.fromEnvironment(
    'APP_COMMIT',
    defaultValue: 'dev',
  );

  /// Display version (mirrors pubspec.yaml).
  static const String appVersion = '1.0.0+6';

  static Future<void> init() async {
    // `anonKey` param is deprecated in supabase_flutter 2.18 in favour of
    // `publishableKey`; the --dart-define name stays SUPABASE_ANON_KEY.
    await Supabase.initialize(url: url, publishableKey: anonKey);
  }
}

class SupabaseFailure implements Exception {
  SupabaseFailure(this.message, {this.raw});
  final String message;
  final Object? raw;

  /// True when PostgREST cannot see the financemuse schema/tables yet.
  bool get isSchemaNotExposed {
    final hay = '$message ${raw ?? ''}'.toLowerCase();
    return hay.contains('schema') ||
        hay.contains('pgrst') ||
        hay.contains('could not find the table') ||
        hay.contains('relation') && hay.contains('does not exist') ||
        hay.contains('404');
  }

  @override
  String toString() => message;
}

/// Signup-specific error mapping: specific, actionable Indonesian
/// messages for the user's OWN input (weak password, email already
/// registered, username taken). This is safe on signup — it reveals
/// nothing about any unrelated account — but it must NEVER be used for
/// login, where every failure stays generic (PRD §5.1, no enumeration).
/// True when the failure is a transport problem (offline, DNS, timeout),
/// i.e. the request never reached the server. These must never surface as
/// a bare 'Pendaftaran gagal' - the user needs to know it is connectivity.
bool _isNetworkError(Object e) {
  final name = e.runtimeType.toString().toLowerCase();
  final msg = e.toString().toLowerCase();
  if (name.contains('socketexception') ||
      name.contains('clientexception') ||
      name.contains('timeoutexception') ||
      name.contains('httpexception')) {
    return true;
  }
  return msg.contains('failed host lookup') ||
      msg.contains('connection refused') ||
      msg.contains('network is unreachable') ||
      msg.contains('connection reset') ||
      msg.contains('timed out') ||
      msg.contains('no internet') ||
      msg.contains('unable to resolve host');
}

SupabaseFailure mapSignupError(Object e) {
  if (_isNetworkError(e)) {
    return SupabaseFailure(
      'Tidak dapat terhubung ke server. Periksa koneksi internet, '
      'lalu coba lagi.',
      raw: e,
    );
  }
  if (e is AuthException) {
    final msg = e.message.toLowerCase();
    final code = (e.code ?? '').toLowerCase();
    if (code == 'weak_password' ||
        msg.contains('at least 12') ||
        msg.contains('password should be') ||
        msg.contains('too short') ||
        msg.contains('weak password')) {
      return SupabaseFailure('Kata sandi minimal 12 karakter.', raw: e);
    }
    if (msg.contains('already registered') ||
        msg.contains('already exists') ||
        msg.contains('user already')) {
      return SupabaseFailure('Email sudah terdaftar. Silakan masuk.', raw: e);
    }
    if (msg.contains('invalid email') || msg.contains('email address')) {
      return SupabaseFailure('Format email tidak valid.', raw: e);
    }
    if (msg.contains('username already') ||
        msg.contains('already taken') ||
        msg.contains('duplicate key') ||
        msg.contains('23505')) {
      return SupabaseFailure(
          'Username sudah dipakai. Pilih username lain.',
          raw: e);
    }
    if (msg.contains('invitation only')) {
      return SupabaseFailure('Pendaftaran memerlukan undangan.', raw: e);
    }
    if (msg.contains('invitation unavailable')) {
      return SupabaseFailure('Undangan tidak tersedia.', raw: e);
    }
    if (msg.contains('password')) {
      return SupabaseFailure(
          'Kata sandi tidak memenuhi syarat. Gunakan minimal 12 karakter.',
          raw: e);
    }
    if (msg.contains('database error saving new user') ||
        msg.contains('database error')) {
      return SupabaseFailure(
          'Pendaftaran gagal di server. Coba lagi; jika berlanjut, '
          'hubungi admin.',
          raw: e);
    }
    if (msg.contains('signup disabled') ||
        msg.contains('signups not allowed')) {
      return SupabaseFailure(
          'Pendaftaran sedang dimatikan di server.', raw: e);
    }
    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return SupabaseFailure(
          'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.',
          raw: e);
    }
    return SupabaseFailure('Pendaftaran gagal. Coba lagi.', raw: e);
  }
  if (e is PostgrestException) {
    return SupabaseFailure('Pendaftaran gagal. Coba lagi.', raw: e);
  }
  return SupabaseFailure('Pendaftaran gagal. Coba lagi.', raw: e);
}

/// Map a Supabase/PostgREST error to a user-facing failure. Generic messages
/// only — never leak whether an account exists (PRD §5.1).
SupabaseFailure mapSupabaseError(Object e) {
  if (e is PostgrestException) {
    return SupabaseFailure(
      e.message.isNotEmpty ? e.message : 'Terjadi kesalahan server.',
      raw: e,
    );
  }
  if (e is AuthException) {
    return SupabaseFailure('Email atau kata sandi salah.', raw: e);
  }
  return SupabaseFailure('Terjadi kesalahan jaringan atau server.', raw: e);
}

extension FinancemuseSchema on SupabaseClient {
  /// All Finance Tracker tables live in the `financemuse` schema (PRD §10).
  SupabaseQueryBuilder table(String name) => schema('financemuse').from(name);
}
