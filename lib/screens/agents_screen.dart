import 'package:flutter/material.dart';

import '../services/mcp_policy.dart';
import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/money_period.dart';
import '../widgets/common.dart';

/// API & AI Agents (PRD §6): connections, permission matrix, approval
/// limits, pending approvals inbox (trusted UI only), agent audit log.
/// No live MCP server in this pass — the policy engine
/// (lib/services/mcp_policy.dart) is a skeleton + the matrix below.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _connections = [];
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _audit = [];

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
      final conns = await AppState.instance.finance.listAgentConnections();
      final pending = await AppState.instance.finance.listPendingActions();
      final audit = await AppState.instance.finance.listAgentAudit();
      if (mounted) {
        setState(() {
          _connections = conns;
          _pending = pending;
          _audit = audit;
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

  Future<void> _decide(String id, bool approve) async {
    try {
      await AppState.instance.finance.decidePendingAction(id, approve);
      if (!mounted) return;
      showSnack(context,
          approve ? 'Aksi disetujui.' : 'Aksi ditolak.');
      _load();
    } on SupabaseFailure catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('API & AI Agents',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s8),
          const Text(
            'MCP Read & Write dengan approval untuk tindakan berisiko. '
            'Approval hanya lewat UI tepercaya ini — agent tidak dapat '
            'menyetujui tindakannya sendiri. Server MCP live belum ada di '
            'pass ini (skeleton kebijakan + REST outline di docs/openapi.yaml).',
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Persetujuan Tertunda (inbox)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    if (_pending.isEmpty)
                      const Text(
                          'Tidak ada aksi tertunda. Aksi berisiko agent '
                          'muncul di sini dengan masa berlaku 10 menit.'),
                    for (final p in _pending)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${p['tool'] ?? 'aksi agent'} • ${p['status']}'),
                        subtitle: Text(
                            'Berlaku hingga: ${p['expires_at'] ?? '-'}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  _decide(p['id'] as String, false),
                              child: const Text('Tolak'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  _decide(p['id'] as String, true),
                              child: const Text('Setujui'),
                            ),
                          ],
                        ),
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
                    const Text('Koneksi Agent',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    if (_connections.isEmpty)
                      const Text('Belum ada koneksi agent.'),
                    for (final c in _connections)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            (c['display_name'] as String?) ?? 'Agent'),
                        subtitle: Text(
                            'Status: ${c['status'] ?? '-'} • Terhubung: ${c['connected_at'] ?? '-'}'),
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
                    const Text('Matriks Izin & Batas Approval (PRD §6.2–6.3)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    _policyRow('Buat income/expense ≤ ${Money.formatIdr(McpPolicy.autoCreateLimitMinor)}',
                        'Auto-allow'),
                    _policyRow('Buat income/expense > ${Money.formatIdr(McpPolicy.autoCreateLimitMinor)}',
                        'Perlu approval'),
                    _policyRow('Edit selisih ≤ ${Money.formatIdr(McpPolicy.autoEditDeltaLimitMinor)}',
                        'Auto-allow'),
                    _policyRow('Edit selisih > ${Money.formatIdr(McpPolicy.autoEditDeltaLimitMinor)}',
                        'Perlu approval'),
                    _policyRow('Transfer internal', 'Selalu approval'),
                    _policyRow('Hapus / bulk / adjustment saldo',
                        'Selalu approval'),
                    _policyRow('admin:* dan agent_permissions:write',
                        'Tidak pernah via MCP'),
                    _policyRow('Masa berlaku approval',
                        '10 menit'),
                    const SizedBox(height: AppSpacing.s8),
                    const Text(
                      'Contoh evaluasi kebijakan (skeleton):',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'create Rp500.000 → ${McpPolicy.evaluateAction(scope: McpScope.transactionsCreate, permissionEnabled: true, amountMinor: 500000).label}',
                    ),
                    Text(
                      'create Rp2.000.000 → ${McpPolicy.evaluateAction(scope: McpScope.transactionsCreate, permissionEnabled: true, amountMinor: 2000000).label}',
                    ),
                    Text(
                      'admin:* → ${McpPolicy.evaluateAction(scope: McpScope.admin, permissionEnabled: true).label}',
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
                    const Text('Log Audit Agent',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    if (_audit.isEmpty)
                      const Text('Belum ada entri audit agent.'),
                    for (final a in _audit.take(20))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${a['tool'] ?? a['event_type'] ?? 'event'} • ${a['outcome'] ?? ''}'),
                        subtitle: Text('${a['occurred_at'] ?? ''}'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _policyRow(String action, String policy) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(action)),
            Text(policy, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
