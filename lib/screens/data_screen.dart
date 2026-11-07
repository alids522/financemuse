import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/csv_service.dart';
import '../services/pdf_export.dart';
import '../services/save_bytes.dart';
import '../services/supabase_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/money_period.dart';

/// Import & Export (PRD §5.12, §5.13):
/// - CSV import/export with mapping preview + duplicate fingerprint.
/// - PDF export (pdf package).
/// - Digital PDF import: best-effort text extraction + mandatory review.
///   Scanned/OCR PDFs show an explicit unsupported message (P2).
class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool _busy = false;
  String? _status;
  List<Map<String, String>> _previewRows = [];
  List<String> _previewErrors = [];
  List<Map<String, dynamic>> _pdfRows = [];
  bool _pdfHasText = false;
  bool _pdfAttempted = false;

  Future<void> _exportCsv() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final rows = await AppState.instance.finance.listTransactions(
        period: AppState.instance.period,
        limit: 5000,
      );
      final csv = CsvService.exportRows(rows);
      final path = await saveBytes(
        utf8.encode(csv),
        'finance-tracker-export-${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      setState(() => _status = 'CSV diekspor (${rows.length} baris): $path');
    } on SupabaseFailure catch (e) {
      setState(() => _status = 'Gagal ekspor: ${e.message}');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final state = AppState.instance;
      final totals = await state.finance.periodTotals(state.period);
      final rows = await state.finance.listTransactions(
        period: state.period,
        limit: 5000,
      );
      final pdf = await PdfExport.buildReport(
        title: 'Finance Tracker — Laporan Transaksi',
        periodLabel: state.period.label,
        incomeMinor: totals.income,
        expenseMinor: totals.expense,
        transactions: rows,
      );
      final path = await saveBytes(
        pdf,
        'finance-tracker-laporan-${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      setState(() => _status = 'PDF diekspor (${rows.length} baris): $path');
    } on SupabaseFailure catch (e) {
      setState(() => _status = 'Gagal ekspor: ${e.message}');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _importCsv() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.first.bytes == null) return;
    final text = utf8.decode(picked.files.first.bytes!, allowMalformed: true);
    final parsed = CsvService.parse(text);
    setState(() {
      _previewRows = parsed.rows;
      _previewErrors = parsed.errors;
      _status = 'Preview CSV: ${parsed.rows.length} baris, '
          '${parsed.errors.length} error parse. Periksa mapping sebelum konfirmasi.';
    });
  }

  Future<void> _confirmCsvImport() async {
    if (_previewRows.isEmpty) {
      setState(() => _status = 'Tidak ada baris untuk diimpor.');
      return;
    }
    setState(() => _busy = true);
    var imported = 0;
    var skipped = 0;
    final seen = <String>{};
    try {
      final accounts = await AppState.instance.finance.listAccounts();
      final accountId = accounts.isEmpty ? null : accounts.first['id'] as String;
      if (accountId == null) {
        setState(() => _status = 'Buat akun dulu sebelum mengimpor.');
        return;
      }
      final categories = await AppState.instance.finance.listCategories();
      final expenseCat = categories
          .where((c) => c['type'] == 'expense')
          .map((c) => c['id'] as String)
          .toList();
      final catId = expenseCat.isEmpty ? null : expenseCat.first;
      for (final row in _previewRows) {
        final amount = Money.parse(row['amount'] ?? '');
        final dateText = row['date_time'] ?? '';
        if (amount == null || dateText.isEmpty) {
          skipped++;
          continue;
        }
        final fp = CsvService.fingerprint(
          account: row['account'] ?? '',
          date: dateText,
          amountMinor: amount,
          description: row['description'] ?? '',
          sourceRef: row['source_ref'],
        );
        if (seen.contains(fp)) {
          skipped++;
          continue; // duplicate fingerprint — skip, never silent-merge
        }
        seen.add(fp);
        final type = (row['type'] ?? 'expense').toLowerCase();
        DateTime effective;
        try {
          effective = DateTime.parse(dateText).toUtc();
        } catch (_) {
          skipped++;
          continue;
        }
        await AppState.instance.finance.createTransaction(
          type: type == 'income' ? 'income' : 'expense',
          amountMinor: amount,
          currency: (row['currency'] ?? 'IDR').toUpperCase(),
          accountId: accountId,
          categoryId: catId,
          effectiveAtUtc: effective,
          merchant: row['merchant'],
          description: row['description'],
          status: 'posted',
        );
        imported++;
      }
      setState(() {
        _status = 'Impor selesai: $imported diimpor, $skipped dilewati '
            '(duplikat / tidak valid).';
        _previewRows = [];
      });
    } on SupabaseFailure catch (e) {
      setState(() => _status = 'Impor gagal: ${e.message}');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _importPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.first.bytes == null) return;
    final result = PdfImport.extractRows(picked.files.first.bytes!);
    setState(() {
      _pdfRows = result.rows;
      _pdfHasText = result.hasText;
      _pdfAttempted = true;
      _status = result.hasText
          ? 'PDF digital: ${result.rows.length} baris kandidat diekstrak. '
              'Semua baris berstatus needs_review — verifikasi sebelum impor.'
          : 'PDF ini tidak mengandung teks yang dapat diekstrak (kemungkinan hasil scan). '
              'Impor PDF hasil scan memerlukan OCR — fitur P2, belum didukung.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Import & Export',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Ekspor mengikuti filter aktif: ${AppState.instance.period.label}. '
            'Impor selalu melewati preview + mapping + deteksi duplikat.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s16),
          if (_status != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Text(_status!),
              ),
            ),
          const SizedBox(height: AppSpacing.s16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Export',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: AppSpacing.s8,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Export CSV'),
                        onPressed: _busy ? null : _exportCsv,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export PDF'),
                        onPressed: _busy ? null : _exportPdf,
                      ),
                    ],
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
                  const Text('Import CSV',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.s8),
                  const Text(
                    'Format: transaction_id, date_time, type, amount, '
                    'currency, account, destination_account, category, '
                    'subcategory, merchant, description, tags, status, source_ref.',
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: AppSpacing.s8,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.upload_outlined),
                        label: const Text('Pilih File CSV'),
                        onPressed: _busy ? null : _importCsv,
                      ),
                      if (_previewRows.isNotEmpty)
                        OutlinedButton(
                          onPressed: _busy ? null : _confirmCsvImport,
                          child: Text(
                              'Konfirmasi Impor (${_previewRows.length} baris)'),
                        ),
                    ],
                  ),
                  if (_previewErrors.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Error parse: ${_previewErrors.take(5).join('; ')}',
                      style: TextStyle(color: context.finance.negative),
                    ),
                  ],
                  if (_previewRows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s8),
                    const Text('Preview (10 baris pertama):',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    for (final r in _previewRows.take(10))
                      Text(
                          '${r['date_time'] ?? ''} • ${r['description'] ?? ''} • ${r['amount'] ?? ''}'),
                  ],
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
                  const Text('Import PDF Digital',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.s8),
                  const Text(
                    'PDF laporan/rekening koran digital yang teksnya dapat '
                    'diekstrak. Baris ambigu berstatus needs_review dan '
                    'tidak diimpor diam-diam.',
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('Pilih File PDF'),
                    onPressed: _busy ? null : _importPdf,
                  ),
                  if (_pdfAttempted && !_pdfHasText) ...[
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'PDF hasil scan tidak didukung di P0 (OCR adalah fitur P2).',
                      style: TextStyle(color: context.finance.warning),
                    ),
                  ],
                  if (_pdfRows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s8),
                    const Text(
                      'Baris kandidat (needs_review — belum diimpor):',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final r in _pdfRows.take(10))
                      Text(
                          '${r['date']} • ${Money.formatIdr((r['amount'] as num?)?.toInt() ?? 0)} • ${r['description']}'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
