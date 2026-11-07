import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/forecast.dart';
import '../utils/money_period.dart';
import '../widgets/common.dart';

/// Budgets vs Actual (PRD §5.7): remaining = budget - actual,
/// projected variance = budget - forecast EOP. Overspend >100% shown
/// negative/red.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  List<Map<String, dynamic>> _budgets = [];
  final Map<String, int> _actual = {};
  final Map<String, ForecastResult> _forecast = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppState.instance;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final budgets = await state.finance.listBudgets();
      final now = JakartaTime.now();
      final elapsed = now.day;
      final totalDays = DateTime(now.year, now.month + 1, 0).day;
      for (final b in budgets) {
        final catId = b['category_id'] as String?;
        final actual =
            catId == null ? 0 : await state.finance.categoryActual(catId, state.period);
        _actual[b['id'] as String] = actual;
        _forecast[b['id'] as String] = Forecast.runRate(
          actualToDateMinor: actual,
          elapsedDays: elapsed,
          totalDays: totalDays,
        );
      }
      if (mounted) {
        setState(() {
          _budgets = budgets;
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

  Future<void> _addBudget() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    List<Map<String, dynamic>> cats = [];
    try {
      cats = await AppState.instance.finance.listCategories();
    } catch (_) {}
    if (!mounted) return;
    String? categoryId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Budget Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama budget'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nominal budget (IDR)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: categoryId,
              decoration: const InputDecoration(
                  labelText: 'Kategori (opsional)'),
              items: cats
                  .where((c) => c['type'] == 'expense')
                  .map((c) => DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text((c['name'] as String?) ?? ''),
                      ))
                  .toList(),
              onChanged: (v) => categoryId = v,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final amount = Money.parse(amountCtrl.text);
              if (amount == null) {
                showSnack(ctx, 'Nominal budget tidak valid.',
                    isError: true);
                return;
              }
              try {
                await AppState.instance.finance.createBudget(
                  name: nameCtrl.text,
                  categoryId: categoryId,
                  amountMinor: amount,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Budget vs Actual',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Budget Baru'),
                onPressed: _addBudget,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Periode: ${AppState.instance.period.label}. '
            'Sisa = budget − actual. Varians proyeksi = budget − forecast akhir periode.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_budgets.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.s16),
                child: Text('Belum ada budget. Buat budget pertama Anda.'),
              ),
            )
          else
            for (final b in _budgets)
              _BudgetCard(
                name: (b['name'] as String?) ?? 'Budget',
                budget: (b['amount_minor'] as num?)?.toInt() ?? 0,
                actual: _actual[b['id'] as String] ?? 0,
                forecast: _forecast[b['id'] as String],
              ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.name,
    required this.budget,
    required this.actual,
    this.forecast,
  });
  final String name;
  final int budget;
  final int actual;
  final ForecastResult? forecast;

  @override
  Widget build(BuildContext context) {
    final remaining = BudgetMath.remaining(budget, actual);
    final util = BudgetMath.utilisation(budget, actual);
    final variance = forecast == null
        ? null
        : BudgetMath.projectedVariance(budget, forecast!.forecastEopMinor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${(util * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: util > 1 ? context.finance.negative : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            LinearProgressIndicator(
              value: util.isFinite ? util.clamp(0, 1) : 1,
              color: util > 1
                  ? context.finance.negative
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Budget: ${Money.formatIdr(budget)}'),
                Text('Actual: ${Money.formatIdr(actual)}'),
                Row(
                  children: [
                    const Text('Sisa: '),
                    MoneyText(remaining, signed: true),
                  ],
                ),
              ],
            ),
            if (forecast != null && variance != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Row(
                children: [
                  Text(
                    'Forecast EOP (${forecast!.methodLabel}): '
                    '${Money.formatIdr(forecast!.forecastEopMinor)} • ',
                  ),
                  const Text('Varians proyeksi: '),
                  MoneyText(variance, signed: true),
                ],
              ),
              if (forecast!.lowConfidence)
                Text(
                  'Kepercayaan rendah: riwayat pendek.',
                  style: TextStyle(color: context.finance.warning),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Forecast (PRD §5.8): run_rate / scheduled / hybrid, method + assumptions,
/// low-confidence label, scenario simulation that never mutates data.
class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  ForecastMethod _method = ForecastMethod.runRate;
  bool _loading = true;
  SupabaseFailure? _failure;
  int _actual = 0;
  int _budgetTotal = 0;
  double _extraExpense = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppState.instance;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final totals = await state.finance.periodTotals(state.period);
      final budgets = await state.finance.listBudgets();
      var budgetTotal = 0;
      for (final b in budgets) {
        budgetTotal += (b['amount_minor'] as num?)?.toInt() ?? 0;
      }
      if (mounted) {
        setState(() {
          _actual = totals.expense;
          _budgetTotal = budgetTotal;
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

  ForecastResult _result() {
    final now = JakartaTime.now();
    final elapsed = now.day;
    final totalDays = DateTime(now.year, now.month + 1, 0).day;
    return switch (_method) {
      ForecastMethod.runRate => Forecast.runRate(
          actualToDateMinor: _actual,
          elapsedDays: elapsed,
          totalDays: totalDays),
      ForecastMethod.scheduled => Forecast.scheduled(
          actualToDateMinor: _actual,
          scheduledFutureMinor: 0,
          elapsedDays: elapsed,
          totalDays: totalDays),
      ForecastMethod.hybrid => Forecast.hybrid(
          actualToDateMinor: _actual,
          scheduledFutureMinor: 0,
          dailyVariableEstimateMinor:
              elapsed > 0 ? (_actual / elapsed).round() : 0,
          elapsedDays: elapsed,
          totalDays: totalDays),
    };
  }

  @override
  Widget build(BuildContext context) {
    final result = _result();
    final simulated = Forecast.simulate(
      baseForecastEopMinor: result.forecastEopMinor,
      extraExpenseMinor: _extraExpense.round(),
    );
    final variance = BudgetMath.projectedVariance(_budgetTotal, result.forecastEopMinor);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Forecast', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Periode: ${AppState.instance.period.label}. '
            'Metode dan asumsi selalu ditampilkan; riwayat pendek diberi '
            'label kepercayaan rendah.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            SegmentedButton<ForecastMethod>(
              segments: const [
                ButtonSegment(
                    value: ForecastMethod.runRate, label: Text('Run Rate')),
                ButtonSegment(
                    value: ForecastMethod.scheduled,
                    label: Text('Scheduled')),
                ButtonSegment(
                    value: ForecastMethod.hybrid, label: Text('Hybrid')),
              ],
              selected: {_method},
              onSelectionChanged: (s) =>
                  setState(() => _method = s.first),
            ),
            const SizedBox(height: AppSpacing.s16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Forecast Akhir Periode (${result.methodLabel})',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    MoneyText(result.forecastEopMinor,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.s8),
                    Text('Actual s.d. hari ini: ${Money.formatIdr(_actual)}'),
                    Text('Total budget: ${Money.formatIdr(_budgetTotal)}'),
                    Row(children: [
                      const Text('Varians proyeksi: '),
                      MoneyText(variance, signed: true),
                    ]),
                    const SizedBox(height: AppSpacing.s8),
                    const Text('Asumsi:',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    for (final a in result.assumptions)
                      Text('• $a'),
                    if (result.lowConfidence)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.s8),
                        child: Text(
                          'Kepercayaan rendah: riwayat data pendek, '
                          'jangan jadikan satu-satunya dasar keputusan.',
                          style: TextStyle(color: context.finance.warning),
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
                    const Text('Simulasi Skenario (tidak mengubah data)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    const Text(
                      'Tambah pengeluaran hipotetis dan lihat dampaknya. '
                      'Simulasi saja — transaksi dan budget tidak berubah.',
                    ),
                    Slider(
                      value: _extraExpense,
                      min: 0,
                      max: 5000000,
                      divisions: 50,
                      label: Money.formatIdr(_extraExpense.round()),
                      onChanged: (v) =>
                          setState(() => _extraExpense = v),
                    ),
                    Text(
                        'Pengeluaran tambahan: ${Money.formatIdr(_extraExpense.round())}'),
                    Text(
                        'Forecast hasil simulasi: ${Money.formatIdr(simulated)}'),
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
                    const Text('Contoh PRD §5.8 (ilustrasi metode)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const Text(
                      'Budget Rp5.000.000, actual Rp2.800.000 dalam 14 dari '
                      '30 hari → run-rate forecast Rp6.000.000, sisa '
                      'Rp2.200.000, varians proyeksi −Rp1.000.000. Ini '
                      'ilustrasi metode sederhana, bukan forecast historis '
                      'yang terkalibrasi.',
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
}

/// Analytics (PRD §5.6): category breakdown + cashflow chart.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  int _income = 0;
  int _expense = 0;
  Map<String, int> _byCategory = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppState.instance;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final totals = await state.finance.periodTotals(state.period);
      final rows = await state.finance.listTransactions(
          period: state.period, limit: 1000);
      final cats = await state.finance.listCategories();
      final names = {
        for (final c in cats) c['id'] as String: (c['name'] as String?) ?? ''
      };
      final byCat = <String, int>{};
      for (final r in rows) {
        if (r['type'] != 'expense' || r['status'] != 'posted') continue;
        final key = names[r['category_id'] as String?] ?? 'Tanpa kategori';
        byCat[key] = (byCat[key] ?? 0) +
            ((r['amount_minor'] as num?)?.toInt() ?? 0);
      }
      if (mounted) {
        setState(() {
          _income = totals.income;
          _expense = totals.expense;
          _byCategory = byCat;
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
    final entries = _byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analitik', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s8),
          Text('Periode: ${AppState.instance.period.label}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            Row(
              children: [
                Expanded(
                    child: KpiCard(
                        label: 'Pemasukan', valueMinor: _income, signed: true)),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                    child: KpiCard(
                        label: 'Pengeluaran',
                        valueMinor: -_expense,
                        signed: true)),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pengeluaran per Kategori',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.s8),
                    if (entries.isEmpty)
                      const Text('Belum ada pengeluaran posted.'),
                    SizedBox(
                      height: 200,
                      child: entries.isEmpty
                          ? const SizedBox.shrink()
                          : PieChart(
                              PieChartData(
                                sections: entries
                                    .take(6)
                                    .map((e) => PieChartSectionData(
                                          value: e.value.toDouble(),
                                          title:
                                              '${(e.value / (_expense == 0 ? 1 : _expense) * 100).toStringAsFixed(0)}%',
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ))
                                    .toList(),
                              ),
                            ),
                    ),
                    for (final e in entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.key),
                        trailing: MoneyText(e.value),
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
}
