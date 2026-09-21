import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import 'ExpenseAddPage.dart';
import 'package:intl/intl.dart';
import '../services/databaseHelper.dart';
import '../services/ApiService.dart';
import 'ExpenseEdit.dart';
import 'ExpenseSumarry.dart';
import '../services/auth_service.dart';
import '../services/notification_expense_service.dart';
import '../widgets/neo_animations.dart';
import 'notification_permission_page.dart';

// FIXME

/*
Database Logic

If Database Doesnt Exist
  Create Database
  Initialize Database

If Database Empty:
  Display "List Is Empty, create new Expense"
Else
  For Item in Database:
    var item = databaseItem[index]
    make cardlist of Ite

*/

class HomePage2 extends StatefulWidget {
  const HomePage2({super.key});

  @override
  State<HomePage2> createState() => _HomePage2State();
}

class _HomePage2State extends State<HomePage2> {
  final listKey = GlobalKey<_ListWithCardsState>();
  late final PageController _pageController;
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);
  int _selectedIndex = 0;
  int _homeTapCount = 0;
  bool _isChangingCurrency = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _restoreCurrencyPreference();
    _startNotificationParser();
    _checkFirstTimeNotificationPermission();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  Future<void> _startNotificationParser() async {
    final service = NotificationExpenseService.instance;
    if (!await service.isParserEnabled() || !await service.isEnabled()) return;
    await service.start(
      _showNotificationParserError,
      onExpenseAdded: () async {
        listKey.currentState?._loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense parsed from notification.')),
          );
        }
      },
    );
  }

  Future<void> _showNotificationParserError(String error) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not parse notification: $error')),
    );
  }

  Future<void> _checkFirstTimeNotificationPermission() async {
    final shown = await DatabaseHelp.getSetting(
      'notification_permission_onboarding_shown',
    );
    if (shown != null) return;

    // Mark as shown immediately so it is strictly shown only once after install
    await DatabaseHelp.setSetting(
      'notification_permission_onboarding_shown',
      'true',
    );

    final service = NotificationExpenseService.instance;
    final isAlreadyEnabled = await service.isEnabled();
    if (!isAlreadyEnabled && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(
            context,
          ).push(SmoothPageRoute(page: const NotificationPermissionPage()));
        }
      });
    }
  }

  Future<void> _restoreCurrencyPreference() async {
    try {
      final currency = await DatabaseHelp.getSetting('currency');
      if (currency == null || currency == 'IDR') return;
      final rate = await DatabaseHelp.getCachedExchangeRate(currency);
      if (rate == null || rate <= 0) return;
      appCurrency.value = currency;
      appExchangeRate.value = rate;
    } catch (_) {
      // Keep the default IDR display if the cache is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: _onPageChanged,
            children: [
              _buildExpensesPage(),
              ExpenseAddPage(
                embedded: true,
                onCancel: _goToHome,
                onSaved: _goToHome,
              ),
              _buildSettingsPage(),
            ],
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: bottomInset > 0 ? bottomInset + 6 : 16,
            child: ExpenseBottomBar(
              selectedIndex: _selectedIndex,
              onSelected: _onNavigationSelected,
            ),
          ),
          if (_isChangingCurrency) const _CurrencyLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildExpensesPage() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 12, 25, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Expenses',
                  style: GoogleFonts.itim(
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildSortDropdown(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification ||
                    notification is OverscrollNotification) {
                  final offset = notification.metrics.pixels;
                  if (_scrollOffset.value != offset) {
                    _scrollOffset.value = offset;
                  }
                }
                return false;
              },
              child: ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, child) {
                  final fadeProgress = (offset / 20.0).clamp(0.0, 1.0);

                  if (fadeProgress <= 0.001) {
                    return child!;
                  }

                  return ShaderMask(
                    shaderCallback: (Rect bounds) {
                      final fadeHeight = 28.0 * fadeProgress;
                      final stop = (fadeHeight / bounds.height).clamp(
                        0.005,
                        0.15,
                      );
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: const [Colors.transparent, Colors.black],
                        stops: [0.0, stop],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.dstIn,
                    child: child,
                  );
                },
                child: ListWithCards(key: listKey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPage() {
    return SettingsPage(
      onDeleteAll: _deleteAllExpenses,
      onExportPdf: _exportExpenses,
      onDeleteAccount: _deleteAccount,
      onChangePassword: _changePassword,
      onRetrySync: _retrySync,
      onCurrencyChanged: _changeCurrency,
      onLoadOnlineExpenses: _loadOnlineExpenses,
    );
  }

  void _onPageChanged(int index) {
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      _homeTapCount = index == 0 ? _homeTapCount + 1 : 0;
    });
  }

  Future<void> _goToHome() async {
    if (!mounted) return;
    listKey.currentState?._loadData();
    await _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildSortDropdown() {
    return NeoBouncy(
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF5DF9FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(3, 3), blurRadius: 0),
          ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            canvasColor: Theme.of(context).colorScheme.surfaceContainer,
            highlightColor: const Color(0x335DF9FF),
            splashColor: const Color(0x555DF9FF),
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.black,
              secondary: const Color(0xFF5DF9FF),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ExpenseSort>(
              value: listKey.currentState?._sort ?? ExpenseSort.dateNewest,
              isDense: true,
              dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(14),
              focusColor: Colors.transparent,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: Colors.black,
              ),
              items: const [
                DropdownMenuItem(
                  value: ExpenseSort.dateNewest,
                  child: Text('Newest'),
                ),
                DropdownMenuItem(
                  value: ExpenseSort.dateOldest,
                  child: Text('Oldest'),
                ),
                DropdownMenuItem(
                  value: ExpenseSort.amountHighest,
                  child: Text('Highest'),
                ),
                DropdownMenuItem(
                  value: ExpenseSort.amountLowest,
                  child: Text('Lowest'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  listKey.currentState?._setSort(value);
                  setState(() {});
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onNavigationSelected(int index) async {
    if (index == _selectedIndex) {
      if (index == 0) {
        _homeTapCount++;
        if (_homeTapCount == 10) {
          _homeTapCount = 0;
          await _showJumpscare();
        }
      }
      return;
    }

    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _deleteAllExpenses() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all expenses?'),
        content: const Text(
          'This will permanently delete every expense from this account. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    try {
      await DatabaseHelp.deleteAllForCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('All expenses deleted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete expenses: $error')),
      );
    }
  }

  Future<void> _exportExpenses() async {
    try {
      final expenses = await DatabaseHelp.getData();
      if (!mounted) return;
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
        locale: _currencyLocale,
        symbol: _currencySymbol,
        decimalDigits: _currencyDecimalDigits,
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
        typeAmounts[key] = (typeAmounts[key] ?? 0.0) + amount;
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
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
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
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: pw.BoxDecoration(
                      color: pdf.PdfColor.fromInt(0xFFF9EB5D),
                      border: pw.Border.all(
                        color: pdf.PdfColors.black,
                        width: 1.2,
                      ),
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
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Account: ${AuthService.currentUser?.email ?? 'Unknown'}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: pdf.PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  'Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: pdf.PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // Transactions Table
            pw.Table(
              border: pw.TableBorder(
                top: const pw.BorderSide(
                  color: pdf.PdfColors.black,
                  width: 1.5,
                ),
                bottom: const pw.BorderSide(
                  color: pdf.PdfColors.black,
                  width: 1.5,
                ),
                left: const pw.BorderSide(
                  color: pdf.PdfColors.black,
                  width: 1.5,
                ),
                right: const pw.BorderSide(
                  color: pdf.PdfColors.black,
                  width: 1.5,
                ),
                horizontalInside: const pw.BorderSide(
                  color: pdf.PdfColor.fromInt(0xFFE5E7EB),
                  width: 0.8,
                ),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.0),
                1: pw.FixedColumnWidth(95),
                2: pw.FixedColumnWidth(75),
                3: pw.FixedColumnWidth(72),
                4: pw.FixedColumnWidth(85),
              },
              children: [
                // Header Row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: pdf.PdfColor.fromInt(0xFF5DF9FF), // Neo Cyan Header
                    border: pw.Border(
                      bottom: pw.BorderSide(
                        color: pdf.PdfColors.black,
                        width: 1.5,
                      ),
                    ),
                  ),
                  children: [
                    _buildPdfTableHeaderCell('NAMA TRANSAKSI'),
                    _buildPdfTableHeaderCell('KATEGORI'),
                    _buildPdfTableHeaderCell('TIPE', alignCenter: true),
                    _buildPdfTableHeaderCell('TANGGAL'),
                    _buildPdfTableHeaderCell('NOMINAL', alignRight: true),
                  ],
                ),
                ...sortedExpenses.asMap().entries.map((entry) {
                  final index = entry.key;
                  final expense = entry.value;
                  final amountIdr = expense['amount'] is int
                      ? expense['amount'] as int
                      : int.tryParse(expense['amount'].toString()) ?? 0;
                  final amount = amountIdr * appExchangeRate.value;
                  final type = expense['type']?.toString() ?? '';
                  final name = expense['name']?.toString() ?? '';
                  final category = expense['category']?.toString() ?? '';
                  final rawDate = expense['date'];

                  return _buildPdfTransactionRow(
                    index: index,
                    name: name,
                    amount: formatter.format(amount),
                    category: category,
                    type: type,
                    date: rawDate,
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: pdf.PdfColors.black,
                      ),
                    ),
                    pw.Text(
                      formatter.format(grandTotal),
                      style: pw.TextStyle(
                        fontSize: 12.5,
                        fontWeight: pw.FontWeight.bold,
                        color: pdf.PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      // --- PAGE 2: EXPENSE SUMMARY & ANALYTICS ---
      document.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
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
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: pw.BoxDecoration(
                      color: pdf.PdfColor.fromInt(0xFFF9EB5D),
                      border: pw.Border.all(
                        color: pdf.PdfColors.black,
                        width: 1.2,
                      ),
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
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Account: ${AuthService.currentUser?.email ?? 'Unknown'}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: pdf.PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  'Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: pdf.PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // --- 3 KPI SUMMARY BOXES ---
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: pdf.PdfColor.fromInt(0xFFE8FDFF),
                      border: pw.Border.all(
                        color: pdf.PdfColors.black,
                        width: 1.2,
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'TOTAL EXPENSES',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: pdf.PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          formatter.format(grandTotal),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          '${sortedExpenses.length} Total Transaksi',
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: pdf.PdfColor.fromInt(0xFFF9FBFD),
                      border: pw.Border.all(
                        color: pdf.PdfColors.black,
                        width: 1.2,
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'RATA-RATA / TRANSAKSI',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: pdf.PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          formatter.format(avgExpense),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          '${sortedCategories.length} Kategori Aktif',
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: pdf.PdfColor.fromInt(0xFFFFF9E6),
                      border: pw.Border.all(
                        color: pdf.PdfColors.black,
                        width: 1.2,
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'TRANSAKSI TERTINGGI',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: pdf.PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          formatter.format(highestExpenseAmount),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          highestExpenseItem != null
                              ? (highestExpenseItem['name']?.toString() ?? '-')
                              : '-',
                          maxLines: 1,
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),

            // --- CATEGORY BREAKDOWN ---
            pw.Text(
              'Distribusi Berdasarkan Kategori',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),

            // Multi-segment category color bar
            if (sortedCategories.isNotEmpty) ...[
              pw.Container(
                height: 12,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: pdf.PdfColors.black, width: 1.2),
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Row(
                  children: sortedCategories.map((cat) {
                    final amount = categoryAmounts[cat] ?? 0.0;
                    final pct = grandTotal > 0
                        ? (amount / grandTotal) * 100
                        : 0.0;
                    final flex = (pct * 10).round().clamp(1, 1000);
                    return pw.Flexible(
                      flex: flex,
                      child: pw.Container(color: _pdfCategoryColor(cat)),
                    );
                  }).toList(),
                ),
              ),
              pw.SizedBox(height: 8),
            ],

            // Category Breakdown Table
            pw.Table(
              border: pw.TableBorder.all(
                color: pdf.PdfColors.black,
                width: 0.8,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.2),
                1: pw.FixedColumnWidth(60),
                2: pw.FixedColumnWidth(70),
                3: pw.FixedColumnWidth(95),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: pdf.PdfColors.grey200,
                  ),
                  children: [
                    _buildPdfCell('Kategori', isHeader: true),
                    _buildPdfCell(
                      'Jumlah Item',
                      isHeader: true,
                      alignRight: true,
                    ),
                    _buildPdfCell(
                      'Persentase',
                      isHeader: true,
                      alignRight: true,
                    ),
                    _buildPdfCell(
                      'Total Nominal',
                      isHeader: true,
                      alignRight: true,
                    ),
                  ],
                ),
                ...sortedCategories.map((cat) {
                  final amount = categoryAmounts[cat] ?? 0.0;
                  final count = categoryCounts[cat] ?? 0;
                  final pct = grandTotal > 0
                      ? (amount / grandTotal) * 100
                      : 0.0;
                  final color = _pdfCategoryColor(cat);

                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: pw.Row(
                          children: [
                            pw.Container(
                              width: 8,
                              height: 8,
                              decoration: pw.BoxDecoration(
                                color: color,
                                border: pw.Border.all(
                                  color: pdf.PdfColors.black,
                                  width: 0.8,
                                ),
                                borderRadius: pw.BorderRadius.circular(2),
                              ),
                            ),
                            pw.SizedBox(width: 5),
                            pw.Text(
                              cat.toUpperCase(),
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildPdfCell('$count item', alignRight: true),
                      _buildPdfCell(
                        '${pct.toStringAsFixed(1)}%',
                        alignRight: true,
                      ),
                      _buildPdfCell(
                        formatter.format(amount),
                        alignRight: true,
                        isBold: true,
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 14),

            // --- EXPENSE TYPE BREAKDOWN & FINANCIAL ADVICE (UNBREAKABLE BLOCK) ---
            pw.Container(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Distribusi Tipe Pengeluaran',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(7),
                          decoration: pw.BoxDecoration(
                            color: pdf.PdfColor.fromInt(0xFFFFFDE7),
                            border: pw.Border.all(
                              color: pdf.PdfColors.black,
                              width: 1.2,
                            ),
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
                                      color: pdf.PdfColor.fromInt(0xFFF9EB5D),
                                      border: pw.Border.all(
                                        color: pdf.PdfColors.black,
                                        width: 0.8,
                                      ),
                                      borderRadius: pw.BorderRadius.circular(2),
                                    ),
                                  ),
                                  pw.SizedBox(width: 4),
                                  pw.Text(
                                    'TERENCANA',
                                    style: pw.TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                '${expectedPct.toStringAsFixed(1)}%',
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                formatter.format(typeAmounts['expected']!),
                                style: const pw.TextStyle(fontSize: 7.5),
                              ),
                              pw.Text(
                                '${typeCounts['expected']} item',
                                style: const pw.TextStyle(
                                  fontSize: 7,
                                  color: pdf.PdfColors.grey700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(7),
                          decoration: pw.BoxDecoration(
                            color: pdf.PdfColor.fromInt(0xFFFFEBEE),
                            border: pw.Border.all(
                              color: pdf.PdfColors.black,
                              width: 1.2,
                            ),
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
                                      color: pdf.PdfColor.fromInt(0xFFFF5D5D),
                                      border: pw.Border.all(
                                        color: pdf.PdfColors.black,
                                        width: 0.8,
                                      ),
                                      borderRadius: pw.BorderRadius.circular(2),
                                    ),
                                  ),
                                  pw.SizedBox(width: 4),
                                  pw.Text(
                                    'TAK TERDUGA',
                                    style: pw.TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                '${unexpectedPct.toStringAsFixed(1)}%',
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                formatter.format(typeAmounts['unexpected']!),
                                style: const pw.TextStyle(fontSize: 7.5),
                              ),
                              pw.Text(
                                '${typeCounts['unexpected']} item',
                                style: const pw.TextStyle(
                                  fontSize: 7,
                                  color: pdf.PdfColors.grey700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(7),
                          decoration: pw.BoxDecoration(
                            color: pdf.PdfColor.fromInt(0xFFE3F2FD),
                            border: pw.Border.all(
                              color: pdf.PdfColors.black,
                              width: 1.2,
                            ),
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
                                      color: pdf.PdfColor.fromInt(0xFF5D9BFF),
                                      border: pw.Border.all(
                                        color: pdf.PdfColors.black,
                                        width: 0.8,
                                      ),
                                      borderRadius: pw.BorderRadius.circular(2),
                                    ),
                                  ),
                                  pw.SizedBox(width: 4),
                                  pw.Text(
                                    'LAINNYA',
                                    style: pw.TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              pw.SizedBox(height: 3),
                              pw.Text(
                                '${othersPct.toStringAsFixed(1)}%',
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                formatter.format(typeAmounts['others']!),
                                style: const pw.TextStyle(fontSize: 7.5),
                              ),
                              pw.Text(
                                '${typeCounts['others']} item',
                                style: const pw.TextStyle(
                                  fontSize: 7,
                                  color: pdf.PdfColors.grey700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
              ),
            ),
          ],
        ),
      );

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
      } catch (_) {
        couldOpenFile = false;
      }

      if (!mounted) return;
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not export PDF: $error')));
    }
  }

  pw.Widget _buildPdfTableHeaderCell(
    String text, {
    bool alignRight = false,
    bool alignCenter = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Align(
        alignment: alignRight
            ? pw.Alignment.centerRight
            : (alignCenter ? pw.Alignment.center : pw.Alignment.centerLeft),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: pdf.PdfColors.black,
          ),
        ),
      ),
    );
  }

  pw.TableRow _buildPdfTransactionRow({
    required int index,
    required String name,
    required String amount,
    required String category,
    required String type,
    required dynamic date,
  }) {
    final isEven = index % 2 == 0;
    final rowBg = isEven
        ? pdf.PdfColors.white
        : pdf.PdfColor.fromInt(0xFFF9FAFB);
    final typeColor = _pdfTypeColor(type);
    final catColor = _pdfCategoryColor(category);

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: rowBg),
      children: [
        // Name
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            name.trim().isNotEmpty ? name : 'Pengeluaran',
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: pdf.PdfColors.black,
            ),
          ),
        ),

        // Category with color dot
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(
                width: 7,
                height: 7,
                decoration: pw.BoxDecoration(
                  color: catColor,
                  borderRadius: pw.BorderRadius.circular(2),
                  border: pw.Border.all(color: pdf.PdfColors.black, width: 0.8),
                ),
              ),
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: pw.Text(
                  _pdfCategoryLabel(category),
                  maxLines: 1,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: pdf.PdfColors.grey800,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Type as Pill Badge with its respective color!
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 2,
              ),
              decoration: pw.BoxDecoration(
                color: typeColor,
                borderRadius: pw.BorderRadius.circular(3),
                border: pw.Border.all(color: pdf.PdfColors.black, width: 0.8),
              ),
              child: pw.Text(
                _pdfTypeLabel(type),
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: pdf.PdfColors.black,
                ),
              ),
            ),
          ),
        ),

        // Date
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Text(
            _formatPdfDate(date),
            style: const pw.TextStyle(
              fontSize: 8,
              color: pdf.PdfColors.grey700,
            ),
          ),
        ),

        // Amount (RIGHT-ALIGNED)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              amount,
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: pdf.PdfColors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatPdfDate(dynamic rawDate) {
    if (rawDate == null) return '-';
    final str = rawDate.toString();
    final parsed = DateTime.tryParse(str);
    if (parsed != null) {
      return DateFormat('dd MMM yyyy').format(parsed);
    }
    return str;
  }

  String _pdfTypeLabel(String type) {
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

  String _pdfCategoryLabel(String category) {
    final cat = category.trim();
    if (cat.isEmpty) return 'LAINNYA';
    return cat.toUpperCase();
  }

  pdf.PdfColor _pdfTypeColor(String type) {
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

  pdf.PdfColor _pdfCategoryColor(String category) {
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

  pw.Widget _buildPdfCell(
    String text, {
    bool isHeader = false,
    bool alignRight = false,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Align(
        alignment: alignRight
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: isHeader ? 9 : 8.5,
            fontWeight: isHeader || isBold
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _changeCurrency(String currency) async {
    if (mounted) setState(() => _isChangingCurrency = true);
    try {
      if (currency == 'IDR') {
        appCurrency.value = currency;
        appExchangeRate.value = 1;
        await DatabaseHelp.setSetting('currency', currency);
        return;
      }

      try {
        final rates = await Throw.getExchangeRates();
        final rate = rates[currency];
        if (rate == null || rate <= 0) {
          throw StateError('Invalid exchange rate');
        }
        await DatabaseHelp.cacheExchangeRate(currency, rate);
        appCurrency.value = currency;
        appExchangeRate.value = rate;
        await DatabaseHelp.setSetting('currency', currency);
      } catch (_) {
        final cachedRate = await DatabaseHelp.getCachedExchangeRate(currency);
        if (cachedRate == null || cachedRate <= 0) {
          throw StateError('Exchange rate unavailable while offline');
        }
        appCurrency.value = currency;
        appExchangeRate.value = cachedRate;
        await DatabaseHelp.setSetting('currency', currency);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change currency: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isChangingCurrency = false);
    }
  }

  Future<void> _retrySync() async {
    await Throw.syncPendingExpenses();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sync retry completed.')));
  }

  Future<void> _loadOnlineExpenses() async {
    var loadingShown = false;
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      loadingShown = true;

      final onlineExpenses = await Throw.getOnlineExpenses();
      final imported = await DatabaseHelp.importMissingExpenses(onlineExpenses);

      if (!mounted) return;
      if (loadingShown) Navigator.pop(context);
      loadingShown = false;
      listKey.currentState?._loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported == 0
                ? 'Your local data is already up to date.'
                : 'Loaded $imported expense(s) from your account.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      if (loadingShown) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load online expenses: $error')),
      );
    }
  }

  Future<void> _changePassword() async {
    final passwords = await showDialog<List<String>>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );
    if (passwords == null || passwords[0].isEmpty || passwords[1].length < 6) {
      return;
    }

    try {
      await AuthService.updatePassword(
        oldPassword: passwords[0],
        newPassword: passwords[1],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message =
          error.code == 'wrong-password' || error.code == 'invalid-credential'
          ? 'Current password is incorrect.'
          : error.message ?? 'Could not update password.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and all local expenses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseHelp.deleteAllForCurrentUser();
    await AuthService.deleteAccount();
  }

  Future<void> _showJumpscare() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width,
              height: MediaQuery.sizeOf(context).height,
              child: Image.asset('lib/asset/JOJO.jpeg', fit: BoxFit.cover),
            ),
          ),
        );
      },
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _oldPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password (6+ characters)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, [
            _oldPasswordController.text,
            _newPasswordController.text,
          ]),
          child: const Text('Update'),
        ),
      ],
    );
  }
}

