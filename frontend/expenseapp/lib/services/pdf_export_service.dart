import 'dart:io';
import 'dart:typed_data';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/error_log_service.dart';

class PdfExportService {
  static Future<void> exportExpenses({
    required BuildContext context,
    required List<Map<String, dynamic>> expenses,
  }) async {
    try {
      if (expenses.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('There are no expenses to export.')),
        );
        return;
      }

      final sortedExpenses = [...expenses]
        ..sort((first, second) {
          final firstDate = DateTime.tryParse(first['date']?.toString() ?? '');
          final secondDate = DateTime.tryParse(
            second['date']?.toString() ?? '',
          );
          if (firstDate == null && secondDate == null) return 0;
          if (firstDate == null) return 1;
          if (secondDate == null) return -1;
          return secondDate.compareTo(firstDate);
        });

      final formatter = NumberFormat.currency(
        locale: currencyLocale,
        symbol: currencySymbol,
        decimalDigits: currencyDecimalDigits,
      );

      // Aggregations for summary section
      double grandTotal = 0;
      final Map<String, double> categoryAmounts = {};
      final Map<String, int> categoryCounts = {};
      final Map<String, double> typeAmounts = {
        'expected': 0.0,
        'unexpected': 0.0,
        'others': 0.0,
      };
      final Map<String, int> typeCounts = {
        'expected': 0,
        'unexpected': 0,
        'others': 0,
      };

      Map<String, dynamic>? highestExpenseItem;
      double highestExpenseAmount = 0.0;

      for (final expense in sortedExpenses) {
        final amountIdr = expense['amount'] is int
            ? expense['amount'] as int
            : int.tryParse(expense['amount'].toString()) ?? 0;
        final amount = amountIdr * appExchangeRate.value;
        grandTotal += amount;

        if (amount > highestExpenseAmount) {
          highestExpenseAmount = amount;
          highestExpenseItem = expense;
        }

        final cat = (expense['category']?.toString() ?? 'lainnya')
            .trim()
            .toLowerCase();
        categoryAmounts[cat] = (categoryAmounts[cat] ?? 0.0) + amount;
        categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;

        final t = (expense['type']?.toString() ?? 'others')
            .trim()
            .toLowerCase();
        final key = typeAmounts.containsKey(t) ? t : 'others';
        typeAmounts[key] = typeAmounts[key]! + amount;
        typeCounts[key] = (typeCounts[key] ?? 0) + 1;
      }

      final sortedCategories = categoryAmounts.keys.toList()
        ..sort((a, b) => categoryAmounts[b]!.compareTo(categoryAmounts[a]!));

