import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../main.dart';

/// Expenses read back from a PDF report exported by PdfExportService.
class PdfImportResult {
  const PdfImportResult({
    required this.expenses,
    required this.currency,
    required this.fromBackupData,
  });

  /// Rows shaped for the local database:
  /// `name`, `amount` (IDR), `date` (yyyy-MM-dd), `category`, `type`.
  final List<Map<String, dynamic>> expenses;

  /// The display currency shown in the PDF header badge.
  final String currency;

  /// True when rows came from the backup payload embedded in the PDF
  /// (exact restore), false when they were recovered from the printed
  /// transactions table of older exports.
  final bool fromBackupData;
}

/// Reads expenses back from a PDF report exported by PdfExportService.
///
/// New exports embed the raw rows as a backup payload which is restored
/// exactly. Older exports are recovered from the printed transactions table.
class PdfImportService {
  static const String backupPayloadPrefix = 'expenseapp-backup-v1:';

  /// Legacy table geometry from the export's transactions table: the type
  /// column is 75pt wide and sits right before the date column (72pt wide).
  static const double _typeColumnWidth = 75;
  static const double _dateColumnWidth = 72;

  /// Words whose vertical centers are closer than this belong to one table row.
  static const double _rowTolerance = 6;

  /// A words-only-this-far below a transaction row is the wrapped remainder
  /// of its name.
  static const double _nameContinuationGap = 16;

