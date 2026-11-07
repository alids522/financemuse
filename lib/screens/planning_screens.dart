import 'package:flutter/material.dart';

import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/money_period.dart';
import '../widgets/common.dart';

/// Savings goals (PRD §5.10) — basic CRUD P0. Automation/projection
/// is P1 and marked TODO.
class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});

  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _goals = [];

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
      final rows = await AppState.instance.finance.listSavingsGoals();
      if (mounted) {
        setState(() {
          _goals = rows;
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

  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tujuan Tabungan Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama tujuan')),
            const SizedBox(height: 12),
            TextField(
              controller: targetCtrl,
              decoration: const InputDecoration(
                  labelText: 'Target (IDR)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final target = Money.parse(targetCtrl.text);
              if (target == null) {
                showSnack(ctx, 'Target tidak valid.', isError: true);
                return;
              }
              try {
                await AppState.instance.finance.createSavingsGoal(
                    name: nameCtrl.text, targetMinor: target);
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } on SupabaseFailure catch (e) {
                if (ctx.mounted) {
                  if (ctx.mounted) showSnack(ctx, e.message, isError: true);
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return _SimpleCrudScaffold(
      title: 'Tujuan Tabungan',
      onAdd: _add,
      addLabel: 'Tujuan Baru',
      loading: _loading,
      failure: _failure,
      emptyText: 'Belum ada tujuan tabungan.',
      note: 'TODO (P1): alokasi kontribusi, milestone, dan proyeksi target.',
      items: _goals
          .map((g) => ListTile(
                title: Text((g['name'] as String?) ?? ''),
                subtitle: Text(
                    'Target: ${Money.formatIdr((g['target_amount_minor'] as num?)?.toInt() ?? 0)}'),
              ))
          .toList(),
    );
  }
}

/// Debts & installments (PRD §5.11) — basic CRUD P0. Payment schedules
/// and interest split are P1 and marked TODO.
class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _debts = [];

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
      final rows = await AppState.instance.finance.listDebts();
      if (mounted) {
        setState(() {
          _debts = rows;
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

  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    final principalCtrl = TextEditingController();
    String kind = 'debt';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Utang / Piutang Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Nama (kreditur/debitur)')),
            const SizedBox(height: 12),
            TextField(
              controller: principalCtrl,
              decoration:
                  const InputDecoration(labelText: 'Pokok (IDR)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Jenis'),
              items: const [
                DropdownMenuItem(value: 'debt', child: Text('Utang')),
                DropdownMenuItem(
                    value: 'receivable', child: Text('Piutang')),
              ],
              onChanged: (v) => kind = v ?? 'debt',
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final principal = Money.parse(principalCtrl.text);
              if (principal == null) {
                showSnack(ctx, 'Pokok tidak valid.', isError: true);
                return;
              }
              try {
                await AppState.instance.finance.createDebt(
                    counterparty: nameCtrl.text,
                    principalMinor: principal,
                    kind: kind);
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } on SupabaseFailure catch (e) {
                if (ctx.mounted) {
                  if (ctx.mounted) showSnack(ctx, e.message, isError: true);
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return _SimpleCrudScaffold(
      title: 'Utang & Cicilan',
      onAdd: _add,
      addLabel: 'Utang Baru',
      loading: _loading,
      failure: _failure,
      emptyText: 'Belum ada utang/piutang.',
      note: 'TODO (P1): jadwal cicilan, pembayaran parsial, dan pemisah bunga/pokok.',
      items: _debts
          .map((d) => ListTile(
                title: Text((d['counterparty'] as String?) ?? ''),
                subtitle: Text(
                    '${d['kind'] ?? 'debt'} • Pokok: ${Money.formatIdr((d['principal_minor'] as num?)?.toInt() ?? 0)}'),
              ))
          .toList(),
    );
  }
}

/// Recurring transactions (PRD §5.9) — basic CRUD P0. Automation
/// (auto-post job) is P1 and marked TODO.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _rules = [];

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
      final rows = await AppState.instance.finance.listRecurringRules();
      if (mounted) {
        setState(() {
          _rules = rows;
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

  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    String cadence = 'monthly';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aturan Berulang Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Nama aturan')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: cadence,
              decoration: const InputDecoration(labelText: 'Frekuensi'),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('Harian')),
                DropdownMenuItem(value: 'weekly', child: Text('Mingguan')),
                DropdownMenuItem(value: 'monthly', child: Text('Bulanan')),
                DropdownMenuItem(value: 'yearly', child: Text('Tahunan')),
              ],
              onChanged: (v) => cadence = v ?? 'monthly',
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              try {
                await AppState.instance.finance.createRecurringRule(
                  name: nameCtrl.text,
                  cadence: cadence,
                  payload: {'note': 'dibuat dari UI P0'},
                );
                if (ctx.mounted) Navigator.of(ctx).pop(true);
              } on SupabaseFailure catch (e) {
                if (ctx.mounted) {
                  if (ctx.mounted) showSnack(ctx, e.message, isError: true);
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return _SimpleCrudScaffold(
      title: 'Transaksi Berulang',
      onAdd: _add,
      addLabel: 'Aturan Baru',
      loading: _loading,
      failure: _failure,
      emptyText: 'Belum ada aturan berulang.',
      note: 'TODO (P1): eksekusi otomatis (mode scheduled/draft/auto-post) dan job idempotent di backend.',
      items: _rules
          .map((r) => ListTile(
                title: Text(((r['payload_json'] as Map<String, dynamic>?)?['name'] as String?) ?? 'Aturan'),
                subtitle: Text(
                    '${r['cadence']} • mode: ${r['mode'] ?? 'draft'} • aktif: ${r['active'] == true ? 'ya' : 'tidak'}'),
              ))
          .toList(),
    );
  }
}

class _SimpleCrudScaffold extends StatelessWidget {
  const _SimpleCrudScaffold({
    required this.title,
    required this.onAdd,
    required this.addLabel,
    required this.loading,
    required this.failure,
    required this.emptyText,
    required this.note,
    required this.items,
  });
  final String title;
  final VoidCallback onAdd;
  final String addLabel;
  final bool loading;
  final SupabaseFailure? failure;
  final String emptyText;
  final String note;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: Text(addLabel),
                onPressed: onAdd,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (failure != null) SchemaNotice(failure: failure),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (items.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Text(emptyText),
              ),
            )
          else
            Card(child: Column(children: items)),
          const SizedBox(height: AppSpacing.s8),
          Text(note, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
