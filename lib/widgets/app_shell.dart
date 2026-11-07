import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

class NavItem {
  const NavItem(this.label, this.route, this.icon, {this.section = ''});
  final String label;
  final String route;
  final IconData icon;
  final String section;
}

/// Sidebar per PRD §4.1/§4.2: collapsible 240px -> 64px rail on desktop
/// >=1200px, drawer <768px (auto-closes on navigate), collapsible tablet.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _collapsed = false;

  static const _items = [
    NavItem('Dashboard', '/dashboard', Icons.dashboard_outlined, section: 'OVERVIEW'),
    NavItem('Transaksi', '/transactions', Icons.receipt_long_outlined, section: 'OVERVIEW'),
    NavItem('Akun & Dompet', '/accounts', Icons.account_balance_wallet_outlined, section: 'OVERVIEW'),
    NavItem('Analitik', '/analytics', Icons.bar_chart_outlined, section: 'OVERVIEW'),
    NavItem('Budget', '/budgets', Icons.pie_chart_outline, section: 'PLANNING'),
    NavItem('Forecast', '/forecast', Icons.trending_up_outlined, section: 'PLANNING'),
    NavItem('Tabungan', '/savings', Icons.savings_outlined, section: 'PLANNING'),
    NavItem('Utang & Cicilan', '/debts', Icons.credit_card_outlined, section: 'PLANNING'),
    NavItem('Kategori', '/categories', Icons.category_outlined, section: 'MANAGEMENT'),
    NavItem('Template Transaksi', '/templates', Icons.bookmark_outline, section: 'MANAGEMENT'),
    NavItem('Transaksi Berulang', '/recurring', Icons.repeat_outlined, section: 'MANAGEMENT'),
    NavItem('Import & Export', '/data', Icons.import_export_outlined, section: 'MANAGEMENT'),
    NavItem('API & AI Agents', '/agents', Icons.smart_toy_outlined, section: 'SYSTEM'),
    NavItem('Pengaturan', '/settings', Icons.settings_outlined, section: 'SYSTEM'),
    NavItem('Manajemen User', '/admin/users', Icons.people_outline, section: 'ADMIN'),
    NavItem('Audit Admin', '/admin/audit', Icons.fact_check_outlined, section: 'ADMIN'),
  ];

  List<NavItem> get _visibleItems {
    final isAdmin = AppState.instance.isAdmin;
    return _items.where((i) => i.section != 'ADMIN' || isAdmin).toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;
    final location = GoRouterState.of(context).uri.toString();

    Widget navContent({bool inDrawer = false}) {
      String? lastSection;
      final tiles = <Widget>[];
      for (final item in _visibleItems) {
        if (item.section != lastSection) {
          lastSection = item.section;
          if (!_collapsed || inDrawer) {
            tiles.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                item.section,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ));
          }
        }
        final active = location == item.route ||
            (item.route != '/dashboard' && location.startsWith(item.route));
        tiles.add(
          _NavTile(
            item: item,
            collapsed: _collapsed && !inDrawer,
            active: active,
            onTap: () {
              if (inDrawer) Navigator.of(context).pop();
              if (location != item.route) context.go(item.route);
            },
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s16),
            child: Row(
              children: [
                Icon(Icons.account_balance,
                    color: Theme.of(context).colorScheme.primary),
                if (!_collapsed || inDrawer) ...[
                  const SizedBox(width: AppSpacing.s8),
                  const Expanded(
                    child: Text(
                      'FINANCE TRACKER',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: ListView(children: tiles)),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout_outlined),
            title: (!_collapsed || inDrawer)
                ? const Text('Keluar')
                : null,
            onTap: () async {
              await AppState.instance.signOut();
              if (context.mounted) context.go('/auth/login');
            },
          ),
        ],
      );
    }

    final topBar = AppBar(
      title: Text(_titleFor(location)),
      leading: isMobile
          ? Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            )
          : IconButton(
              icon: Icon(_collapsed ? Icons.menu_open : Icons.menu),
              tooltip: _collapsed ? 'Perluas sidebar' : 'Ciutkan sidebar',
              onPressed: () => setState(() => _collapsed = !_collapsed),
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Tambah transaksi',
          onPressed: () => context.go('/transactions/new'),
        ),
        IconButton(
          icon: Icon(AppState.instance.themeMode == ThemeMode.dark
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined),
          tooltip: 'Ganti tema',
          onPressed: () async {
            final next = AppState.instance.themeMode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
            await AppState.instance.setTheme(next);
          },
        ),
      ],
    );

    if (isMobile) {
      return Scaffold(
        appBar: topBar,
        drawer: Drawer(child: navContent(inDrawer: true)),
        body: widget.child,
      );
    }
    final sidebarWidth = _collapsed ? 64.0 : 240.0;
    return Scaffold(
      appBar: topBar,
      body: Row(
        children: [
          SizedBox(
            width: sidebarWidth,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: navContent(),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  String _titleFor(String location) {
    for (final item in _items) {
      if (location == item.route) return item.label;
    }
    if (location.startsWith('/transactions/new')) return 'Transaksi Baru';
    if (location.startsWith('/transactions/')) return 'Detail Transaksi';
    if (location.startsWith('/auth')) return 'Finance Tracker';
    return 'Finance Tracker';
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.collapsed,
    required this.active,
    required this.onTap,
  });
  final NavItem item;
  final bool collapsed;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: active ? accent.withValues(alpha: 0.15) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: active
              ? BoxDecoration(
                  border: Border(left: BorderSide(color: accent, width: 2)),
                )
              : null,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(item.icon,
                  size: 20,
                  color: active
                      ? accent
                      : Theme.of(context).textTheme.bodyMedium?.color),
              if (!collapsed) ...[
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.normal,
                      color: active ? accent : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