      final avgExpense = sortedExpenses.isNotEmpty
          ? grandTotal / sortedExpenses.length
          : 0.0;
      final expectedPct = grandTotal > 0
          ? (typeAmounts['expected']! / grandTotal) * 100
          : 0.0;
      final unexpectedPct = grandTotal > 0
          ? (typeAmounts['unexpected']! / grandTotal) * 100
          : 0.0;
      final othersPct = grandTotal > 0
          ? (typeAmounts['others']! / grandTotal) * 100
          : 0.0;
      final isHighUnexpected = unexpectedPct > 35;

      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          build: (context) => [
            _buildPage1Header(),
            pw.SizedBox(height: 6),
            _buildPage1Metadata(),
            pw.SizedBox(height: 14),
            _buildTransactionsTable(sortedExpenses, formatter),
            pw.SizedBox(height: 10),
            _buildTotalBox(grandTotal, formatter),
          ],
        ),
      );

      // PAGE 2: EXPENSE SUMMARY & ANALYTICS
      document.addPage(
        pw.MultiPage(
          build: (context) => [
            _buildPage2Header(),
            pw.SizedBox(height: 6),
            _buildPage2Metadata(),
            pw.SizedBox(height: 14),
            _buildKpiBoxes(grandTotal, avgExpense, highestExpenseAmount,
                highestExpenseItem, sortedExpenses.length, sortedCategories.length, formatter),
            pw.SizedBox(height: 14),
            _buildCategoryBreakdown(
                grandTotal, categoryAmounts, categoryCounts, sortedCategories, formatter),
            pw.SizedBox(height: 14),
            _buildTypeBreakdown(
                expectedPct, unexpectedPct, othersPct, typeAmounts, typeCounts,
                isHighUnexpected, formatter),
          ],
        ),
      );

      await _saveAndOpenPdf(context, document);
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Export expense report');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not export PDF: $error')));
    }
  }

  // --- PAGE 1 BUILDERS ---

  static pw.Widget _buildPage1Header() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: pdf.PdfColor.fromInt(0xFF5DF9FF),
        border: pw.Border.all(color: pdf.PdfColors.black, width: 2),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'EXPENSE REPORT',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(
              color: pdf.PdfColor.fromInt(0xFFF9EB5D),
              border: pw.Border.all(color: pdf.PdfColors.black, width: 1.2),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              appCurrency.value,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPage1Metadata() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Account: ${AuthService.currentUser?.email ?? 'Unknown'}',
          style: const pw.TextStyle(fontSize: 9, color: pdf.PdfColors.grey700),
        ),
        pw.Text(
          'Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: pdf.PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _buildTransactionsTable(
      List<Map<String, dynamic>> sortedExpenses, NumberFormat formatter) {
    return pw.Table(
      border: pw.TableBorder(
        top: const pw.BorderSide(color: pdf.PdfColors.black, width: 1.5),
        bottom: const pw.BorderSide(color: pdf.PdfColors.black, width: 1.5),
        left: const pw.BorderSide(color: pdf.PdfColors.black, width: 1.5),
        right: const pw.BorderSide(color: pdf.PdfColors.black, width: 1.5),
        horizontalInside: const pw.BorderSide(
            color: pdf.PdfColor.fromInt(0xFFE5E7EB), width: 0.8),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.0),
        1: pw.FixedColumnWidth(95),
        2: pw.FixedColumnWidth(75),
        3: pw.FixedColumnWidth(72),
        4: pw.FixedColumnWidth(85),
      },
      children: [
        _buildTableHeaderRow(),
        ...sortedExpenses.asMap().entries.map((entry) {
          final index = entry.key;
          final expense = entry.value;
          return _buildTransactionRow(index, expense, formatter);
        }),
      ],
    );
  }

  static pw.TableRow _buildTableHeaderRow() {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(
        color: pdf.PdfColor.fromInt(0xFF5DF9FF),
        border: pw.Border(bottom: pw.BorderSide(color: pdf.PdfColors.black, width: 1.5)),
      ),
      children: [
        _buildHeaderCell('NAMA TRANSAKSI'),
        _buildHeaderCell('KATEGORI'),
        _buildHeaderCell('TIPE', alignCenter: true),
        _buildHeaderCell('TANGGAL'),
        _buildHeaderCell('NOMINAL', alignRight: true),
      ],
    );
  }

  static pw.TableRow _buildTransactionRow(
      int index, Map<String, dynamic> expense, NumberFormat formatter) {
    final isEven = index % 2 == 0;
    final rowBg = isEven ? pdf.PdfColors.white : pdf.PdfColor.fromInt(0xFFF9FAFB);
    final amountIdr = expense['amount'] is int
        ? expense['amount'] as int
        : int.tryParse(expense['amount'].toString()) ?? 0;
    final amount = amountIdr * appExchangeRate.value;
    final type = expense['type']?.toString() ?? '';
    final name = expense['name']?.toString() ?? '';
    final category = expense['category']?.toString() ?? '';
    final rawDate = expense['date'];

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: rowBg),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            name.trim().isNotEmpty ? name : 'Pengeluaran',
            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                  color: _pdfCategoryColor(category),
                  borderRadius: pw.BorderRadius.circular(2),
                  border: pw.Border.all(color: pdf.PdfColors.black, width: 0.8),
                ),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: pw.Text(
                  _pdfCategoryLabel(category),
                  maxLines: 1,
                  style: const pw.TextStyle(fontSize: 8, color: pdf.PdfColors.grey800),
                ),
              ),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: pw.BoxDecoration(
                color: _pdfTypeColor(type),
                borderRadius: pw.BorderRadius.circular(3),
                border: pw.Border.all(color: pdf.PdfColors.black, width: 0.8),
              ),
              child: pw.Text(
                _pdfTypeLabel(type),
                style: pw.TextStyle(
                    fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            _formatPdfDate(rawDate),
            style: const pw.TextStyle(fontSize: 8, color: pdf.PdfColors.grey700),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              formatter.format(amount),
              style:
                  pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTotalBox(double grandTotal, NumberFormat formatter) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: pw.BoxDecoration(
          color: pdf.PdfColor.fromInt(0xFFF9EB5D),
          border: pw.Border.all(color: pdf.PdfColors.black, width: 1.6),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              'TOTAL PENGELUARAN: ',
              style: pw.TextStyle(
                  fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              formatter.format(grandTotal),
              style: pw.TextStyle(
                  fontSize: 12.5, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // --- PAGE 2 BUILDERS ---

  static pw.Widget _buildPage2Header() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: pdf.PdfColor.fromInt(0xFF5DF9FF),
        border: pw.Border.all(color: pdf.PdfColors.black, width: 2),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'EXPENSE SUMMARY & ANALYTICS',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(
              color: pdf.PdfColor.fromInt(0xFFF9EB5D),
              border: pw.Border.all(color: pdf.PdfColors.black, width: 1.2),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              appCurrency.value,
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPage2Metadata() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Account: ${AuthService.currentUser?.email ?? 'Unknown'}',
          style: const pw.TextStyle(fontSize: 9, color: pdf.PdfColors.grey700),
        ),
        pw.Text(
          'Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: pdf.PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _buildKpiBoxes(
      double grandTotal,
      double avgExpense,
      double highestExpenseAmount,
      Map<String, dynamic>? highestExpenseItem,
      int totalCount,
      int categoryCount,
      NumberFormat formatter) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _buildKpiBox(
            'TOTAL EXPENSES',
            formatter.format(grandTotal),
            '$totalCount Total Transaksi',
            pdf.PdfColor.fromInt(0xFFE8FDFF),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _buildKpiBox(
            'RATA-RATA / TRANSAKSI',
            formatter.format(avgExpense),
            '$categoryCount Kategori Aktif',
            pdf.PdfColor.fromInt(0xFFF9FBFD),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _buildKpiBox(
            'TRANSAKSI TERTINGGI',
            formatter.format(highestExpenseAmount),
            highestExpenseItem?['name']?.toString() ?? '-',
            pdf.PdfColor.fromInt(0xFFFFF9E6),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildKpiBox(
      String label, String value, String subtitle, pdf.PdfColor bgColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: bgColor,
        border: pw.Border.all(color: pdf.PdfColors.black, width: 1.2),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 7.5, color: pdf.PdfColors.grey700),
          ),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 7.5)),
        ],
      ),
    );
  }

  static pw.Widget _buildCategoryBreakdown(
      double grandTotal,
      Map<String, double> categoryAmounts,
      Map<String, int> categoryCounts,
      List<String> sortedCategories,
      NumberFormat formatter) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Distribusi Berdasarkan Kategori',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        if (sortedCategories.isNotEmpty)
          pw.Container(
            height: 12,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: pdf.PdfColors.black, width: 1.2),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Row(
              children: sortedCategories.map((cat) {
                final amount = categoryAmounts[cat] ?? 0.0;
                final pct = grandTotal > 0 ? (amount / grandTotal) * 100 : 0.0;
                final flex = (pct * 10).round().clamp(1, 1000);
                return pw.Flexible(
                  flex: flex,
                  child: pw.Container(color: _pdfCategoryColor(cat)),
                );
              }).toList(),
            ),
          ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: pdf.PdfColors.black, width: 0.8),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.2),
            1: pw.FixedColumnWidth(60),
            2: pw.FixedColumnWidth(70),
            3: pw.FixedColumnWidth(95),
          },
          children: [
            _buildCategoryHeaderRow(),
            ...sortedCategories.map((cat) {
              final amount = categoryAmounts[cat] ?? 0.0;
              final count = categoryCounts[cat] ?? 0;
              final pct = grandTotal > 0 ? (amount / grandTotal) * 100 : 0.0;
              return _buildCategoryRow(cat, count, pct, amount, formatter);
            }),
          ],
        ),
      ],
    );
  }

  static pw.TableRow _buildCategoryHeaderRow() {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: pdf.PdfColors.grey200),
      children: [
        _buildCell('Kategori', isHeader: true),
        _buildCell('Jumlah Item', isHeader: true, alignRight: true),
        _buildCell('Persentase', isHeader: true, alignRight: true),
        _buildCell('Total Nominal', isHeader: true, alignRight: true),
      ],
    );
  }

  static pw.TableRow _buildCategoryRow(String cat, int count, double pct,
      double amount, NumberFormat formatter) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Row(
            children: [
              pw.Container(
                width: 8,
                height: 8,
                decoration: pw.BoxDecoration(
                  color: _pdfCategoryColor(cat),
                  border: pw.Border.all(color: pdf.PdfColors.black, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Text(
                cat.toUpperCase(),
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text('$count item',
              style: const pw.TextStyle(fontSize: 8.5), textAlign: pw.TextAlign.right),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text('${pct.toStringAsFixed(1)}%',
              style: const pw.TextStyle(fontSize: 8.5), textAlign: pw.TextAlign.right),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(formatter.format(amount),
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.right),
        ),
      ],
    );
  }

  static pw.Widget _buildTypeBreakdown(
      double expectedPct,
      double unexpectedPct,
      double othersPct,
      Map<String, double> typeAmounts,
      Map<String, int> typeCounts,
      bool isHighUnexpected,
      NumberFormat formatter) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Distribusi Tipe Pengeluaran',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          children: [
            pw.Expanded(child: _buildTypeCard('TERENCANA', expectedPct, typeAmounts['expected']!, typeCounts['expected']!, pdf.PdfColor.fromInt(0xFFFFFDE7), pdf.PdfColor.fromInt(0xFFF9EB5D), formatter)),
            pw.SizedBox(width: 8),
            pw.Expanded(child: _buildTypeCard('TAK TERDUGA', unexpectedPct, typeAmounts['unexpected']!, typeCounts['unexpected']!, pdf.PdfColor.fromInt(0xFFFFEBEE), pdf.PdfColor.fromInt(0xFFFF5D5D), formatter)),
            pw.SizedBox(width: 8),
            pw.Expanded(child: _buildTypeCard('LAINNYA', othersPct, typeAmounts['others']!, typeCounts['others']!, pdf.PdfColor.fromInt(0xFFE3F2FD), pdf.PdfColor.fromInt(0xFF5D9BFF), formatter)),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Container(
          padding: const pw.EdgeInsets.all(7),
          decoration: pw.BoxDecoration(
            color: isHighUnexpected
                ? pdf.PdfColor.fromInt(0xFFFFEBEE)
                : pdf.PdfColor.fromInt(0xFFE8F5E9),
            border: pw.Border.all(
              color: isHighUnexpected
                  ? pdf.PdfColor.fromInt(0xFFFF5D5D)
                  : pdf.PdfColor.fromInt(0xFF06D6A0),
              width: 1.2,
            ),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            isHighUnexpected
                ? 'Evaluasi Finansial: Pengeluaran tak terduga mencapai ${unexpectedPct.toStringAsFixed(1)}%! Alokasikan dana darurat lebih ketat untuk menjaga stabilitas keuangan.'
                : 'Evaluasi Finansial: Rasio terencana sehat! Pengeluaran tak terduga terkendali di bawah 35% (${unexpectedPct.toStringAsFixed(1)}%).',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: isHighUnexpected
                  ? pdf.PdfColor.fromInt(0xFFB71C1C)
                  : pdf.PdfColor.fromInt(0xFF1B5E20),
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTypeCard(String label, double pct, double amount,
      int count, pdf.PdfColor bgColor, pdf.PdfColor dotColor,
      NumberFormat formatter) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        color: bgColor,
        border: pw.Border.all(color: pdf.PdfColors.black, width: 1.2),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                  color: dotColor,
                  border: pw.Border.all(color: pdf.PdfColors.black, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 4),
              pw.Text(label,
                  style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text('${pct.toStringAsFixed(1)}%',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Text(formatter.format(amount), style: const pw.TextStyle(fontSize: 7.5)),
          pw.Text('$count item',
              style: const pw.TextStyle(fontSize: 7, color: pdf.PdfColors.grey700)),
        ],
      ),
    );
  }

  // --- SAVE & OPEN ---

  static Future<void> _saveAndOpenPdf(
      BuildContext context, pw.Document document) async {
    final Uint8List bytes = await document.save();
    final fileName =
        'expense-report-${DateTime.now().millisecondsSinceEpoch}.pdf';
    String? path;
    String? androidContentUri;
    late final String fileToOpenPath;

    if (Platform.isAndroid) {
      MediaStore.appFolder = 'ExpenseApp';
      await MediaStore.ensureInitialized();
      final temporaryDirectory = await getTemporaryDirectory();
      final temporaryFile = File('${temporaryDirectory.path}/$fileName');
      await temporaryFile.writeAsBytes(bytes, flush: true);
      final savedFile = await MediaStore().saveFile(
        tempFilePath: temporaryFile.path,
        dirType: DirType.download,
        dirName: DirName.download,
      );
      path = savedFile?.uri.toString();
      androidContentUri = path;
      fileToOpenPath = temporaryFile.path;
    } else {
      path = await FileSaver.instance.saveFile(
        name: fileName,
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );
      fileToOpenPath = path;
    }

    var couldOpenFile = false;
    try {
      if (Platform.isAndroid && androidContentUri != null) {
        final intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: androidContentUri,
          type: 'application/pdf',
          flags: <int>[Flag.FLAG_GRANT_READ_URI_PERMISSION],
        );
        await intent.launch();
        couldOpenFile = true;
      } else {
        final openResult = await OpenFilex.open(
          fileToOpenPath,
          type: 'application/pdf',
        );
        couldOpenFile = openResult.type == ResultType.done;
      }
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Open exported expense report');
      couldOpenFile = false;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          couldOpenFile
              ? (path?.isEmpty != false
                  ? 'PDF exported to Downloads.'
                  : 'PDF exported: $path')
              : 'PDF exported. Open it from Downloads.',
        ),
      ),
    );
  }

  // --- HELPERS ---

  static pw.Widget _buildHeaderCell(String text,
      {bool alignRight = false, bool alignCenter = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Align(
        alignment: alignRight
            ? pw.Alignment.centerRight
            : (alignCenter ? pw.Alignment.center : pw.Alignment.centerLeft),
        child: pw.Text(
          text,
          style: pw.TextStyle(
              fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: pdf.PdfColors.black),
        ),
      ),
    );
  }

  static pw.Widget _buildCell(String text,
      {bool isHeader = false, bool alignRight = false, bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Align(
        alignment:
            alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: isHeader ? 9 : 8.5,
            fontWeight: isHeader || isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  static String _formatPdfDate(dynamic rawDate) {
    if (rawDate == null) return '-';
    final str = rawDate.toString();
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return DateFormat('dd MMM yyyy').format(parsed);
    }
    return str;
  }

  static String _pdfTypeLabel(String type) {
    switch (type.trim().toLowerCase()) {
      case 'expected':
        return 'Terencana';
      case 'unexpected':
        return 'Tak Terduga';
      case 'others':
        return 'Lainnya';
      default:
        return type.isEmpty ? '-' : type;
    }
  }

  static String _pdfCategoryLabel(String category) {
    final cat = category.trim();
    if (cat.isEmpty) return 'LAINNYA';
    return cat.toUpperCase();
  }

  static pdf.PdfColor _pdfTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'expected':
        return pdf.PdfColor.fromInt(0xFFF9EB5D);
      case 'unexpected':
        return pdf.PdfColor.fromInt(0xFFFF5D5D);
      case 'others':
        return pdf.PdfColor.fromInt(0xFF5D9BFF);
      default:
        return pdf.PdfColors.white;
    }
  }

  static pdf.PdfColor _pdfCategoryColor(String category) {
    switch (category.trim().toLowerCase()) {
      case 'makanan':
        return pdf.PdfColor.fromInt(0xFFFFD166);
      case 'school supply':
        return pdf.PdfColor.fromInt(0xFFC77DFF);
      case 'baju':
        return pdf.PdfColor.fromInt(0xFFFF99C8);
      case 'elektronik':
        return pdf.PdfColor.fromInt(0xFF70D6FF);
      case 'transportasi':
        return pdf.PdfColor.fromInt(0xFF06D6A0);
      case 'kesehatan':
        return pdf.PdfColor.fromInt(0xFFFF70A6);
      case 'hiburan':
        return pdf.PdfColor.fromInt(0xFFB5E48C);
      default:
        return pdf.PdfColor.fromInt(0xFF5DF9FF);
    }
  }
}

// Currency helpers - also used by hp2.dart
String get currencySymbol {
  switch (appCurrency.value) {
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    default:
      return 'Rp';
  }
}

String get currencyLocale {
  switch (appCurrency.value) {
    case 'USD':
      return 'en_US';
    case 'EUR':
      return 'de_DE';
    default:
      return 'id_ID';
  }
}

int get currencyDecimalDigits {
  switch (appCurrency.value) {
    case 'USD':
    case 'EUR':
      return 2;
    default:
      return 0;
  }
}
