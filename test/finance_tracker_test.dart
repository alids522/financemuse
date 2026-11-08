import 'package:financemuse/services/auth_service.dart';
import 'package:financemuse/services/csv_service.dart';
import 'package:financemuse/services/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:financemuse/services/mcp_policy.dart';
import 'package:financemuse/utils/forecast.dart';
import 'package:financemuse/utils/money_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money (minor units)', () {
    test('parse strips Rp and separators', () {
      expect(Money.parse('35.000'), 35000);
      expect(Money.parse('Rp 35.000'), 35000);
      expect(Money.parse('35000'), 35000);
      expect(Money.parse('0'), isNull);
      expect(Money.parse('-5000'), isNull); // negative rejected
      expect(Money.parse('abc'), isNull);
    });

    test('formatIdr uses Indonesian separators', () {
      expect(Money.formatIdr(35000), contains('35.000'));
      expect(Money.formatIdr(5000000), contains('5.000.000'));
    });

    test('splits must sum exactly to parent', () {
      expect(Money.splitsSumToParent([20000, 15000], 35000), isTrue);
      expect(Money.splitsSumToParent([20000, 14000], 35000), isFalse);
      expect(Money.splitsSumToParent([35000], 35000), isTrue);
      expect(Money.splitsSumToParent([0, 35000], 35000), isFalse);
      expect(Money.splitsSumToParent([-5000, 40000], 35000), isFalse);
    });
  });

  group('Period boundaries (Asia/Jakarta)', () {
    test('Month is a calendar month, not last 30 days (AC-08)', () {
      final nov = Periods.month(2026, 11);
      // 1 Nov 2026 00:00 Jakarta = 31 Oct 2026 17:00 UTC.
      expect(nov.startUtc, DateTime.utc(2026, 10, 31, 17));
      // 1 Dec 2026 00:00 Jakarta = 30 Nov 2026 17:00 UTC.
      expect(nov.endUtcExclusive, DateTime.utc(2026, 11, 30, 17));
      expect(nov.contains(DateTime.utc(2026, 11, 1, 0)), isTrue);
      expect(nov.contains(DateTime.utc(2026, 11, 30, 16, 59)), isTrue);
      expect(nov.contains(DateTime.utc(2026, 11, 30, 17)), isFalse);
      expect(nov.contains(DateTime.utc(2026, 10, 31, 16, 59)), isFalse);
    });

    test('February in a leap year spans 29 days', () {
      final feb = Periods.month(2028, 2);
      expect(feb.startUtc, DateTime.utc(2028, 1, 31, 17));
      expect(feb.endUtcExclusive, DateTime.utc(2028, 2, 29, 17));
    });

    test('Year boundaries are calendar years', () {
      final y = Periods.year(2026);
      expect(y.startUtc, DateTime.utc(2025, 12, 31, 17));
      expect(y.endUtcExclusive, DateTime.utc(2026, 12, 31, 17));
    });

    test('Custom range is inclusive of both days (Jakarta)', () {
      final r = Periods.custom(DateTime(2026, 11, 7), DateTime(2026, 11, 9));
      expect(r.startUtc, DateTime.utc(2026, 11, 6, 17));
      expect(r.endUtcExclusive, DateTime.utc(2026, 11, 9, 17));
      expect(r.contains(DateTime.utc(2026, 11, 9, 16)), isTrue);
      expect(r.contains(DateTime.utc(2026, 11, 9, 17)), isFalse);
    });

    test('Week starts Monday by default', () {
      // Saturday 7 Nov 2026 -> week starts Monday 2 Nov 2026.
      final w = Periods.week(DateTime(2026, 11, 7));
      expect(w.startUtc, DateTime.utc(2026, 11, 1, 17));
      expect(w.endUtcExclusive, DateTime.utc(2026, 11, 8, 17));
    });
  });

  group('Budget & forecast (PRD §5.7–5.8)', () {
    test('PRD example: budget 5jt, actual 2.8jt, 14/30 days', () {
      final result = Forecast.runRate(
        actualToDateMinor: 2800000,
        elapsedDays: 14,
        totalDays: 30,
      );
      expect(result.forecastEopMinor, 6000000);
      expect(BudgetMath.remaining(5000000, 2800000), 2200000);
      expect(
        BudgetMath.projectedVariance(5000000, result.forecastEopMinor),
        -1000000,
      );
    });

    test('overspend shows negative remaining and utilisation > 1', () {
      expect(BudgetMath.remaining(5000000, 6000000), -1000000);
      expect(BudgetMath.utilisation(5000000, 6000000), greaterThan(1.0));
    });

    test('scheduled forecast adds future scheduled amounts', () {
      final result = Forecast.scheduled(
        actualToDateMinor: 2800000,
        scheduledFutureMinor: 1200000,
        elapsedDays: 14,
        totalDays: 30,
      );
      expect(result.forecastEopMinor, 4000000);
    });

    test('hybrid avoids double counting scheduled bills', () {
      final result = Forecast.hybrid(
        actualToDateMinor: 2800000,
        scheduledFutureMinor: 1000000,
        dailyVariableEstimateMinor: 50000,
        elapsedDays: 14,
        totalDays: 30,
      );
      // 2.8jt + 1jt + 50rb * 16 hari tersisa = 4.6jt.
      expect(result.forecastEopMinor, 4600000);
    });

    test('scenario simulation never mutates the base forecast', () {
      const base = 6000000;
      expect(
        Forecast.simulate(baseForecastEopMinor: base, extraExpenseMinor: 1000000),
        7000000,
      );
      expect(base, 6000000);
    });

    test('run-rate with zero elapsed days falls back to actual', () {
      final result = Forecast.runRate(
        actualToDateMinor: 100000,
        elapsedDays: 0,
        totalDays: 30,
      );
      expect(result.forecastEopMinor, 100000);
      expect(result.lowConfidence, isTrue);
    });
  });

  group('Idempotency keys', () {
    test('keys are unique UUIDs', () {
      final a = newIdempotencyKey();
      final b = newIdempotencyKey();
      expect(a, isNot(b));
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(a),
        isTrue,
      );
    });
  });

  group('MCP policy matrix (PRD §6.2–6.3)', () {
    test('create <= Rp1.000.000 auto-allow', () {
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsCreate,
          permissionEnabled: true,
          amountMinor: 1000000,
        ),
        McpDecision.autoAllow,
      );
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsCreate,
          permissionEnabled: true,
          amountMinor: 500000,
        ),
        McpDecision.autoAllow,
      );
    });

    test('create > Rp1.000.000 requires approval', () {
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsCreate,
          permissionEnabled: true,
          amountMinor: 1000001,
        ),
        McpDecision.approvalRequired,
      );
    });

    test('transfer always requires approval', () {
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsCreate,
          permissionEnabled: true,
          amountMinor: 100000,
          isTransfer: true,
        ),
        McpDecision.approvalRequired,
      );
    });

    test('edit delta <= Rp250.000 auto-allow, above requires approval', () {
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsUpdate,
          permissionEnabled: true,
          deltaMinor: 250000,
        ),
        McpDecision.autoAllow,
      );
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsUpdate,
          permissionEnabled: true,
          deltaMinor: 250001,
        ),
        McpDecision.approvalRequired,
      );
    });

    test('sensitive field change requires approval even for small delta', () {
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsUpdate,
          permissionEnabled: true,
          deltaMinor: 1000,
          sensitiveFieldChanged: true,
        ),
        McpDecision.approvalRequired,
      );
    });

    test('delete / bulk / export / admin are denied or approval-only', () {
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsDelete,
          permissionEnabled: true,
        ),
        McpDecision.approvalRequired,
      );
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsDelete,
          permissionEnabled: false,
        ),
        McpDecision.denied,
      );
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.admin,
          permissionEnabled: true,
        ),
        McpDecision.denied,
      );
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.agentPermissionsWrite,
          permissionEnabled: true,
        ),
        McpDecision.denied,
      );
    });

    test('reads auto-allow when enabled, denied when disabled', () {
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsRead,
          permissionEnabled: true,
        ),
        McpDecision.autoAllow,
      );
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsRead,
          permissionEnabled: false,
        ),
        McpDecision.denied,
      );
    });

    test('invalid amounts are denied', () {
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsCreate,
          permissionEnabled: true,
          amountMinor: 0,
        ),
        McpDecision.denied,
      );
      expect(
        McpPolicy.evaluateAction(
          scope: McpScope.transactionsCreate,
          permissionEnabled: true,
          amountMinor: -5000,
        ),
        McpDecision.denied,
      );
    });
  });

  group('CSV', () {
    test('duplicate fingerprint is stable and order-sensitive to fields', () {
      final a = CsvService.fingerprint(
        account: 'Cash',
        date: '2026-11-07',
        amountMinor: 35000,
        description: 'Makan Siang!',
      );
      final b = CsvService.fingerprint(
        account: 'Cash',
        date: '2026-11-07',
        amountMinor: 35000,
        description: 'makan siang',
      );
      expect(a, b); // normalised description
      expect(
        CsvService.fingerprint(
          account: 'Bank',
          date: '2026-11-07',
          amountMinor: 35000,
          description: 'Makan Siang!',
        ),
        isNot(a),
      );
    });

    test('parse returns rows and flags short rows', () {
      final parsed = CsvService.parse(
        'transaction_id,date_time,type,amount,currency\n'
        '1,2026-11-07T10:00:00+07:00,expense,35000,IDR\n'
        'bad\n',
      );
      expect(parsed.rows.length, 1);
      expect(parsed.rows.first['amount'], '35000');
      expect(parsed.errors.length, 1);
    });

    test('export maps DB-shaped rows (amount_minor, effective_at) to CSV headers', () {
      final csv = CsvService.exportRows([
        {
          'id': 'db-row-1',
          'effective_at': '2026-11-07T10:00:00+07:00',
          'type': 'expense',
          'amount_minor': 35000,
          'currency': 'IDR',
          'account_id': 'acc-1',
          'category_id': 'cat-1',
          'description': 'Makan siang',
        }
      ]);
      final lines = csv.split('\n');
      expect(lines.first, contains('transaction_id'));
      expect(lines[1], contains('db-row-1'));
      expect(lines[1], contains('2026-11-07'));
      expect(lines[1], contains('35000'));
      expect(lines[1], contains('acc-1'));
    });

    test('export round-trips headers', () {
      final csv = CsvService.exportRows([
        {
          'transaction_id': 'x',
          'date_time': '2026-11-07',
          'type': 'expense',
          'amount': 35000,
          'currency': 'IDR',
        }
      ]);
      expect(csv.split('\n').first, contains('transaction_id'));
      expect(csv, contains('35000'));
    });
  });
  group('Password validation (min 12, equality only)', () {
    test('8-11 chars rejected with min-12 message', () {
      expect(AuthService.validatePassword('Abc12345'),
          'Kata sandi minimal 12 karakter.');
      expect(AuthService.validatePassword('Abc12345678'),
          'Kata sandi minimal 12 karakter.');
    });

    test('12 chars accepted', () {
      expect(AuthService.validatePassword('Abcdef123456'), isNull);
    });

    test('password equal to username rejected (case-insensitive)', () {
      expect(AuthService.validatePassword('adoetz123456',
              username: 'adoetz123456'),
          'Kata sandi tidak boleh sama dengan username.');
      expect(AuthService.validatePassword('ADOETZ123456',
              username: 'adoetz123456'),
          'Kata sandi tidak boleh sama dengan username.');
    });

    test('password merely containing username accepted', () {
      expect(AuthService.validatePassword('Kuat-adoetz-2026',
              username: 'adoetz'),
          isNull);
    });

    test('password equal to email or its local-part rejected', () {
      expect(AuthService.validatePassword('adoetzku1234@mail.com',
              email: 'adoetzku1234@mail.com'),
          'Kata sandi tidak boleh sama dengan email.');
      expect(AuthService.validatePassword('adoetzku1234',
              email: 'adoetzku1234@mail.com'),
          'Kata sandi tidak boleh sama dengan email.');
    });

    test('password merely containing email local-part accepted', () {
      expect(AuthService.validatePassword('Kuat-adoetzku1234-9',
              email: 'adoetzku1234@mail.com'),
          isNull);
    });
  });

  group('Signup vs login error mapping', () {
    test('signup short-password AuthException maps to min-12 message', () {
      final err = mapSignupError(const AuthException(
          'Password should be at least 12 characters.',
          statusCode: '422',
          code: 'weak_password'));
      expect(err.message, 'Kata sandi minimal 12 karakter.');
    });

    test('signup already-registered maps to a specific message', () {
      final err = mapSignupError(
          const AuthException('User already registered', statusCode: '422'));
      expect(err.message, 'Email sudah terdaftar. Silakan masuk.');
    });

    test('signup network failure maps to connectivity message', () {
      final err = mapSignupError(
          Exception('Failed host lookup: supabase.adoetz52.my.id'));
      expect(
          err.message,
          'Tidak dapat terhubung ke server. Periksa koneksi internet, '
          'lalu coba lagi.');
    });

    test('signup database error maps to server message', () {
      final err = mapSignupError(const AuthException(
          'Database error saving new user', statusCode: '500'));
      expect(
          err.message,
          'Pendaftaran gagal di server. Coba lagi; jika berlanjut, '
          'hubungi admin.');
    });

    test('signup rate limit maps to wait message', () {
      final err = mapSignupError(
          const AuthException('Email rate limit exceeded',
              statusCode: '429'));
      expect(err.message,
          'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.');
    });

    test('build marker defaults are non-empty', () {
      expect(SupabaseConfig.appVersion.isNotEmpty, isTrue);
      expect(SupabaseConfig.appCommit.isNotEmpty, isTrue);
    });

    test('login AuthException stays generic (no enumeration)', () {
      final err = mapSupabaseError(
          const AuthException('Invalid login credentials', statusCode: '400'));
      expect(err.message, 'Email atau kata sandi salah.');
      final weak = mapSupabaseError(const AuthException(
          'Password should be at least 12 characters.',
          statusCode: '422',
          code: 'weak_password'));
      expect(weak.message, 'Email atau kata sandi salah.');
    });
  });

}