class _CurrencyLoadingOverlay extends StatelessWidget {
  const _CurrencyLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Color(0xCCFFFFFF),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black,
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.black),
                SizedBox(height: 16),
                Text(
                  'Getting newest exchange rate...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final Future<void> Function() onDeleteAll;
  final Future<void> Function() onExportPdf;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function() onChangePassword;
  final Future<void> Function() onRetrySync;
  final Future<void> Function(String) onCurrencyChanged;
  final Future<void> Function() onLoadOnlineExpenses;

  const SettingsPage({
    super.key,
    required this.onDeleteAll,
    required this.onExportPdf,
    required this.onDeleteAccount,
    required this.onChangePassword,
    required this.onRetrySync,
    required this.onCurrencyChanged,
    required this.onLoadOnlineExpenses,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _pendingSync = 0;
  bool _notificationsEnabled = true;
  bool _autoExpenseParserEnabled = false;
  Set<String> _allowedNotificationApps = {};

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
    _loadNotificationParserStatus();
    _loadAllowedNotificationApps();
    _loadReminderPreference();
  }

  Future<void> _loadReminderPreference() async {
    final saved = await DatabaseHelp.getSetting('expense_reminders');
    if (mounted && saved != null) {
      setState(() => _notificationsEnabled = saved == 'true');
    }
  }

  Future<void> _loadAllowedNotificationApps() async {
    final apps = await NotificationExpenseService.instance.getAllowedApps();
    if (mounted) setState(() => _allowedNotificationApps = apps);
  }

  Future<void> _setNotificationAppAllowed(
    String packageName,
    bool allowed,
  ) async {
    final apps = {..._allowedNotificationApps};
    if (packageName == NotificationExpenseService.allNotificationsKey) {
      apps.clear();
      if (allowed) apps.add(NotificationExpenseService.allNotificationsKey);
    } else if (apps.contains(NotificationExpenseService.allNotificationsKey)) {
      apps.remove(NotificationExpenseService.allNotificationsKey);
      if (allowed) apps.add(packageName);
    }
    if (allowed) {
      apps.add(packageName);
    } else {
      apps.remove(packageName);
    }
    setState(() => _allowedNotificationApps = apps);
    await NotificationExpenseService.instance.setAllowedApps(apps);
  }

  Future<void> _loadNotificationParserStatus() async {
    final service = NotificationExpenseService.instance;
    final enabled =
        await service.isParserEnabled() && await service.isEnabled();
    if (mounted) setState(() => _autoExpenseParserEnabled = enabled);
    if (enabled) {
      await service.start(_showParserError);
    }
  }

  Future<void> _showParserError(String error) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not parse notification: $error')),
    );
  }

  Future<void> _toggleAutoExpenseParser(bool enabled) async {
    if (!enabled) {
      await NotificationExpenseService.instance.setParserEnabled(false);
      if (mounted) setState(() => _autoExpenseParserEnabled = false);
      return;
    }
    final service = NotificationExpenseService.instance;
    await service.setParserEnabled(true);
    if (!await service.isEnabled()) await service.openAccessSettings();
    if (await service.isEnabled()) await service.start(_showParserError);
    if (mounted) setState(() => _autoExpenseParserEnabled = true);
  }

  Future<void> _loadSyncStatus() async {
    final pending = await DatabaseHelp.getUnsyncedData();
    if (mounted) setState(() => _pendingSync = pending.length);
  }

  Future<void> _retrySync() async {
    await widget.onRetrySync();
    await _loadSyncStatus();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
      children: [
        const SizedBox(height: 30),
        Text(
          'Manage your data',
          style: GoogleFonts.itim(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Manage your data, account, and app preferences.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('Data & sync'),
        _buildSyncCard(),
        const SizedBox(height: 16),
        _SettingsAction(
          icon: Icons.cloud_download_outlined,
          title: 'Load online expenses',
          subtitle: 'Import expenses created on another device.',
          color: const Color(0xFF5DF9FF),
          onTap: widget.onLoadOnlineExpenses,
        ),
        const SizedBox(height: 16),
        _SettingsAction(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Export expenses as PDF',
          subtitle: 'Save a complete report of your expenses.',
          color: const Color(0xFF5DF9FF),
          onTap: widget.onExportPdf,
        ),
        const SizedBox(height: 16),
        _SettingsAction(
          icon: Icons.delete_sweep_outlined,
          title: 'Delete all expenses',
          subtitle: 'Permanently remove every expense from this account.',
          color: const Color(0xFFFFD6D6),
          onTap: widget.onDeleteAll,
        ),
        const SizedBox(height: 28),
        _buildSectionTitle('Preferences'),
        _buildPreferencesCard(),
        const SizedBox(height: 28),
        _buildSectionTitle('Automation'),
        _buildAutoExpenseParserCard(),
        const SizedBox(height: 28),
        _buildSectionTitle('Account'),
        _SettingsAction(
          icon: Icons.password_outlined,
          title: 'Change password',
          subtitle: 'Set a new password for this account.',
          color: const Color(0xFFE5E7EB),
          onTap: widget.onChangePassword,
        ),
        const SizedBox(height: 16),
        _SettingsAction(
          icon: Icons.person_remove_outlined,
          title: 'Delete account',
          subtitle: 'Permanently remove your account and data.',
          color: const Color(0xFFFFD6D6),
          onTap: widget.onDeleteAccount,
        ),
        const SizedBox(height: 28),
        _buildSectionTitle('Signed-in account'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_circle_outlined, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AuthService.currentUser?.email ?? 'Signed-in account',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: AuthService.signOut,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _buildSectionTitle('About'),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.info_outline),
          title: Text('Expense App'),
          subtitle: Text('Version 1.5.2'),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildSyncCard() {
    final synced = _pendingSync == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Row(
        children: [
          Icon(
            synced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              synced
                  ? 'All expenses are synced'
                  : '$_pendingSync expense(s) waiting to sync',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (!synced)
            IconButton(
              tooltip: 'Retry sync',
              onPressed: _retrySync,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }

  Widget _buildPreferencesCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        children: [
          ValueListenableBuilder<String>(
            valueListenable: appCurrency,
            builder: (context, currency, child) => ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Currency'),
              subtitle: const Text('Used when displaying expense amounts'),
              trailing: DropdownButton<String>(
                value: currency,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'IDR', child: Text('IDR')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                ],
                onChanged: (value) {
                  if (value != null) widget.onCurrencyChanged(value);
                },
              ),
            ),
          ),
          const Divider(height: 1),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: appThemeMode,
            builder: (context, mode, child) => SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark theme'),
              subtitle: const Text('Use a darker color scheme'),
              value: mode == ThemeMode.dark,
              onChanged: (enabled) async {
                final mode = enabled ? ThemeMode.dark : ThemeMode.light;
                appThemeMode.value = mode;
                await DatabaseHelp.setSetting(
                  'theme_mode',
                  enabled ? 'dark' : 'light',
                );
              },
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_none_outlined),
            title: const Text('Expense reminders'),
            subtitle: const Text('Enable reminders to record expenses'),
            value: _notificationsEnabled,
            onChanged: (enabled) async {
              setState(() => _notificationsEnabled = enabled);
              await DatabaseHelp.setSetting(
                'expense_reminders',
                enabled.toString(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAutoExpenseParserCard() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Auto Expense parser'),
            subtitle: const Text(
              'Read selected payment notifications automatically.',
            ),
            value: _autoExpenseParserEnabled,
            onChanged: _toggleAutoExpenseParser,
          ),
          const Divider(height: 1),
          ExpansionTile(
            leading: const Icon(Icons.filter_alt_outlined),
            title: const Text('Allowed payment apps'),
            subtitle: Text(
              _allowedNotificationApps.contains(
                    NotificationExpenseService.allNotificationsKey,
                  )
                  ? 'All notifications selected'
                  : '${_allowedNotificationApps.length} selected',
            ),
            children: [
              CheckboxListTile(
                dense: true,
                title: const Text('All notifications'),
                subtitle: const Text('Include notifications from every app'),
                value: _allowedNotificationApps.contains(
                  NotificationExpenseService.allNotificationsKey,
                ),
                onChanged: (allowed) {
                  if (allowed != null) {
                    _setNotificationAppAllowed(
                      NotificationExpenseService.allNotificationsKey,
                      allowed,
                    );
                  }
                },
              ),
              ...NotificationExpenseService.supportedApps.entries.map(
                (entry) => CheckboxListTile(
                  dense: true,
                  title: Text(entry.value),
                  subtitle: Text(entry.key),
                  value: _allowedNotificationApps.contains(entry.key),
                  onChanged: (allowed) {
                    if (allowed != null) {
                      _setNotificationAppAllowed(entry.key, allowed);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Future<void> Function() onTap;

  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return NeoBouncy(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.black),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

class ExpenseModel {
  final int? id;
  final String name;
  final int amount;
  final DateTime date;
  final String category;
  final String type;

  ExpenseModel({
    this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.category,
    required this.type,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    final parsedDate = DateTime.tryParse(map['date']?.toString() ?? '');
    return ExpenseModel(
      id: map['id'] as int?,
      name: map['name']?.toString().trim().isNotEmpty == true
          ? map['name'].toString()
          : 'Unknown',
      amount: map['amount'] is int
          ? map['amount'] as int
          : int.tryParse(map['amount']?.toString() ?? '0') ?? 0,
      date: parsedDate ?? DateTime.now(),
      category: map['category']?.toString().trim().isNotEmpty == true
          ? map['category'].toString().trim().toLowerCase()
          : 'general',
      type: map['type']?.toString().trim().isNotEmpty == true
          ? map['type'].toString().trim().toLowerCase()
          : 'others',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'date': date.toIso8601String().substring(0, 10),
      'category': category,
      'type': type,
    };
  }
}

class ListWithCards extends StatefulWidget {
  const ListWithCards({super.key});

  @override
  _ListWithCardsState createState() => _ListWithCardsState();
}

class _ListWithCardsState extends State<ListWithCards>
    with WidgetsBindingObserver {
  List<ExpenseModel> _expenses = [];
  bool _isLoading = true;
  ExpenseSort _sort = ExpenseSort.dateNewest;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appCurrency.addListener(_onCurrencyChanged);
    appExchangeRate.addListener(_onCurrencyChanged);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appCurrency.removeListener(_onCurrencyChanged);
    appExchangeRate.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPendingExpenses();
    }
  }

  Future<void> _syncPendingExpenses() async {
    if (_isSyncing) return;

    _isSyncing = true;
    try {
      await Throw.syncPendingExpenses();

      if (!mounted) return;

      final data = await DatabaseHelp.getData();
      setState(() {
        _expenses = data.map((item) => ExpenseModel.fromMap(item)).toList();
      });
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await DatabaseHelp.initDB();
      await DatabaseHelp.assignLegacyExpensesToCurrentUser();
      unawaited(_syncPendingExpenses());
    } catch (e) {
      print("Nigga The Database Aint Initialized");
    }

    try {
      // 1. Panggil getData() langsung dari class karena sudah static
      // Tidak perlu simpan hasil initDB() ke variabel baru
      final List<Map<String, dynamic>> data = await DatabaseHelp.getData();

      setState(() {
        // 2. Konversi List<Map> menjadi List<ExpenseModel>
        _expenses = data.map((item) => ExpenseModel.fromMap(item)).toList();
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading data: $e");
      setState(() => _isLoading = false);
    }
  }

  List<ExpenseModel> get _sortedExpenses {
    final result = [..._expenses];

    result.sort((a, b) {
      switch (_sort) {
        case ExpenseSort.dateNewest:
          return b.date.compareTo(a.date);
        case ExpenseSort.dateOldest:
          return a.date.compareTo(b.date);
        case ExpenseSort.amountHighest:
          return b.amount.compareTo(a.amount);
        case ExpenseSort.amountLowest:
          return a.amount.compareTo(b.amount);
      }
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_expenses.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            FadeSlideAnimation(
              delay: const Duration(milliseconds: 50),
              child: _buildHeroTotalCard(),
            ),
            const SizedBox(height: 36),
            _buildEmptyState(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        itemCount: _sortedExpenses.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return FadeSlideAnimation(
              delay: const Duration(milliseconds: 50),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildHeroTotalCard(),
              ),
            );
          }
          final expenseIndex = index - 1;
          return FadeSlideAnimation(
            delay: Duration(milliseconds: (expenseIndex * 30).clamp(0, 250)),
            child: CardList(
              expense: _sortedExpenses[expenseIndex],
              onRefresh: _loadData,
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroTotalCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalIdr = _expenses.fold<int>(
      0,
      (total, expense) => total + expense.amount,
    );
    final formatter = NumberFormat.currency(
      locale: _currencyLocale,
      symbol: _currencySymbol,
      decimalDigits: _currencyDecimalDigits,
    );
    final uniqueCategories = _expenses.map((e) => e.category).toSet().length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2830) : const Color(0xFFE8FDFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black, width: 2.8),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DF9FF),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.black, width: 1.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 15,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'TOTAL PENGELUARAN',
                      style: GoogleFonts.itim(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9EB5D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black, width: 1.6),
                    ),
                    child: Text(
                      appCurrency.value,
                      style: GoogleFonts.itim(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NeoBouncy(
                    scaleFactor: 0.90,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        SmoothPageRoute(
                          page: ExpenseSumarryPage(initialExpenses: _expenses),
                        ),
                      );
                      _loadData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF5DF9FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black, width: 1.8),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black,
                            offset: Offset(2, 2),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Details',
                            style: GoogleFonts.itim(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: Colors.black,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatter.format(totalIdr * appExchangeRate.value),
              style: GoogleFonts.itim(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildHeroStatChip(
                icon: Icons.receipt_long_rounded,
                text: '${_expenses.length} Transaksi',
                color: isDark ? const Color(0xFF27323C) : Colors.white,
                isDark: isDark,
              ),
              if (_expenses.isNotEmpty)
                _buildHeroStatChip(
                  icon: Icons.category_rounded,
                  text: '$uniqueCategories Kategori',
                  color: isDark ? const Color(0xFF27323C) : Colors.white,
                  isDark: isDark,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatChip({
    required IconData icon,
    required String text,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.black, width: 1.6),
        boxShadow: const [
          BoxShadow(
            color: Colors.black,
            offset: Offset(1.5, 1.5),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? const Color(0xFF5DF9FF) : Colors.black87,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: GoogleFonts.itim(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF22262B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF9EB5D),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: const Icon(
                Icons.savings_outlined,
                size: 34,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Belum Ada Pengeluaran',
              style: GoogleFonts.itim(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tekan tombol + di bawah untuk mencatat pengeluaran pertamamu!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setSort(ExpenseSort value) {
    setState(() => _sort = value);
  }
}

class CardList extends StatelessWidget {
  final ExpenseModel expense;
  final VoidCallback onRefresh;

  const CardList({super.key, required this.expense, required this.onRefresh});

  Color _getBackgroundColor() {
    switch (expense.type.toLowerCase()) {
      case 'expected':
        return const Color(0xFFF9EB5D);
      case 'unexpected':
        return const Color(0xFFFF5D5D);
      case 'others':
        return const Color(0xFF5D9BFF);
      default:
        return const Color(0xFFD9D9D9);
    }
  }

  IconData _getCategoryIcon() {
    switch (expense.category.toLowerCase()) {
      case 'makanan':
        return Icons.fastfood;
      case 'school supply':
        return Icons.school;
      case 'baju':
        return Icons.checkroom;
      case 'elektronik':
        return Icons.devices;
      case 'transportasi':
        return Icons.directions_car;
      case 'kesehatan':
        return Icons.medical_services;
      case 'hiburan':
        return Icons.celebration;
      default:
        return Icons.receipt_long;
    }
  }

  // BOX BUAT NGASIH LIAT BARANG2 NYA
  @override
  Widget build(BuildContext context) {
    final amountValue = expense.amount;
    final formatter = NumberFormat.currency(
      locale: _currencyLocale,
      symbol: _currencySymbol,
      decimalDigits: _currencyDecimalDigits,
    );
    return NeoBouncy(
      onTap: () async {
        await Navigator.push(
          context,
          SmoothPageRoute(page: ExpenseEdit(expenseId: expense.id)),
        );
        onRefresh();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _getBackgroundColor(),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(4, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Icon(_getCategoryIcon(), color: Colors.black, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    expense.name,
                    style: GoogleFonts.itim(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatter.format(amountValue * appExchangeRate.value),
                    style: GoogleFonts.itim(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    DateFormat('dd MMM yyyy', 'id_ID').format(expense.date),
                    style: GoogleFonts.itim(
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            NeoBouncy(
              onTap: () async {
                await Navigator.push(
                  context,
                  SmoothPageRoute(page: ExpenseEdit(expenseId: expense.id)),
                );
                onRefresh();
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(2, 2),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  size: 18,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String get _currencySymbol {
  switch (appCurrency.value) {
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    default:
      return 'Rp';
  }
}

String get _currencyLocale {
  switch (appCurrency.value) {
    case 'USD':
      return 'en_US';
    case 'EUR':
      return 'de_DE';
    default:
      return 'id_ID';
  }
}

int get _currencyDecimalDigits {
  switch (appCurrency.value) {
    case 'USD':
    case 'EUR':
      return 2;
    default:
      return 0;
  }
}

class ExpenseBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const ExpenseBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? const Color(0xFF22262B) : Colors.white;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: barBg,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Home Tab (Index 0)
          Expanded(
            child: _buildPillTab(
              context: context,
              index: 0,
              label: 'Home',
              activeIcon: Icons.home_rounded,
              inactiveIcon: Icons.home_outlined,
              activeColor: const Color(0xFF5DF9FF),
              isDark: isDark,
            ),
          ),

          const SizedBox(width: 8),

          // Center Hero Add Action (Index 1)
          _buildCenterHeroButton(context, isDark: isDark),

          const SizedBox(width: 8),

          // Settings Tab (Index 2)
          Expanded(
            child: _buildPillTab(
              context: context,
              index: 2,
              label: 'Settings',
              activeIcon: Icons.settings_rounded,
              inactiveIcon: Icons.settings_outlined,
              activeColor: const Color(0xFFC77DFF),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillTab({
    required BuildContext context,
    required int index,
    required String label,
    required IconData activeIcon,
    required IconData inactiveIcon,
    required Color activeColor,
    required bool isDark,
  }) {
    final isSelected = selectedIndex == index;

    return NeoBouncy(
      scaleFactor: 0.92,
      onTap: () => onSelected(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 12 : 8,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected
                  ? Colors.black
                  : (isDark ? Colors.grey[400] : Colors.grey[600]),
              size: 22,
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.itim(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCenterHeroButton(BuildContext context, {required bool isDark}) {
    final isSelected = selectedIndex == 1;

    return NeoBouncy(
      scaleFactor: 0.90,
      onTap: () => onSelected(1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        width: isSelected ? 56 : 52,
        height: isSelected ? 56 : 52,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFF5D5D) : const Color(0xFFF9EB5D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black, width: 2.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black,
              offset: isSelected ? const Offset(1, 1) : const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Center(
          child: AnimatedRotation(
            turns: isSelected ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: Icon(
              Icons.add_rounded,
              color: Colors.black,
              size: isSelected ? 32 : 30,
              weight: 800,
            ),
          ),
        ),
      ),
    );
  }
}

enum ExpenseSort { dateNewest, dateOldest, amountHighest, amountLowest }
