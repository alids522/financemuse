import 'dart:convert';

import 'package:csv/csv.dart';

/// CSV import/export (PRD §5.12, §5.13).
/// Canonical header (PRD §5.12):
/// transaction_id, date_time, type, amount, currency, account,
/// destination_account, category, subcategory, merchant, description,
/// tags, status, source_ref
class CsvService {
  CsvService._();

  static const List<String> headers = [
    'transaction_id',
    'date_time',
    'type',
    'amount',
    'currency',
    'account',
    'destination_account',
    'category',
    'subcategory',
    'merchant',
    'description',
    'tags',
    'status',
    'source_ref',
  ];

  static String exportRows(List<Map<String, dynamic>> rows) {
    final data = <List<dynamic>>[
      headers,
      ...rows.map((r) => headers.map((h) => r[h] ?? '').toList()),
    ];
    return const ListToCsvConverter().convert(data);
  }

  /// Parse CSV text into row maps keyed by the canonical headers.
  /// Returns rows plus per-row parse errors (never silently drops rows).
  static ({List<Map<String, String>> rows, List<String> errors}) parse(
      String csvText) {
    final errors = <String>[];
    final raw = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(csvText.trim());
    if (raw.isEmpty) return (rows: [], errors: ['File CSV kosong.']);
    final header = raw.first.map((c) => c.toString().trim()).toList();
    final out = <Map<String, String>>[];
    for (var i = 1; i < raw.length; i++) {
      final cells = raw[i];
      if (cells.length < 3) {
        errors.add('Baris ${i + 1}: terlalu sedikit kolom.');
        continue;
      }
      final row = <String, String>{};
      for (var j = 0; j < header.length && j < cells.length; j++) {
        row[header[j]] = cells[j].toString();
      }
      out.add(row);
    }
    return (rows: out, errors: errors);
  }

  /// Duplicate fingerprint (PRD §5.12): account + date + amount +
  /// normalized description (+ source_ref when present).
  static String fingerprint({
    required String account,
    required String date,
    required int amountMinor,
    required String description,
    String? sourceRef,
  }) {
    final norm = description
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final base = '$account|$date|$amountMinor|$norm';
    return sourceRef == null || sourceRef.isEmpty
        ? base
        : '$base|$sourceRef';
  }
}

/// Minimal digital-PDF text extraction (PRD §5.12, P0).
/// Extracts literal strings from PDF content streams — good enough for
/// text-based statements. Scanned/image PDFs contain no extractable text
/// and are reported as unsupported (OCR is P2).
class PdfImport {
  PdfImport._();

  static ({List<Map<String, dynamic>> rows, bool hasText}) extractRows(
      List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    // Collect literal strings "(...)" from content streams.
    final buf = StringBuffer();
    final re = RegExp(r'\((?:[^()\\]|\\.)*\)');
    for (final m in re.allMatches(text)) {
      var s = m.group(0)!;
      s = s.substring(1, s.length - 1);
      s = s.replaceAll(r'\(', '(').replaceAll(r'\)', ')').replaceAll(r'\\', r'\');
      buf.write(s);
      buf.write(' ');
    }
    final flat = buf.toString();
    final hasText = flat.trim().length > 20;
    if (!hasText) return (rows: [], hasText: false);

    // Heuristic row parse: date (dd/mm/yyyy or yyyy-mm-dd) + amount.
    final rows = <Map<String, dynamic>>[];
    final lineRe = RegExp(
        r'(\d{2}[/-]\d{2}[/-]\d{4}|\d{4}-\d{2}-\d{2})[^0-9]{0,80}?([0-9][0-9.,]{2,})');
    for (final m in lineRe.allMatches(flat)) {
      final amountText = m.group(2)!.replaceAll(RegExp(r'[^0-9]'), '');
      final amount = int.tryParse(amountText);
      if (amount == null || amount <= 0) continue;
      rows.add({
        'date': m.group(1),
        'amount': amount,
        'description': 'Baris PDF (perlu review)',
        'confidence': 'low',
        'needs_review': true,
      });
    }
    return (rows: rows, hasText: true);
  }
}
