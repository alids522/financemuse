import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/money_period.dart';
import '../widgets/common.dart';

/// Transaction list (PRD §5.3, §5.5): filters Day/Week/Month/Year/Custom,
/// search, sort, pagination. Detail/edit + duplicate/reverse/soft-delete
/// live on the detail route.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, this.transactionId});
  final String? transactionId;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _rows = [];
  String? _typeFilter;
  String _search = '';
  int _offset = 0;
  static const int _pageSize = 50;
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

  Future<void> _load({bool reset = true}) async {
    if (reset) _offset = 0;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final rows = await AppState.instance.finance.listTransactions(
        period: AppState.instance.period,
        type: _typeFilter,
        search: _search.isEmpty ? null : _search,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
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
    final state = AppState.instance;
    if (widget.transactionId != null) {
      return TransactionDetailScreen(id: widget.transactionId!);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: PeriodSwitcher(
                  currentKind: state.periodKind,
                  period: state.period,
                  onChanged: (kind, range) {
                    state.setPeriod(range, kind);
                    _load();
                  },
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
                onPressed: () => context.go('/transactions/new'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cari deskripsi / merchant',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (v) {
                    _search = v;
                    _load();
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              DropdownButton<String?>(
                value: _typeFilter,
                hint: const Text('Semua tipe'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Semua tipe')),
                  DropdownMenuItem(value: 'expense', child: Text('Pengeluaran')),
                  DropdownMenuItem(value: 'income', child: Text('Pemasukan')),
                  DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                  DropdownMenuItem(value: 'adjustment', child: Text('Penyesuaian')),
                ],
                onChanged: (v) {
                  _typeFilter = v;
                  _load();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_rows.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s16),
                child: Text(
                  'Belum ada transaksi pada periode ini. '
                  'Tekan Tambah untuk mencatat transaksi pertama.',
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final t in _rows)
                    ListTile(
                      title: Text((t['description'] as String?) ??
                          (t['merchant'] as String?) ??
                          (t['type'] as String)),
                      subtitle: Text(
                        '${(t['effective_at'] as String?)?.substring(0, 10) ?? ''} • '
                        '${t['type']} • ${t['status']}',
                      ),
                      trailing: MoneyText(
                        (t['type'] == 'expense' ? -1 : 1) *
                            ((t['amount'] as num?)?.toInt() ?? 0),
                        signed: true,
                      ),
                      onTap: () => context.go('/transactions/${t['id']}'),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _offset == 0
                            ? null
                            : () {
                                _offset -= _pageSize;
                                _load(reset: false);
                              },
                        child: const Text('Sebelumnya'),
                      ),
                      TextButton(
                        onPressed: _rows.length < _pageSize
                            ? null
                            : () {
                                _offset += _pageSize;
                                _load(reset: false);
                              },
                        child: const Text('Berikutnya'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Transaction detail: edit, duplicate, reverse, soft delete (PRD §5.3).
class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  Map<String, dynamic>? _tx;
  bool _loading = true;
  SupabaseFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AppState.instance.finance.listTransactions(limit: 1000);
      final found = rows.where((r) => r['id'] == widget.id).toList();
      if (mounted) {
        setState(() {
          _tx = found.isEmpty ? null : found.first;
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failure != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: SchemaNotice(failure: _failure),
      );
    }
    final tx = _tx;
    if (tx == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.s16),
        child: Text('Transaksi tidak ditemukan.'),
      );
    }
    final amount = (tx['amount'] as num?)?.toInt() ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (tx['description'] as String?) ??
                (tx['merchant'] as String?) ??
                'Transaksi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.s8),
          MoneyText(amount,
              signed: true, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.s16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Tipe', '${tx['type']}'),
                  _row('Status', '${tx['status']}'),
                  _row('Tanggal efektif', '${tx['effective_at']}'),
                  _row('Merchant', '${tx['merchant'] ?? '-'}'),
                  _row('ID', '${tx['id']}'),
                  _row('Idempotency key', '${tx['idempotency_key'] ?? '-'}'),
                  _row('Versi baris', '${tx['row_version'] ?? '-'}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          Wrap(
            spacing: AppSpacing.s8,
            children: [
              ElevatedButton(
                onPressed: () => context.go('/transactions/new',
                    extra: tx),
                child: const Text('Edit'),
              ),
              OutlinedButton(
                onPressed: () async {
                  try {
                    await AppState.instance.finance
                        .duplicateTransaction(tx);
                    if (context.mounted) {
                      showSnack(context, 'Transaksi diduplikasi sebagai draft.');
                      context.go('/transactions');
                    }
                  } on SupabaseFailure catch (e) {
                    if (context.mounted) {
                      showSnack(context, e.message, isError: true);
                    }
                  }
                },
                child: const Text('Duplikat'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: 'Balikkan transaksi?',
                      message:
                          'Transaksi reversal akan dibuat dan transaksi ini menjadi voided. Ledger tetap terjaga.');
                  if (!ok) return;
                  try {
                    await AppState.instance.finance
                        .reverseTransaction(tx, 'dibalik dari UI');
                    if (context.mounted) {
                      showSnack(context, 'Transaksi dibalik.');
                      context.go('/transactions');
                    }
                  } on SupabaseFailure catch (e) {
                    if (context.mounted) {
                      showSnack(context, e.message, isError: true);
                    }
                  }
                },
                child: const Text('Balikkan'),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: context.finance.negative),
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: 'Hapus transaksi?',
                      message:
                          'Penghapusan bersifat soft delete (deleted_at). Riwayat ledger tetap ada.',
                      confirmLabel: 'Ya, hapus');
                  if (!ok) return;
                  try {
                    await AppState.instance.finance
                        .softDeleteTransaction(widget.id);
                    if (context.mounted) {
                      showSnack(context, 'Transaksi dihapus (soft delete).');
                      context.go('/transactions');
                    }
                  } on SupabaseFailure catch (e) {
                    if (context.mounted) {
                      showSnack(context, e.message, isError: true);
                    }
                  }
                },
                child: const Text('Hapus'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 140,
                child: Text(label,
                    style: Theme.of(context).textTheme.bodySmall)),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

/// Transaction form (PRD §5.3, §8.4): segmented Income/Expense/Transfer,
/// amount prominent, account, category (transfer swaps to destination
/// account), date, merchant, notes, tags, splits, save & save-and-add.
/// Idempotency key generated per create and reused on retry.
class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({super.key, this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  String _type = 'expense';
  String? _accountId;
  String? _destAccountId;
  String? _categoryId;
  DateTime _effectiveAt = JakartaTime.now();
  String _status = 'posted';
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  bool _busy = false;
  SupabaseFailure? _failure;
  String? _idempotencyKey;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _type = (ex['type'] as String?) ?? 'expense';
      _amountCtrl.text = '${(ex['amount'] as num?)?.toInt() ?? 0}';
      _merchantCtrl.text = (ex['merchant'] as String?) ?? '';
      _descCtrl.text = (ex['description'] as String?) ?? '';
      _accountId = ex['account_id'] as String?;
      _destAccountId = ex['destination_account_id'] as String?;
      _categoryId = ex['category_id'] as String?;
      _status = (ex['status'] as String?) ?? 'posted';
      final eff = ex['effective_at'] as String?;
      if (eff != null) {
        _effectiveAt = JakartaTime.toJakarta(DateTime.parse(eff));
      }
      _idempotencyKey = ex['idempotency_key'] as String?;
    }
    _loadLookups();
  }

  Future<void> _loadLookups() async {
    try {
      final accounts = await AppState.instance.finance.listAccounts();
      final categories = await AppState.instance.finance.listCategories();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _categories = categories;
        _loading = false;
      });
    } on SupabaseFailure catch (e) {
      if (mounted) {
        setState(() {
          _failure = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save({bool addAnother = false}) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = Money.parse(_amountCtrl.text);
    if (amount == null) {
      showSnack(context, 'Nominal harus lebih dari 0.', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final effectiveUtc = JakartaTime.toUtc(_effectiveAt);
      if (widget.existing != null) {
        await AppState.instance.finance.updateTransaction(
          widget.existing!['id'] as String,
          {
            'type': _type,
            'amount': amount,
            'account_id': _accountId,
            'destination_account_id': _destAccountId,
            'category_id': _type == 'transfer' ? null : _categoryId,
            'effective_at': effectiveUtc.toIso8601String(),
            'merchant': _merchantCtrl.text,
            'description': _descCtrl.text,
            'status': _status,
          },
          expectedVersion:
              widget.existing!['row_version'] as int?,
        );
      } else {
        _idempotencyKey ??= newIdempotencyKey();
        await AppState.instance.finance.createTransaction(
          type: _type,
          amountMinor: amount,
          currency: 'IDR',
          accountId: _accountId!,
          destinationAccountId: _destAccountId,
          categoryId: _type == 'transfer' ? null : _categoryId,
          effectiveAtUtc: effectiveUtc,
          merchant: _merchantCtrl.text,
          description: _descCtrl.text,
          tags: _tagsCtrl.text
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList(),
          status: _status,
          idempotencyKey: _idempotencyKey,
        );
      }
      if (!mounted) return;
      showSnack(context, 'Transaksi disimpan.');
      if (addAnother) {
        _amountCtrl.clear();
        _descCtrl.clear();
        _merchantCtrl.clear();
        _idempotencyKey = null;
        setState(() => _busy = false);
      } else {
        context.go('/transactions');
      }
    } on SupabaseFailure catch (e) {
      if (mounted) showSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTransfer = _type == 'transfer';
    final cats = _categories
        .where((c) => c['type'] == (_type == 'income' ? 'income' : 'expense'))
        .toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing != null
                    ? 'Edit Transaksi'
                    : 'Transaksi Baru',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.s16),
              if (_failure != null) SchemaNotice(failure: _failure),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Pengeluaran')),
                    ButtonSegment(value: 'income', label: Text('Pemasukan')),
                    ButtonSegment(value: 'transfer', label: Text('Transfer')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) =>
                      setState(() => _type = s.first),
                ),
                const SizedBox(height: AppSpacing.s16),
                TextFormField(
                  controller: _amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nominal (IDR)',
                    prefixText: 'Rp ',
                    helperText: 'Nominal harus lebih dari 0.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      Money.parse(v ?? '') == null
                          ? 'Masukkan nominal yang valid.'
                          : null,
                ),
                const SizedBox(height: AppSpacing.s16),
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: InputDecoration(
                      labelText: isTransfer ? 'Akun Asal' : 'Akun'),
                  items: _accounts
                      .map((a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text((a['name'] as String?) ?? ''),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _accountId = v),
                  validator: (v) =>
                      v == null ? 'Pilih akun.' : null,
                ),
                const SizedBox(height: AppSpacing.s16),
                if (isTransfer)
                  DropdownButtonFormField<String>(
                    initialValue: _destAccountId,
                    decoration: const InputDecoration(
                        labelText: 'Akun Tujuan'),
                    items: _accounts
                        .where((a) => a['id'] != _accountId)
                        .map((a) => DropdownMenuItem(
                              value: a['id'] as String,
                              child: Text((a['name'] as String?) ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _destAccountId = v),
                    validator: (v) => v == null
                        ? 'Pilih akun tujuan yang berbeda.'
                        : null,
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration:
                        const InputDecoration(labelText: 'Kategori'),
                    items: cats
                        .map((c) => DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text((c['name'] as String?) ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _categoryId = v),
                    validator: (v) =>
                        v == null ? 'Pilih kategori.' : null,
                  ),
                const SizedBox(height: AppSpacing.s16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal & waktu efektif'),
                  subtitle: Text(
                      '${_effectiveAt.day}/${_effectiveAt.month}/${_effectiveAt.year} '
                      '${_effectiveAt.hour.toString().padLeft(2, '0')}:${_effectiveAt.minute.toString().padLeft(2, '0')} WIB'),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _effectiveAt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (date != null) {
                      setState(() => _effectiveAt = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          _effectiveAt.hour,
                          _effectiveAt.minute));
                    }
                  },
                ),
                TextFormField(
                  controller: _merchantCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Merchant / Penerima (opsional)'),
                ),
                const SizedBox(height: AppSpacing.s16),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Deskripsi (opsional)'),
                ),
                const SizedBox(height: AppSpacing.s16),
                TextFormField(
                  controller: _tagsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tag (opsional, pisahkan dengan koma)',
                  ),
                ),
                const SizedBox(height: AppSpacing.s16),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'posted', child: Text('Posted')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'posted'),
                ),
                const SizedBox(height: AppSpacing.s24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _busy ? null : () => _save(),
                        child: const Text('Simpan'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => _save(addAnother: true),
                        child: const Text('Simpan & Tambah Lagi'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    TextButton(
                      onPressed: () => context.go('/transactions'),
                      child: const Text('Batal'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
