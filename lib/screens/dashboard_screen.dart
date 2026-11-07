import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/forecast.dart';
import '../utils/money_period.dart';
import '../widgets/common.dart';

/// Dashboard (PRD §5.6): total balance, income/expense/net, budget
/// utilisation, recent transactions. Balance is computed from opening
/// balances + posted transactions; the authoritative source is the journal
/// ledger (PRD §9.3) — labelled in-app until a balance view exists.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  SupabaseFailure? _failure;
  int _totalBalance = 0;
  int _income = 0;
  int _expense = 0;
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _budgets = [];
  final Map<String, int> _budgetActual = {};

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
      final accounts = await state.finance.listAccounts();
      final totals = await state.finance.periodTotals(state.period);
      final recent = await state.finance.listTransactions(
        period: state.period,
        limit: 10,
      );
      var balance = 0;
      for (final a in accounts) {
        balance += (a['opening_balance'] as num?)?.toInt() ?? 0;
      }
      // Apply posted transactions to opening balances (client-side
      // computation; journal ledger is authoritative — see README).
      final all = await state.finance.listTransactions(limit: 1000);
      for (final t in all) {
        if (t['status'] != 'posted') continue;
        final amount = (t['amount'] as num?)?.toInt() ?? 0;
        if (t['type'] == 'income') balance += amount;
        if (t['type'] == 'expense') balance -= amount;
      }
      List<Map<String, dynamic>> budgets = [];
      try {
        budgets = await state.finance.listBudgets();
        for (final b in budgets) {
          final catId = b['category_id'] as String?;
          if (catId != null) {
            _budgetActual[b['id'] as String] =
                await state.finance.categoryActual(catId, state.period);
          }
        }
      } catch (_) {
        budgets = [];
      }
      if (!mounted) return;
      setState(() {
        _totalBalance = balance;
        _income = totals.income;
        _expense = totals.expense;
        _recent = recent;
        _budgets = budgets;
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
    final now = JakartaTime.now();
    final elapsed = now.day;
    final totalDays = DateTime(now.year, now.month + 1, 0).day;
    final forecast = Forecast.runRate(
      actualToDateMinor: _expense,
      elapsedDays: elapsed,
      totalDays: totalDays,
    );
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
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Muat ulang',
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_failure != null) SchemaNotice(failure: _failure),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            LayoutBuilder(
              builder: (ctx, constraints) {
                final wide = constraints.maxWidth > 900;
                final cards = [
                  KpiCard(
                      label: 'Total Saldo',
                      valueMinor: _totalBalance,
                      subLabel: 'Dihitung dari saldo awal + transaksi posted'),
                  KpiCard(
                      label: 'Pemasukan (${state.period.label})',
                      valueMinor: _income,
                      signed: true),
                  KpiCard(
                      label: 'Pengeluaran (${state.period.label})',
                      valueMinor: -_expense,
                      signed: true),
                  KpiCard(
                      label: 'Arus Kas Bersih',
                      valueMinor: _income - _expense,
                      signed: true),
                ];
                if (wide) {
                  return Row(
                    children: cards
                        .map((c) => Expanded(child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: c)))
                        .toList(),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: cards
                      .map((c) => SizedBox(
                          width: (constraints.maxWidth - 8) / 2, child: c))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: AppSpacing.s16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Arus Kas',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: AppSpacing.s8),
                          SizedBox(
                            height: 180,
                            child: BarChart(
                              BarChartData(
                                barGroups: [
                                  BarChartGroupData(x: 0, barRods: [
                                    BarChartRodData(
                                        toY: _income.toDouble(),
                                        color: context.finance.positive,
                                        width: 28),
                                  ]),
                                  BarChartGroupData(x: 1, barRods: [
                                    BarChartRodData(
                                        toY: _expense.toDouble(),
                                        color: context.finance.negative,
                                        width: 28),
                                  ]),
                                ],
                                titlesData: FlTitlesData(
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (v, _) => Text(
                                          v == 0 ? 'Masuk' : 'Keluar'),
                                    ),
                                  ),
                                  leftTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                ),
                                gridData: const FlGridData(show: false),
                                borderData: FlBorderData(show: false),
                              ),
                            ),
                          ),
                          Text(
                            'Forecast akhir periode (run_rate): '
                            '${Money.formatIdr(forecast.forecastEopMinor)} '
                            '— ${forecast.assumptions.first}.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (forecast.lowConfidence)
                            Text(
                              'Kepercayaan rendah: riwayat pendek.',
                              style: TextStyle(
                                  color: context.finance.warning),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Status Budget',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: AppSpacing.s8),
                          if (_budgets.isEmpty)
                            const Text(
                                'Belum ada budget. Buat di menu Budget.'),
                          for (final b in _budgets.take(5))
                            _BudgetRow(
                              name: (b['name'] as String?) ?? 'Budget',
                              budget: (b['amount'] as num?)?.toInt() ?? 0,
                              actual: _budgetActual[b['id'] as String] ?? 0,
                            ),
                          TextButton(
                            onPressed: () => context.go('/budgets'),
                            child: const Text('Lihat semua budget'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Transaksi Terakhir',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        TextButton(
                          onPressed: () => context.go('/transactions'),
                          child: const Text('Lihat semua'),
                        ),
                      ],
                    ),
                    if (_recent.isEmpty)
                      const Text('Belum ada transaksi pada periode ini.'),
                    for (final t in _recent)
                      ListTile(
                        title: Text((t['description'] as String?) ??
                            (t['merchant'] as String?) ??
                            (t['type'] as String)),
                        subtitle: Text(
                            (t['effective_at'] as String?)?.substring(0, 10) ??
                                ''),
                        trailing: MoneyText(
                          (t['type'] == 'expense'
                                  ? -1
                                  : 1) *
                              ((t['amount'] as num?)?.toInt() ?? 0),
                          signed: true,
                        ),
                        onTap: () =>
                            context.go('/transactions/${t['id']}'),
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

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.name,
    required this.budget,
    required this.actual,
  });
  final String name;
  final int budget;
  final int actual;

  @override
  Widget build(BuildContext context) {
    final util = BudgetMath.utilisation(budget, actual);
    final remaining = BudgetMath.remaining(budget, actual);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name),
              MoneyText(remaining,
                  signed: true,
                  style: TextStyle(
                      color: remaining < 0
                          ? context.finance.negative
                          : null)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: util.isFinite ? util.clamp(0, 1) : 1,
            color: util > 1
                ? context.finance.negative
                : Theme.of(context).colorScheme.primary,
          ),
          Text(
            '${Money.formatIdr(actual)} dari ${Money.formatIdr(budget)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
