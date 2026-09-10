import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import 'ExpenseAddPage.dart';
import 'package:intl/intl.dart';
import '../services/databaseHelper.dart';
import '../services/ApiService.dart';
import 'ExpenseEdit.dart';
import '../services/auth_service.dart';
import '../services/notification_expense_service.dart';

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
  int _selectedIndex = 2;
  int _homeTapCount = 0;
  bool _isChangingCurrency = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _restoreCurrencyPreference();
    _startNotificationParser();
  }

  @override
  void dispose() {
    _pageController.dispose();
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
    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: _onPageChanged,
            children: [
              _buildSettingsPage(),
              ExpenseAddPage(
                embedded: true,
                onCancel: _goToHome,
                onSaved: _goToHome,
              ),
              ListWithCards(key: listKey),
            ],
          ),
          if (_selectedIndex == 2)
            Positioned(
              top: 8,
              left: 18,
              right: 18,
              child: SafeArea(bottom: false, child: _buildFloatingHomeHeader()),
            ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 14,
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

  Widget _buildFloatingHomeHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
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
          child: Text(
            'Expenses',
            style: GoogleFonts.itim(fontSize: 27, fontWeight: FontWeight.bold),
          ),
        ),
        _buildSortDropdown(),
      ],
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
      _homeTapCount = index == 2 ? _homeTapCount + 1 : 0;
    });
  }

  Future<void> _goToHome() async {
    if (!mounted) return;
    listKey.currentState?._loadData();
    await _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildSortDropdown() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
    );
  }

  Future<void> _onNavigationSelected(int index) async {
    if (index == _selectedIndex) {
      if (index == 2) {
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
        decimalDigits: 0,
      );
      final document = pw.Document();
      document.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(level: 0, child: pw.Text('Expense Report')),
            pw.Text('Account: ${AuthService.currentUser?.email ?? 'Unknown'}'),
            pw.Text(
              'Generated: ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
            ),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(color: pdf.PdfColors.black),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.75),
                1: pw.FixedColumnWidth(82),
              },
              children: [
                _buildPdfRow(
                  const ['Name', 'Amount', 'Category', 'Type', 'Date'],
                  pdf.PdfColors.grey300,
                  isHeader: true,
                ),
                ...sortedExpenses.map((expense) {
                  final amountIdr = expense['amount'] is int
                      ? expense['amount'] as int
                      : int.tryParse(expense['amount'].toString()) ?? 0;
                  final amount = amountIdr * appExchangeRate.value;
                  final type = expense['type']?.toString() ?? '';
                  return _buildPdfRow([
                    expense['name']?.toString() ?? '',
                    formatter.format(amount).replaceAll(',', '.'),
                    expense['category']?.toString() ?? '',
                    type,
                    expense['date']?.toString() ?? '',
                  ], _pdfTypeColor(type));
                }),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total expenses: ${formatter.format(expenses.fold<double>(0, (total, expense) {
                  final amountIdr = expense['amount'] is int ? expense['amount'] as int : int.tryParse(expense['amount'].toString()) ?? 0;
                  return total + amountIdr * appExchangeRate.value;
                })).replaceAll(',', '.')}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );

      final Uint8List bytes = await document.save();
      final fileName =
          'expense-report-${DateTime.now().millisecondsSinceEpoch}.pdf';
      String? path;

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
      } else {
        path = await FileSaver.instance.saveFile(
          name: fileName,
          bytes: bytes,
          ext: 'pdf',
          mimeType: MimeType.pdf,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null || path.isEmpty
                ? 'PDF exported to Downloads.'
                : 'PDF exported: $path',
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

  pw.TableRow _buildPdfRow(
    List<String> values,
    pdf.PdfColor color, {
    bool isHeader = false,
  }) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: color),
      children: values
          .map(
            (value) => pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  fontWeight: isHeader
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          )
          .toList(),
    );
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
          subtitle: Text('Version 0.0.1'),
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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
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
      return Stack(
        children: [
          const Center(child: Text('Data Kosong')),
          Positioned(bottom: 104, left: 0, right: 0, child: _buildTotalCard()),
        ],
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 92, bottom: 190),
            itemCount: _sortedExpenses.length,
            itemBuilder: (context, index) {
              return CardList(
                expense: _sortedExpenses[index],
                onRefresh: _loadData,
              );
            },
          ),
        ),
        Positioned(bottom: 104, left: 0, right: 0, child: _buildTotalCard()),
      ],
    );
  }

  Widget _buildTotalCard() {
    final totalIdr = _expenses.fold<int>(
      0,
      (total, expense) => total + expense.amount,
    );
    final formatter = NumberFormat.currency(
      locale: _currencyLocale,
      symbol: _currencySymbol,
      decimalDigits: 0,
    );

    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 100,
            maxWidth: MediaQuery.sizeOf(context).width - 48,
          ),
          child: IntrinsicWidth(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatter.format(totalIdr * appExchangeRate.value),
                        maxLines: 1,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      locale: 'id_ID',
      symbol: _currencySymbol,
      decimalDigits: 0,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 25),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 0, offset: Offset(8, 8)),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 40),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Icon(
                    _getCategoryIcon(),
                    color: Colors.black,
                    size: 35,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.name,
                        style: GoogleFonts.itim(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        formatter.format(amountValue * appExchangeRate.value),
                        style: GoogleFonts.itim(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        DateFormat('dd MMM yyyy', 'id_ID').format(expense.date),
                        style: GoogleFonts.itim(
                          fontSize: 16,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: -8,
            bottom: -8,
            child: IconButton(
              tooltip: 'Edit expense',
              icon: const Icon(Icons.edit, color: Colors.black),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ExpenseEdit(expenseId: expense.id),
                  ),
                );

                onRefresh();
              },
            ),
          ),
        ],
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
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(38),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(5, 5), blurRadius: 0),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildItem(context, Icons.settings_outlined, 0),
          _buildItem(context, Icons.add, 1),
          _buildItem(context, Icons.home_outlined, 2),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, IconData icon, int index) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: () => onSelected(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        width: isSelected ? 58 : 42,
        height: isSelected ? 58 : 42,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5DF9FF) : Colors.transparent,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
        ),
        child: Icon(
          icon,
          color: isSelected
              ? Colors.black
              : Theme.of(context).colorScheme.onSurface,
          size: isSelected ? 31 : 25,
          weight: isSelected ? 800 : 500,
        ),
      ),
    );
  }
}

enum ExpenseSort { dateNewest, dateOldest, amountHighest, amountLowest }
