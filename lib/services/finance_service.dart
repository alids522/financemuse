import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/money_period.dart';
import 'supabase_client.dart';

/// Data layer for all Finance Tracker tables (PRD §10), via the Supabase
/// client on schema `financemuse`.
///
/// NOTE: PostgREST does not expose the `financemuse` schema yet, so these
/// calls fail at runtime until exposure is decided. Every screen catches
/// [SupabaseFailure] and shows an in-app notice — data is never faked and
/// there is no silent fallback to mock data.
class FinanceService {
  FinanceService(this._client);
  final SupabaseClient _client;

  String get _userId => _client.auth.currentUser!.id;

  // ---------------------------------------------------------------- accounts
  Future<List<Map<String, dynamic>>> listAccounts() async {
    try {
      final rows = await _client
          .table('accounts')
          .select()
          .eq('user_id', _userId)
          .order('name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> createAccount({
    required String name,
    required String type,
    required String currency,
    required int openingBalanceMinor,
  }) async {
    try {
      await _client.table('accounts').insert({
        'user_id': _userId,
        'name': name,
        'type': type,
        'currency': currency,
        'opening_balance': openingBalanceMinor,
        'status': 'active',
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> updateAccount(String id, Map<String, dynamic> patch) async {
    try {
      await _client.table('accounts').update(patch).eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Delete is blocked when transactions exist (PRD §5.2).
  Future<void> deleteAccount(String id) async {
    try {
      final used = await _client
          .table('transactions')
          .select('id')
          .eq('account_id', id)
          .limit(1);
      if (used.isNotEmpty) {
        throw SupabaseFailure(
          'Akun tidak dapat dihapus karena masih memiliki transaksi. '
          'Arsipkan akun sebagai gantinya.',
        );
      }
      await _client.table('accounts').delete().eq('id', id);
    } on SupabaseFailure {
      rethrow;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ------------------------------------------------------------ transactions
  Future<List<Map<String, dynamic>>> listTransactions({
    PeriodRange? period,
    String? type,
    String? accountId,
    String? categoryId,
    String? status,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var q = _client
          .table('transactions')
          .select()
          .eq('user_id', _userId)
          .isFilter('deleted_at', null);
      if (period != null) {
        q = q
            .gte('effective_at', period.startUtc.toIso8601String())
            .lt('effective_at', period.endUtcExclusive.toIso8601String());
      }
      if (type != null) q = q.eq('type', type);
      if (accountId != null) q = q.eq('account_id', accountId);
      if (categoryId != null) q = q.eq('category_id', categoryId);
      if (status != null) q = q.eq('status', status);
      if (search != null && search.isNotEmpty) {
        q = q.or('description.ilike.%$search%,merchant.ilike.%$search%');
      }
      final rows = await q
          .order('effective_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Map<String, dynamic>> createTransaction({
    required String type, // expense | income | transfer | adjustment
    required int amountMinor,
    required String currency,
    required String accountId,
    String? destinationAccountId,
    String? categoryId,
    required DateTime effectiveAtUtc,
    String? merchant,
    String? description,
    List<String> tags = const [],
    String status = 'posted',
    String? idempotencyKey,
    List<Map<String, dynamic>> splits = const [],
  }) async {
    if (amountMinor <= 0) {
      throw SupabaseFailure('Nominal harus lebih dari 0.');
    }
    if (type == 'transfer' &&
        (destinationAccountId == null || destinationAccountId == accountId)) {
      throw SupabaseFailure(
          'Transfer memerlukan akun tujuan yang berbeda dari akun asal.');
    }
    if (type != 'transfer' && categoryId == null) {
      throw SupabaseFailure('Kategori wajib diisi kecuali untuk transfer.');
    }
    if (splits.isNotEmpty &&
        !Money.splitsSumToParent(
            splits.map((s) => s['amount'] as int).toList(), amountMinor)) {
      throw SupabaseFailure('Total split harus sama dengan nominal transaksi.');
    }
    final key = idempotencyKey ?? newIdempotencyKey();
    try {
      final inserted = await _client.table('transactions').insert({
        'user_id': _userId,
        'type': type,
        'status': status,
        'account_id': accountId,
        'destination_account_id': destinationAccountId,
        'category_id': categoryId,
        'effective_at': effectiveAtUtc.toIso8601String(),
        'amount': amountMinor,
        'currency': currency,
        'merchant': merchant,
        'description': description,
        'tags': tags,
        'idempotency_key': key,
      }).select().single();
      if (splits.isNotEmpty) {
        await _client.table('transaction_splits').insert(splits
            .map((s) => {
                  'transaction_id': inserted['id'],
                  'category_id': s['category_id'],
                  'amount': s['amount'],
                })
            .toList());
      }
      return Map<String, dynamic>.from(inserted);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> updateTransaction(String id, Map<String, dynamic> patch,
      {int? expectedVersion}) async {
    try {
      var q = _client.table('transactions').update(patch).eq('id', id);
      if (expectedVersion != null) {
        q = q.eq('row_version', expectedVersion);
      }
      await q;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<Map<String, dynamic>> duplicateTransaction(
      Map<String, dynamic> original) async {
    return createTransaction(
      type: original['type'] as String,
      amountMinor: original['amount'] as int,
      currency: (original['currency'] as String?) ?? 'IDR',
      accountId: original['account_id'] as String,
      destinationAccountId: original['destination_account_id'] as String?,
      categoryId: original['category_id'] as String?,
      effectiveAtUtc: DateTime.parse(original['effective_at'] as String),
      merchant: original['merchant'] as String?,
      description: original['description'] as String?,
      status: 'draft',
    );
  }

  /// Reverse: creates a linked reversal transaction (PRD §5.3).
  Future<Map<String, dynamic>> reverseTransaction(
      Map<String, dynamic> original, String reason) async {
    final reversed = await createTransaction(
      type: original['type'] as String,
      amountMinor: original['amount'] as int,
      currency: (original['currency'] as String?) ?? 'IDR',
      accountId: original['account_id'] as String,
      destinationAccountId: original['destination_account_id'] as String?,
      categoryId: original['category_id'] as String?,
      effectiveAtUtc: DateTime.now().toUtc(),
      merchant: original['merchant'] as String?,
      description: 'Reversal: ${original['description'] ?? ''} — $reason',
      status: 'posted',
    );
    await updateTransaction(
        original['id'] as String, {'status': 'voided'});
    return reversed;
  }

  /// Soft delete (deleted_at), never hard delete (PRD §9.4).
  Future<void> softDeleteTransaction(String id) async {
    await updateTransaction(id, {'deleted_at': DateTime.now().toUtc().toIso8601String()});
  }

  /// Totals for a period, computed from posted transactions + opening
  /// balances. The authoritative balance comes from the journal ledger
  /// (PRD §9.3); until a balance view/function exists, this client-side
  /// computation is labelled as such in the UI.
  Future<({int income, int expense, int net})> periodTotals(
      PeriodRange period) async {
    final rows = await listTransactions(period: period, limit: 1000);
    var income = 0;
    var expense = 0;
    for (final r in rows) {
      if (r['status'] != 'posted') continue;
      final amount = (r['amount'] as num?)?.toInt() ?? 0;
      switch (r['type']) {
        case 'income':
          income += amount;
        case 'expense':
          expense += amount;
      }
      // transfer / adjustment do not affect income/expense (PRD §5.2).
    }
    return (income: income, expense: expense, net: income - expense);
  }

  // -------------------------------------------------------------- categories
  Future<List<Map<String, dynamic>>> listCategories() async {
    try {
      final rows = await _client
          .table('categories')
          .select()
          .or('user_id.eq.$_userId,user_id.is.null')
          .order('order');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> createCategory({
    required String name,
    required String type, // income | expense
    String? parentId,
    String color = '#7B9BC0',
    String icon = 'category',
  }) async {
    try {
      await _client.table('categories').insert({
        'user_id': _userId,
        'type': type,
        'parent_id': parentId,
        'name': name,
        'color': color,
        'icon': icon,
        'archived': false,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Seed the system categories (user_id null) on first run — PRD §5.4.
  static const List<Map<String, String>> systemCategories = [
    {'name': 'Gaji/Bonus', 'type': 'income'},
    {'name': 'Freelance', 'type': 'income'},
    {'name': 'Bisnis', 'type': 'income'},
    {'name': 'Hadiah', 'type': 'income'},
    {'name': 'Refund/Lainnya', 'type': 'income'},
    {'name': 'Makanan & Minuman', 'type': 'expense'},
    {'name': 'Belanja Harian', 'type': 'expense'},
    {'name': 'Transportasi', 'type': 'expense'},
    {'name': 'Perumahan', 'type': 'expense'},
    {'name': 'Utilitas', 'type': 'expense'},
    {'name': 'Belanja', 'type': 'expense'},
    {'name': 'Kesehatan', 'type': 'expense'},
    {'name': 'Keluarga & Pendidikan', 'type': 'expense'},
    {'name': 'Hiburan', 'type': 'expense'},
    {'name': 'Langganan', 'type': 'expense'},
    {'name': 'Biaya Admin', 'type': 'expense'},
    {'name': 'Lainnya', 'type': 'expense'},
  ];

  // --------------------------------------------------------------- templates
  Future<List<Map<String, dynamic>>> listTemplates() async {
    try {
      final rows = await _client
          .table('transaction_templates')
          .select()
          .eq('user_id', _userId)
          .order('sort_order');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> createTemplate({
    required String name,
    required Map<String, dynamic> payload,
    bool favourite = false,
  }) async {
    try {
      await _client.table('transaction_templates').insert({
        'user_id': _userId,
        'name': name,
        'payload_json': payload,
        'favourite': favourite,
        'sort_order': 0,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> deleteTemplate(String id) async {
    try {
      await _client.table('transaction_templates').delete().eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ----------------------------------------------------------------- budgets
  Future<List<Map<String, dynamic>>> listBudgets() async {
    try {
      final rows = await _client
          .table('budgets')
          .select()
          .eq('user_id', _userId)
          .order('name');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> createBudget({
    required String name,
    String? categoryId,
    required int amountMinor,
    String currency = 'IDR',
    String cadence = 'monthly',
  }) async {
    try {
      await _client.table('budgets').insert({
        'user_id': _userId,
        'name': name,
        'category_id': categoryId,
        'amount': amountMinor,
        'currency': currency,
        'cadence': cadence,
        'rollover': false,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Actual expense for one category in a period (posted only).
  Future<int> categoryActual(String categoryId, PeriodRange period) async {
    final rows = await listTransactions(
        period: period, categoryId: categoryId, type: 'expense', limit: 1000);
    var total = 0;
    for (final r in rows) {
      if (r['status'] == 'posted') {
        total += (r['amount'] as num?)?.toInt() ?? 0;
      }
    }
    return total;
  }

  // ------------------------------------------------------- savings / debts
  Future<List<Map<String, dynamic>>> listSavingsGoals() async {
    try {
      final rows = await _client
          .table('savings_goals')
          .select()
          .eq('user_id', _userId)
          .order('target_date');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> createSavingsGoal({
    required String name,
    required int targetMinor,
    DateTime? targetDate,
  }) async {
    try {
      await _client.table('savings_goals').insert({
        'user_id': _userId,
        'name': name,
        'target_amount': targetMinor,
        'target_date': targetDate?.toIso8601String(),
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> listDebts() async {
    try {
      final rows = await _client
          .table('debts')
          .select()
          .eq('user_id', _userId)
          .order('due');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> createDebt({
    required String name,
    required int principalMinor,
    DateTime? due,
    String kind = 'debt',
  }) async {
    try {
      await _client.table('debts').insert({
        'user_id': _userId,
        'name': name,
        'principal': principalMinor,
        'due': due?.toIso8601String(),
        'kind': kind,
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // --------------------------------------------------------------- recurring
  Future<List<Map<String, dynamic>>> listRecurringRules() async {
    try {
      final rows = await _client
          .table('recurring_rules')
          .select()
          .eq('user_id', _userId)
          .order('next_at');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> createRecurringRule({
    required String name,
    required String cadence,
    required Map<String, dynamic> payload,
    DateTime? nextAt,
  }) async {
    try {
      await _client.table('recurring_rules').insert({
        'user_id': _userId,
        'name': name,
        'cadence': cadence,
        'payload_json': payload,
        'mode': 'draft',
        'active': true,
        'next_at': nextAt?.toIso8601String(),
      });
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ------------------------------------------------------------------ agents
  Future<List<Map<String, dynamic>>> listAgentConnections() async {
    try {
      final rows = await _client
          .table('agent_connections')
          .select()
          .eq('user_id', _userId)
          .order('connected_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> listPendingActions() async {
    try {
      final rows = await _client
          .table('agent_pending_actions')
          .select()
          .eq('user_id', _userId)
          .eq('status', 'pending')
          .order('expires_at');
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> decidePendingAction(String id, bool approve) async {
    try {
      await _client.table('agent_pending_actions').update({
        'status': approve ? 'approved' : 'rejected',
      }).eq('id', id);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> listAgentAudit() async {
    try {
      final rows = await _client
          .table('agent_audit_logs')
          .select()
          .eq('user_id', _userId)
          .order('occurred_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  // ------------------------------------------------------------------- admin
  // NOTE (PRD §7): admin mutations require a service-role backend /
  // Edge Function. The anon client cannot perform them; these methods call
  // the tables and surface the server error honestly until that backend
  // exists. Never embed a service-role key in the app.
  Future<List<Map<String, dynamic>>> adminListUsers({String search = ''}) async {
    try {
      var q = _client.table('profiles').select();
      if (search.isNotEmpty) {
        q = q.ilike('username_normalized', '%${search.toLowerCase()}%');
      }
      final rows = await q
          .order('created_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> adminListRoles() async {
    try {
      final rows =
          await _client.table('user_roles').select().limit(500);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<List<Map<String, dynamic>>> adminListAudit() async {
    try {
      final rows = await _client
          .table('admin_audit_logs')
          .select()
          .order('timestamp', ascending: false)
          .limit(200);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  Future<void> _adminAudit({
    required String targetUserId,
    required String action,
    required String reason,
  }) async {
    await _client.table('admin_audit_logs').insert({
      'admin_user_id': _userId,
      'target_user_id': targetUserId,
      'action': action,
      'reason': reason,
      'result': 'ok',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> adminSetStatus(
      String targetUserId, String status, String reason) async {
    try {
      await _client
          .table('profiles')
          .update({'status': status})
          .eq('user_id', targetUserId);
      await _adminAudit(
          targetUserId: targetUserId,
          action: status == 'suspended' ? 'suspend' : 'reactivate',
          reason: reason);
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }

  /// Change role, protecting the last admin (PRD §7.2).
  Future<void> adminChangeRole(
      String targetUserId, String newRole, String reason) async {
    try {
      if (newRole != 'admin') {
        final admins = await _client
            .table('user_roles')
            .select('user_id')
            .eq('role', 'admin');
        final adminIds =
            admins.map((r) => r['user_id'] as String).toList();
        if (adminIds.length <= 1 && adminIds.contains(targetUserId)) {
          throw SupabaseFailure(
              'Tidak dapat menghapus admin terakhir. Tetapkan admin lain dulu.');
        }
      }
      await _client.table('user_roles').upsert({
        'user_id': targetUserId,
        'role': newRole,
        'created_by': _userId,
      });
      await _adminAudit(
          targetUserId: targetUserId,
          action: 'change_role:$newRole',
          reason: reason);
    } on SupabaseFailure {
      rethrow;
    } catch (e) {
      throw mapSupabaseError(e);
    }
  }
}
