import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase bootstrap.
///
/// Config comes from --dart-define SUPABASE_URL / SUPABASE_ANON_KEY.
/// The anon key is never stored in the repo, never printed, and never
/// committed — it is passed only at build/run time.
///
/// IMPORTANT (pending decision): the `financemuse` Postgres schema is NOT
/// yet exposed via PostgREST (PGRST_DB_SCHEMAS). Until exposure is decided,
/// every query against `.schema('financemuse')` fails at runtime. The app
/// implements the service layer properly and surfaces a clear in-app notice
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
