import 'package:flutter/material.dart';

import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/money_period.dart';
import '../widgets/common.dart';

/// Accounts & wallets (PRD §5.2): Cash/Bank/E-wallet/Other, opening
/// balance, archive; delete blocked when transactions exist.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _accounts = [];

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
      final rows = await AppState.instance.finance.listAccounts();
      if (mounted) {
        setState(() {
          _accounts = rows;
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

  Future<void> _showForm({Map<String, dynamic>? existing}) async {
    final nameCtrl =
        TextEditingController(text: (existing?['name'] as String?) ?? '');
    final balanceCtrl = TextEditingController(
        text: '${(existing?['opening_balance_minor'] as num?)?.toInt() ?? 0}');
    String type = (existing?['type'] as String?) ?? 'Cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Akun Baru' : 'Edit Akun'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama akun'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipe'),
              items: const ['Cash', 'Bank', 'E-wallet', 'Other']
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => type = v ?? 'Cash',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: balanceCtrl,
              decoration: const InputDecoration(
                  labelText: 'Saldo awal (IDR)'),
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
              try {
                if (existing == null) {
                  await AppState.instance.finance.createAccount(
                    name: nameCtrl.text,
                    type: type,
                    currency: 'IDR',
                    openingBalanceMinor:
                        Money.parse(balanceCtrl.text) ?? 0,
                  );
                } else {
                  await AppState.instance.finance.updateAccount(
                    existing['id'] as String,
                    {'name': nameCtrl.text, 'type': type},
                  );
                }
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Akun & Dompet',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Tambah Akun'),
                onPressed: () => _showForm(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_accounts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s16),
                child: Text(
                    'Belum ada akun. Tambahkan Cash, Bank, atau E-wallet.'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final a in _accounts)
                    ListTile(
                      leading: Icon(
                        switch ((a['type'] as String?) ?? 'Other') {
                          'Cash' => Icons.money_outlined,
                          'Bank' => Icons.account_balance_outlined,
                          'E-wallet' => Icons.account_balance_wallet_outlined,
                          _ => Icons.wallet_outlined,
                        },
                      ),
                      title: Text((a['name'] as String?) ?? ''),
                      subtitle: Text(
                          '${a['type']} • ${a['status'] ?? 'active'}'),
                      trailing: MoneyText(
                          (a['opening_balance_minor'] as num?)?.toInt() ?? 0),
                      onTap: () => _showForm(existing: a),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.s8),
          const Text(
            'Saldo ditampilkan dari saldo awal. Saldo otoritatif berasal '
            'dari journal ledger (PRD §9.3). Hapus akun diblokir bila masih '
            'ada transaksi — arsipkan sebagai gantinya.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Categories + templates (PRD §5.4).
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _categories = [];

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
      final rows = await AppState.instance.finance.listCategories();
      if (mounted) {
        setState(() {
          _categories = rows;
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

  Future<void> _addCategory() async {
    final nameCtrl = TextEditingController();
    String type = 'expense';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kategori Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama kategori'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipe'),
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('Pengeluaran')),
                DropdownMenuItem(value: 'income', child: Text('Pemasukan')),
              ],
              onChanged: (v) => type = v ?? 'expense',
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
                await AppState.instance.finance.createCategory(
                    name: nameCtrl.text, type: type);
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
    final income =
        _categories.where((c) => c['type'] == 'income').toList();
    final expense =
        _categories.where((c) => c['type'] == 'expense').toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Kategori',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Kategori Baru'),
                onPressed: _addCategory,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            _categoryGroup('Pemasukan', income),
            const SizedBox(height: AppSpacing.s16),
            _categoryGroup('Pengeluaran', expense),
            const SizedBox(height: AppSpacing.s8),
            const Text(
              'Kategori sistem (user_id null) berasal dari preset PRD §5.4. '
              'Kategori yang sudah dipakai tidak dihapus langsung.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryGroup(String title, List<Map<String, dynamic>> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.s8),
            if (items.isEmpty) const Text('Belum ada kategori.'),
            for (final c in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text((c['name'] as String?) ?? ''),
                subtitle: Text(c['user_id'] == null
                    ? 'Kategori sistem'
                    : 'Kategori custom'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Transaction templates (PRD §5.4): quick-add presets with editable
/// preview before submit.
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key});

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _templates = [];

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
      final rows = await AppState.instance.finance.listTemplates();
      if (mounted) {
        setState(() {
          _templates = rows;
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
          Text('Template Transaksi',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s8),
          const Text(
            'Template adalah preset yang bisa dipakai ulang. Penggunaan '
            'template selalu membuka preview yang dapat diedit sebelum '
            'submit (PRD §5.4). Buat template dari form transaksi dengan '
            'menyimpan preset — untuk P0, template dibuat lewat form di bawah.',
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_templates.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s16),
                child: Text('Belum ada template.'),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final t in _templates)
                    ListTile(
                      title: Text((t['name'] as String?) ?? ''),
                      subtitle: Text(
                          (t['favourite'] == true) ? 'Favorit' : 'Template'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirmDialog(context,
                              title: 'Hapus template?',
                              message:
                                  'Template "${t['name']}" akan dihapus.');
                          if (!ok) return;
                          await AppState.instance.finance
                              .deleteTemplate(t['id'] as String);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
