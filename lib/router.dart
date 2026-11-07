import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/accounts_categories.dart';
import 'screens/admin_screens.dart';
import 'screens/agents_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/budgets_forecast_analytics.dart';
import 'screens/dashboard_screen.dart';
import 'screens/data_screen.dart';
import 'screens/planning_screens.dart';
import 'screens/settings_screen.dart';
import 'screens/transactions_screen.dart';
import 'state/app_state.dart';
import 'widgets/app_shell.dart';

/// go_router routes per PRD §4.3. No bottom tabs.
/// Admin routes are hidden in the UI for non-admins; authorization is
/// enforced server-side (PRD §7).
GoRouter buildRouter(AppState state) {
  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, goState) {
      final signedIn = state.auth.isSignedIn;
      final onAuth = goState.uri.toString().startsWith('/auth');
      if (!signedIn && !onAuth) return '/auth/login';
      if (signedIn && onAuth) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/sign-up',
        builder: (_, _) => const AuthScreen(isSignUp: true),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (_, _) => const AuthScreen(isSignUp: false),
      ),
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, _) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (_, _) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/transactions/new',
            builder: (_, st) => TransactionFormScreen(
              existing: st.extra as Map<String, dynamic>?,
            ),
          ),
          GoRoute(
            path: '/transactions/:id',
            builder: (_, st) => TransactionsScreen(
              transactionId: st.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: '/accounts',
            builder: (_, _) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/categories',
            builder: (_, _) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/templates',
            builder: (_, _) => const TemplatesScreen(),
          ),
          GoRoute(
            path: '/budgets',
            builder: (_, _) => const BudgetsScreen(),
          ),
          GoRoute(
            path: '/forecast',
            builder: (_, _) => const ForecastScreen(),
          ),
          GoRoute(
            path: '/analytics',
            builder: (_, _) => const AnalyticsScreen(),
          ),
          GoRoute(
            path: '/savings',
            builder: (_, _) => const SavingsScreen(),
          ),
          GoRoute(
            path: '/debts',
            builder: (_, _) => const DebtsScreen(),
          ),
          GoRoute(
            path: '/recurring',
            builder: (_, _) => const RecurringScreen(),
          ),
          GoRoute(
            path: '/data',
            builder: (_, _) => const DataScreen(),
          ),
          GoRoute(
            path: '/agents',
            builder: (_, _) => const AgentsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/admin/users',
            builder: (_, _) => const AdminUsersScreen(),
          ),
          GoRoute(
            path: '/admin/audit',
            builder: (_, _) => const AdminAuditScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (_, st) => Scaffold(
      body: Center(
        child: Text('Halaman tidak ditemukan: ${st.uri}'),
      ),
    ),
  );
}
