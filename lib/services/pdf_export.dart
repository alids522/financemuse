import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../utils/money_period.dart';

/// PDF export (PRD §5.13): human-readable report with title, period,
/// summary, category breakdown, transactions table, budget-vs-actual and
/// forecast assumptions, and generated date.
class PdfExport {
  PdfExport._();

  static Future<Uint8List> buildReport({
    required String title,
    required String periodLabel,
    required int incomeMinor,
    required int expenseMinor,
    required List<Map<String, dynamic>> transactions,
    List<Map<String, dynamic>> budgetRows = const [],
    List<String> forecastAssumptions = const [],
  }) async {
    final doc = pw.Document();
    final now = JakartaTime.now();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('Periode: $periodLabel',
              style: const pw.TextStyle(fontSize: 12)),
          pw.Text(
              'Dibuat: ${now.day}/${now.month}/${now.year} '
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} WIB',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 12),
          pw.Text('Ringkasan',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Pemasukan: ${Money.formatIdr(incomeMinor)}'),
          pw.Text('Pengeluaran: ${Money.formatIdr(expenseMinor)}'),
          pw.Text('Net: ${Money.formatIdr(incomeMinor - expenseMinor)}'),
          pw.SizedBox(height: 12),
          if (budgetRows.isNotEmpty) ...[
            pw.Text('Budget vs Actual',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['Budget', 'Actual', 'Sisa'],
              data: budgetRows
                  .map((b) => [
                        b['name'] ?? '',
                        Money.formatIdr((b['actual'] as num?)?.toInt() ?? 0),
                        Money.formatIdr((b['remaining'] as num?)?.toInt() ?? 0),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 12),
          ],
          if (forecastAssumptions.isNotEmpty) ...[
            pw.Text('Asumsi Forecast',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ...forecastAssumptions.map((a) => pw.Text('• $a')),
            pw.SizedBox(height: 12),
          ],
          pw.Text('Transaksi',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.TableHelper.fromTextArray(
            headers: ['Tanggal', 'Deskripsi', 'Kategori', 'Nominal'],
            data: transactions
                .map((t) => [
                      (t['effective_at'] as String?)?.substring(0, 10) ?? '',
                      (t['description'] as String?) ??
                          (t['merchant'] as String?) ??
                          '',
                      (t['category_name'] as String?) ?? '',
                      Money.formatIdr((t['amount'] as num?)?.toInt() ?? 0),
                    ])
                .toList(),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