  static const Map<String, int> _monthAbbreviations = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'mei': 5,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'agu': 8,
    'aug': 8,
    'sep': 9,
    'okt': 10,
    'oct': 10,
    'nov': 11,
    'des': 12,
    'dec': 12,
  };

  static const Set<String> _typeLabels = {
    'terencana',
    'tak terduga',
    'lainnya',
    '-',
  };

  /// Builds the backup payload that exported PDFs embed in their metadata.
  static String backupPayload(List<Map<String, dynamic>> expenses) {
    final rows = expenses
        .map((expense) => {
              'name': expense['name']?.toString() ?? '',
              'amount': expense['amount'] is int
                  ? expense['amount'] as int
                  : int.tryParse(expense['amount']?.toString() ?? '0') ?? 0,
              'date': expense['date']?.toString() ?? '',
              'category': expense['category']?.toString() ?? '',
              'type': expense['type']?.toString() ?? '',
            })
        .toList();
    final json = jsonEncode({
      'version': 1,
      'currency': appCurrency.value,
      'expenses': rows,
    });
    return '$backupPayloadPrefix${base64Encode(utf8.encode(json))}';
  }

  static Future<PdfImportResult> parse(
    Uint8List bytes, {
    Future<double?> Function(String currency)? exchangeRateFor,
    bool ignoreBackupPayload = false,
  }) async {
    final document = PdfDocument(inputBytes: bytes);
    try {
      if (!ignoreBackupPayload) {
        final keywords = document.documentInformation.keywords;
        if (keywords.startsWith(backupPayloadPrefix)) {
          return _parseBackupPayload(keywords);
        }
      }
      return await _parsePrintedTable(document, exchangeRateFor);
    } finally {
      document.dispose();
    }
  }

  static PdfImportResult _parseBackupPayload(String keywords) {
    final encoded = keywords.substring(backupPayloadPrefix.length).trim();
    final decoded =
        jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
    final rows = decoded['expenses'] as List? ?? const [];
    final expenses = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row is! Map) continue;
      expenses.add({
        'name': row['name']?.toString().trim().isNotEmpty == true
            ? row['name'].toString().trim()
            : 'Pengeluaran',
        'amount': row['amount'] is num
            ? (row['amount'] as num).toInt()
            : int.tryParse(row['amount']?.toString() ?? '') ?? 0,
        'date': _normalizeDate(row['date']?.toString() ?? ''),
        'category': _normalizeCategory(row['category']?.toString() ?? ''),
        'type': _normalizeType(row['type']?.toString() ?? ''),
      });
    }
    return PdfImportResult(
      expenses: expenses,
      currency: decoded['currency']?.toString() ?? 'IDR',
      fromBackupData: true,
    );
  }

  static Future<PdfImportResult> _parsePrintedTable(
    PdfDocument document,
    Future<double?> Function(String currency)? exchangeRateFor,
  ) async {
    final extractor = PdfTextExtractor(document);
    final clusters = <_RowCluster>[];
    for (var page = 0; page < document.pages.count; page++) {
      final lines = extractor.extractTextLines(
        startPageIndex: page,
        endPageIndex: page,
      );
      final words = <_Word>[];
      for (final line in lines) {
        for (final word in line.wordCollection) {
          if (word.text.trim().isEmpty) continue;
          words.add(_Word(word.text, word.bounds));
        }
      }
      clusters.addAll(_clusterRows(words, page));
    }

    double? categoryX;
    double? dateX;
    var currency = 'IDR';
    for (final cluster in clusters) {
      final upper = cluster.words.map((word) => word.text.toUpperCase());
      if (upper.contains('KATEGORI') && upper.contains('TANGGAL')) {
        for (final word in cluster.words) {
          final text = word.text.toUpperCase();
          if (text == 'KATEGORI') categoryX = word.bounds.left;
          if (text == 'TANGGAL') dateX = word.bounds.left;
        }
      }
      if (upper.contains('EXPENSE') && upper.contains('REPORT')) {
        for (final word in cluster.words) {
          final text = word.text.toUpperCase();
          if (text == 'IDR' || text == 'USD' || text == 'EUR') currency = text;
        }
      }
    }
    if (categoryX == null || dateX == null) {
      throw const FormatException(
        'This PDF does not contain an expense report exported by this app.',
      );
    }

    double? idrRate;
    if (currency != 'IDR') {
      idrRate = await exchangeRateFor?.call(currency) ??
          (appCurrency.value == currency ? appExchangeRate.value : null);
      if (idrRate == null || idrRate <= 0) {
        throw StateError(
          'No exchange rate for $currency. Switch the app currency to '
          '$currency once, then import again.',
        );
      }
    }

    final expenses = <Map<String, dynamic>>[];
    _RowCluster? currentRow;
    for (final cluster in clusters) {
      final cells = _cellsFor(cluster, categoryX, dateX);
      final date = _parseDisplayDate(cells.date);
      final amount = _parseDisplayAmount(cells.amount, currency);
      if (date != null &&
          amount != null &&
          _typeLabels.contains(cells.type.trim().toLowerCase())) {
        final amountIdr =
            currency == 'IDR' ? amount.round() : (amount / idrRate!).round();
        final row = {
          'name': cells.name.trim().isEmpty
              ? 'Pengeluaran'
              : cells.name.trim(),
          'amount': amountIdr,
          'date': date,
          'category': _normalizeCategory(cells.category),
          'type': _normalizeType(cells.type),
        };
        expenses.add(row);
        currentRow = cluster;
      } else if (currentRow != null &&
          cluster.page == currentRow.page &&
          cells.isNameOnly &&
          cluster.centerY > currentRow.centerY &&
          cluster.centerY - currentRow.centerY <= _nameContinuationGap) {
        final row = expenses.last;
        row['name'] = '${row['name']} ${cells.name}'.trim();
      } else {
        currentRow = null;
      }
    }

    return PdfImportResult(
      expenses: expenses,
      currency: currency,
      fromBackupData: false,
    );
  }

  static List<_RowCluster> _clusterRows(List<_Word> words, int page) {
    final sorted = [...words]
      ..sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
    final clusters = <_RowCluster>[];
    for (final word in sorted) {
      if (clusters.isNotEmpty &&
          word.bounds.center.dy - clusters.last.centerY <= _rowTolerance) {
        clusters.last.words.add(word);
      } else {
        clusters.add(_RowCluster(page, [word]));
      }
    }
    for (final cluster in clusters) {
      cluster.words.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
    }
    return clusters;
  }

  static _Cells _cellsFor(_RowCluster cluster, double categoryX, double dateX) {
    final name = <String>[];
    final category = <String>[];
    final type = <String>[];
    final date = <String>[];
    final amount = <String>[];
    for (final word in cluster.words) {
      final x = word.bounds.left;
      if (x < categoryX - 0.5) {
        name.add(word.text);
      } else if (x < dateX - _typeColumnWidth) {
        category.add(word.text);
      } else if (x < dateX) {
        type.add(word.text);
      } else if (x < dateX + _dateColumnWidth) {
        date.add(word.text);
      } else {
        amount.add(word.text);
      }
    }
    return _Cells(
      name: name.join(' '),
      category: category.join(' '),
      type: type.join(' '),
      date: date.join(' '),
      amount: amount.join(' '),
    );
  }

  /// Converts a displayed date like `05 Jan 2026` back to `yyyy-MM-dd`.
  static String? _parseDisplayDate(String raw) {
    final match =
        RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})$').firstMatch(raw.trim());
    if (match == null) return null;
    final month = _monthAbbreviations[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    final day = int.parse(match.group(1)!);
    if (day < 1 || day > 31) return null;
    return '${match.group(3)}-${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  /// Converts a formatted amount like `Rp1.234.567`, `$1,234.56` or
  /// `€1.234,56` back to its numeric value in display currency.
  static double? _parseDisplayAmount(String raw, String currency) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (currency == 'IDR') {
      final digits = text.replaceAll(RegExp('[^0-9]'), '');
      return digits.isEmpty ? null : double.tryParse(digits);
    }
    if (currency == 'EUR') {
      text = text.replaceAll('.', '').replaceAll(',', '.');
    } else {
      text = text.replaceAll(',', '');
    }
    text = text.replaceAll(RegExp('[^0-9.]'), '');
    return text.isEmpty ? null : double.tryParse(text);
  }

  static String _normalizeDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    return parsed != null ? parsed.toIso8601String().substring(0, 10) : raw.trim();
  }

  static String _normalizeCategory(String raw) {
    final category = raw.trim().toLowerCase();
    return category.isEmpty ? 'lainnya' : category;
  }

  static String _normalizeType(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'terencana':
      case 'expected':
        return 'expected';
      case 'tak terduga':
      case 'unexpected':
        return 'unexpected';
      default:
        return 'others';
    }
  }
}

class _Word {
  const _Word(this.text, this.bounds);

  final String text;
  final Rect bounds;
}

class _Cells {
  const _Cells({
    required this.name,
    required this.category,
    required this.type,
    required this.date,
    required this.amount,
  });

  final String name;
  final String category;
  final String type;
  final String date;
  final String amount;

  bool get isNameOnly =>
      name.trim().isNotEmpty &&
      category.trim().isEmpty &&
      type.trim().isEmpty &&
      date.trim().isEmpty &&
      amount.trim().isEmpty;
}

class _RowCluster {
  _RowCluster(this.page, this.words);

  final int page;
  final List<_Word> words;

  double get centerY {
    var total = 0.0;
    for (final word in words) {
      total += word.bounds.center.dy;
    }
    return total / words.length;
  }
}
