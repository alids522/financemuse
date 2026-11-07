import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

/// Money: integer minor units (rupiah has no minor subunit in practice —
/// 1 IDR = 1 minor unit). Never use double for authoritative money (PRD §9.4).
class Money {
  Money._();

  static final _idr =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _idrCompact =
      NumberFormat.compactCurrency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 1);

  /// Format an integer minor-unit amount as IDR, e.g. 35000 -> "Rp 35.000".
  static String formatIdr(int minor, {bool compact = false}) {
    if (compact) return _idrCompact.format(minor);
    return _idr.format(minor);
  }

  /// Signed format: +Rp 6.000.000 / -Rp 35.000.
  static String formatSigned(int minor) {
    final sign = minor > 0 ? '+' : (minor < 0 ? '−' : '');
    return '$sign${_idr.format(minor.abs())}';
  }

  /// Parse user input ("35.000", "Rp 35.000", "35000") to minor units.
  /// Returns null when the text is not a positive integer amount.
  /// A minus sign anywhere means a negative amount, which is rejected.
  static int? parse(String input) {
    if (input.contains('-')) return null;
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final value = int.tryParse(digits);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// Validate that split amounts sum exactly to the parent amount (PRD §5.3).
  static bool splitsSumToParent(List<int> splits, int parent) {
    var sum = 0;
    for (final s in splits) {
      if (s <= 0) return false;
      sum += s;
    }
    return sum == parent;
  }
}

/// Date/time helpers for Asia/Jakarta (UTC+7, no DST).
class JakartaTime {
  JakartaTime._();
  static const Duration offset = Duration(hours: 7);
  static const String zoneName = 'Asia/Jakarta';

  /// Convert a UTC instant to Jakarta wall time.
  static DateTime toJakarta(DateTime utc) => utc.toUtc().add(offset);

  /// Convert Jakarta wall time to a UTC instant.
  static DateTime toUtc(DateTime jakartaWall) =>
      DateTime.utc(jakartaWall.year, jakartaWall.month, jakartaWall.day,
              jakartaWall.hour, jakartaWall.minute, jakartaWall.second,
              jakartaWall.millisecond)
          .subtract(offset);

  static DateTime now() => DateTime.now().toUtc().add(offset);
}

/// Period boundaries. Month = calendar month, never "last 30 days" (PRD §5.5,
/// AC-08). Returned instants are UTC; the local wall-clock boundaries are
/// midnight Asia/Jakarta.
class PeriodRange {
  const PeriodRange(this.startUtc, this.endUtcExclusive, this.label);
  final DateTime startUtc; // inclusive
  final DateTime endUtcExclusive; // exclusive
  final String label;

  bool contains(DateTime utc) =>
      !utc.isBefore(startUtc) && utc.isBefore(endUtcExclusive);
}

class Periods {
  Periods._();

  static PeriodRange day(DateTime jakartaDate) {
    final start = DateTime(jakartaDate.year, jakartaDate.month, jakartaDate.day);
    return PeriodRange(
      JakartaTime.toUtc(start),
      JakartaTime.toUtc(start.add(const Duration(days: 1))),
      'Hari ${start.day}/${start.month}/${start.year}',
    );
  }

  static PeriodRange week(DateTime jakartaDate, {int weekStart = DateTime.monday}) {
    var start = DateTime(jakartaDate.year, jakartaDate.month, jakartaDate.day);
    while (start.weekday != weekStart) {
      start = start.subtract(const Duration(days: 1));
    }
    final end = start.add(const Duration(days: 7));
    return PeriodRange(
      JakartaTime.toUtc(start),
      JakartaTime.toUtc(end),
      'Minggu ${start.day}/${start.month} – ${end.subtract(const Duration(days: 1)).day}/${end.subtract(const Duration(days: 1)).month}',
    );
  }

  /// Calendar month (AC-08): 1 Nov 00:00 Jakarta .. 1 Dec 00:00 Jakarta.
  static PeriodRange month(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return PeriodRange(
      JakartaTime.toUtc(start),
      JakartaTime.toUtc(end),
      _monthName(month, year),
    );
  }

  static PeriodRange year(int year) {
    return PeriodRange(
      JakartaTime.toUtc(DateTime(year, 1, 1)),
      JakartaTime.toUtc(DateTime(year + 1, 1, 1)),
      'Tahun $year',
    );
  }

  static PeriodRange custom(DateTime jakartaStartDay, DateTime jakartaEndDay) {
    // Inclusive both days, Jakarta wall time.
    final start = DateTime(jakartaStartDay.year, jakartaStartDay.month, jakartaStartDay.day);
    final end = DateTime(jakartaEndDay.year, jakartaEndDay.month, jakartaEndDay.day)
        .add(const Duration(days: 1));
    return PeriodRange(
      JakartaTime.toUtc(start),
      JakartaTime.toUtc(end),
      'Kustom ${start.day}/${start.month}/${start.year} – ${jakartaEndDay.day}/${jakartaEndDay.month}/${jakartaEndDay.year}',
    );
  }

  static String _monthName(int month, int year) {
    const names = [
      '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    return '${names[month]} $year';
  }
}

/// Idempotency keys (PRD §5.3, §12): one UUID per create, reused on retry.
String newIdempotencyKey() => const Uuid().v4();
