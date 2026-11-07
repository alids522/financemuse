import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'router.dart';
import 'services/supabase_client.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Finance Tracker — Flutter app (PRD v1.0, P0).
/// Supabase URL + anon key via --dart-define SUPABASE_URL / SUPABASE_ANON_KEY.
/// If the anon key is empty, the app still starts and shows a configuration
/// notice instead of crashing.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  await SupabaseConfig.init();
  final state = AppState();
  await state.init();
  runApp(FinanceTrackerApp(state: state));
}

class FinanceTrackerApp extends StatelessWidget {
  const FinanceTrackerApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => MaterialApp.router(
        title: 'Finance Tracker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: state.themeMode,
        routerConfig: buildRouter(state),
        locale: const Locale('id', 'ID'),
      ),
    );
  }
}
