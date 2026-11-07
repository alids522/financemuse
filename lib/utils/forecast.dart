/// Budget & forecast math (PRD §5.7, §5.8). Pure functions, unit-tested.
/// All amounts are integer minor units (IDR).
class BudgetMath {
  BudgetMath._();

  /// remaining = budget - actual. Negative means overspend.
  static int remaining(int budgetMinor, int actualMinor) =>
      budgetMinor - actualMinor;

  /// projected variance = budget - forecast EOP. Negative = projected overspend.
  static int projectedVariance(int budgetMinor, int forecastEopMinor) =>
      budgetMinor - forecastEopMinor;

  /// Utilisation 0..n (1.0 = 100%). >1.0 is overspend, shown red.
  static double utilisation(int budgetMinor, int actualMinor) {
    if (budgetMinor <= 0) return actualMinor > 0 ? double.infinity : 0;
    return actualMinor / budgetMinor;
  }
}

enum ForecastMethod { runRate, scheduled, hybrid }

class ForecastResult {
  const ForecastResult({
    required this.method,
    required this.forecastEopMinor,
    required this.actualToDateMinor,
    required this.scheduledFutureMinor,
    required this.elapsedDays,
    required this.totalDays,
    required this.assumptions,
    required this.lowConfidence,
  });
  final ForecastMethod method;
  final int forecastEopMinor;
  final int actualToDateMinor;
  final int scheduledFutureMinor;
  final int elapsedDays;
  final int totalDays;
  final List<String> assumptions;
  final bool lowConfidence;

  String get methodLabel => switch (method) {
        ForecastMethod.runRate => 'run_rate',
        ForecastMethod.scheduled => 'scheduled',
        ForecastMethod.hybrid => 'hybrid',
      };
}

class Forecast {
  Forecast._();

  /// run_rate: actual_to_date / elapsed_days * total_days.
  /// PRD example: budget 5.000.000, actual 2.800.000, 14/30 hari
  /// => forecast 6.000.000, remaining 2.200.000, variance -1.000.000.
  static ForecastResult runRate({
    required int actualToDateMinor,
    required int elapsedDays,
    required int totalDays,
  }) {
    final forecast = elapsedDays <= 0
        ? actualToDateMinor
        : (actualToDateMinor * totalDays / elapsedDays).round();
    return ForecastResult(
      method: ForecastMethod.runRate,
      forecastEopMinor: forecast,
      actualToDateMinor: actualToDateMinor,
      scheduledFutureMinor: 0,
      elapsedDays: elapsedDays,
      totalDays: totalDays,
      assumptions: [
        '$elapsedDays hari elapsed',
        '$totalDays hari dalam periode',
        'tanpa jadwal future terpisah',
        'Metode sederhana run-rate, bukan forecast historis terkalibrasi.',
      ],
      lowConfidence: elapsedDays < 7 || totalDays <= 0,
    );
  }

  /// scheduled: posted actual + future recurring/bills not yet posted.
  static ForecastResult scheduled({
    required int actualToDateMinor,
    required int scheduledFutureMinor,
    required int elapsedDays,
    required int totalDays,
  }) {
    return ForecastResult(
      method: ForecastMethod.scheduled,
      forecastEopMinor: actualToDateMinor + scheduledFutureMinor,
      actualToDateMinor: actualToDateMinor,
      scheduledFutureMinor: scheduledFutureMinor,
      elapsedDays: elapsedDays,
      totalDays: totalDays,
      assumptions: [
        'Actual posted + transaksi recurring/tagihan masa depan yang belum posted.',
        '$elapsedDays hari elapsed dari $totalDays hari.',
      ],
      lowConfidence: elapsedDays < 7,
    );
  }

  /// hybrid: posted actual + known scheduled future + historical variable
  /// spend estimate for remaining days (avoids double-counting scheduled).
  static ForecastResult hybrid({
    required int actualToDateMinor,
    required int scheduledFutureMinor,
    required int dailyVariableEstimateMinor,
    required int elapsedDays,
    required int totalDays,
  }) {
    final remainingDays = (totalDays - elapsedDays).clamp(0, totalDays);
    final forecast = actualToDateMinor +
        scheduledFutureMinor +
        dailyVariableEstimateMinor * remainingDays;
    return ForecastResult(
      method: ForecastMethod.hybrid,
      forecastEopMinor: forecast,
      actualToDateMinor: actualToDateMinor,
      scheduledFutureMinor: scheduledFutureMinor,
      elapsedDays: elapsedDays,
      totalDays: totalDays,
      assumptions: [
        'Actual posted + jadwal future + estimasi variabel harian untuk $remainingDays hari tersisa.',
        'Tagihan terjadwal tidak dihitung ganda.',
      ],
      lowConfidence: elapsedDays < 7,
    );
  }

  /// What-if simulation: never mutates data (PRD §5.8). Applies extra
  /// hypothetical expense/income deltas to a base forecast.
  static int simulate({
    required int baseForecastEopMinor,
    int extraExpenseMinor = 0,
    int extraIncomeMinor = 0,
  }) =>
      baseForecastEopMinor + extraExpenseMinor - extraIncomeMinor;
}
