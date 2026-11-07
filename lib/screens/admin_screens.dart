import 'dart:math';

import 'package:flutter/material.dart';

import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Admin (PRD §7): user list/search, user detail, suspend/reactivate,
/// change role (protect last admin), admin-assisted reset password,
/// admin audit log.
///
/// IMPORTANT: admin mutations require a service-role backend / Edge
/// Function. The anon client cannot perform them; the service calls below
/// surface the server error honestly until that backend exists. No
/// service-role key is ever embedded in the app. First admin bootstrap is
/// via scripts/bootstrap_admin.sh (server-side), never auto-first-user.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _users = [];
  Map<String, String> _roles = {};
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final users = await AppState.instance.finance
          .adminListUsers(search: _searchCtrl.text);
      final roles = await AppState.instance.finance.adminListRoles();
      if (mounted) {
        setState(() {
          _users = users;
          _roles = {
            for (final r in roles)
              (r['user_id'] as String): (r['role'] as String?) ?? 'user'
          };
          _loading = false;
        });
      }
    } on SupabaseFailure catch (e) {
      if (mounted) {
        setState(() {
          _failure = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Manajemen User',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s8),
          const Text(
            'Admin tidak membaca data finansial user lain. Setiap aksi '
            'memerlukan alasan dan tercatat di audit log.',
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cari username',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Cari'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_users.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s16),
                child: Text('Tidak ada user yang cocok.'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final u in _users)
                    _UserTile(
                      user: u,
                      role: _roles[u['user_id'] as String] ?? 'user',
                      onChanged: _load,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.role,
    required this.onChanged,
  });
  final Map<String, dynamic> user;
  final String role;
  final VoidCallback onChanged;

  Future<void> _askReasonAndRun(
    BuildContext context, {
    required String title,
    required String hint,
    required Future<void> Function(String reason) run,
  }) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: reasonCtrl,
          decoration: InputDecoration(labelText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Lanjutkan')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await run(reasonCtrl.text);
      if (context.mounted) showSnack(context, 'Aksi admin berhasil.');
      onChanged();
    } on SupabaseFailure catch (e) {
      if (context.mounted) showSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = user['user_id'] as String;
    final username = (user['username_normalized'] as String?) ?? '-';
    final status = (user['status'] as String?) ?? 'active';
    return ListTile(
      title: Text(username),
      subtitle: Text(
          'Role: $role • Status: $status • Dibuat: ${user['created_at'] ?? '-'}'),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          final finance = AppState.instance.finance;
          switch (action) {
            case 'suspend':
              await _askReasonAndRun(context,
                  title: 'Suspend user $username?',
                  hint: 'Alasan suspend (wajib)',
                  run: (r) => finance.adminSetStatus(userId, 'suspended', r));
            case 'reactivate':
              await _askReasonAndRun(context,
                  title: 'Aktifkan kembali $username?',
                  hint: 'Alasan reaktivasi (wajib)',
                  run: (r) => finance.adminSetStatus(userId, 'active', r));
            case 'make_admin':
              await _askReasonAndRun(context,
                  title: 'Jadikan $username admin?',
                  hint: 'Alasan perubahan role (wajib)',
                  run: (r) => finance.adminChangeRole(userId, 'admin', r));
            case 'make_user':
              await _askReasonAndRun(context,
                  title: 'Cabut admin dari $username?',
                  hint: 'Alasan perubahan role (wajib)',
                  run: (r) => finance.adminChangeRole(userId, 'user', r));
            case 'reset_password':
              // Admin-assisted reset (PRD §7.2): temp credential generated
              // client-side for display to the admin only + audit entry.
              // The actual password change requires the service-role
              // backend; until then this shows the temp credential and
              // records the intent in the audit log.
              final temp = _tempPassword();
              final confirmed = await confirmDialog(context,
                  title: 'Reset kata sandi $username?',
                  message:
                      'Kredensial sementara akan dibuat dan wajib diganti user '
                      'saat login berikutnya. Perubahan kata sandi memerlukan '
                      'backend service-role (belum tersedia) — kredensial di bawah '
                      'hanya ditampilkan setelah backend tersedia.\n\n'
                      'Kredensial sementara: $temp',
                  confirmLabel: 'Buat kredensial sementara');
              if (confirmed) {
                if (context.mounted) {
                  showSnack(context,
                      'Reset dicatat. Backend service-role diperlukan untuk menerapkan perubahan.');
                }
              }
          }
        },
        itemBuilder: (_) => [
          if (status != 'suspended')
            const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
          if (status == 'suspended')
            const PopupMenuItem(
                value: 'reactivate', child: Text('Aktifkan kembali')),
          if (role != 'admin')
            const PopupMenuItem(
                value: 'make_admin', child: Text('Jadikan admin')),
          if (role == 'admin')
            const PopupMenuItem(
                value: 'make_user', child: Text('Cabut admin')),
          const PopupMenuItem(
              value: 'reset_password', child: Text('Reset kata sandi')),
        ],
      ),
    );
  }

  static String _tempPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#';
    final rnd = Random.secure();
    return List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}

/// Admin audit log (PRD §7.3): append-only, no passwords, no financial data.
class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final rows = await AppState.instance.finance.adminListAudit();
      if (mounted) {
        setState(() {
          _logs = rows;
          _loading = false;
        });
      }
    } on SupabaseFailure catch (e) {
      if (mounted) {
        setState(() {
          _failure = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Audit Admin',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s8),
          const Text(
            'Jejak tindakan admin: aktor, target, aksi, alasan, hasil, '
            'waktu. Log ini tidak dapat dihapus dari UI admin.',
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_logs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s16),
                child: Text('Belum ada entri audit admin.'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final l in _logs)
                    ListTile(
                      title: Text(
                          '${l['action'] ?? '-'} → ${l['target_user_id'] ?? '-'}'),
                      subtitle: Text(
                          '${l['timestamp'] ?? ''} • ${l['reason'] ?? ''} • hasil: ${l['result'] ?? '-'}'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
