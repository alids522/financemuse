import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/finance_service.dart';
import '../services/supabase_client.dart';
import '../utils/money_period.dart';

/// App-wide state: session, role, theme, selected period.
class AppState extends ChangeNotifier {
  AppState();

  static late AppState instance;

  late final AuthService auth;
  late final FinanceService finance;
  ThemeMode themeMode = ThemeMode.system;
  String role = 'user';
  PeriodRange period = Periods.month(
    JakartaTime.now().year,
    JakartaTime.now().month,
  );
  String periodKind = 'month'; // day | week | month | year | custom
  SupabaseFailure? lastFailure;

  bool get isAdmin => role == 'admin';

  Future<void> init() async {
    instance = this;
    final client = Supabase.instance.client;
    auth = AuthService(client);
    finance = FinanceService(client);
    final prefs = await SharedPreferences.getInstance();
    final theme = prefs.getString('theme') ?? 'system';
    themeMode = switch (theme) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    if (auth.isSignedIn) {
      role = await auth.currentRole();
    }
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    });
    notifyListeners();
  }

  void setPeriod(PeriodRange range, String kind) {
    period = range;
    periodKind = kind;
    notifyListeners();
  }

  Future<void> refreshRole() async {
    role = await auth.currentRole();
    notifyListeners();
  }

  Future<void> signOut() async {
    await auth.signOut();
    role = 'user';
    notifyListeners();
  }
}
