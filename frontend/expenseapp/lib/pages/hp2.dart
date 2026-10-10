import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/expense_model.dart';
import '../services/databaseHelper.dart';
import '../services/ApiService.dart';
import '../services/error_log_service.dart';
import '../services/pdf_export_service.dart';
import '../services/auth_service.dart';
import '../services/notification_expense_service.dart';
import '../widgets/neo_animations.dart';
import '../widgets/neo_brutalist_calendar.dart';
import 'ExpenseAddPage.dart';
import 'ExpenseEdit.dart';
import 'ExpenseSumarry.dart';
import 'developer_logs_page.dart';
import 'notification_permission_page.dart';
import 'PendingNotificationReviewPage.dart';
import 'settings_page.dart';

class HomePage2 extends StatefulWidget {
  const HomePage2({super.key});

  @override
  State<HomePage2> createState() => _HomePage2State();
}

class _HomePage2State extends State<HomePage2> with WidgetsBindingObserver {
  final listKey = GlobalKey<_ListWithCardsState>();
  late final PageController _pageController;
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);
  int _selectedIndex = 0;
  int _homeTapCount = 0;
  int _settingsTapCount = 0;
  DateTime? _settingsTapStartedAt;
  bool _isChangingCurrency = false;
  bool _isLoadingOnlineExpenses = false;
  int _pendingNotificationCount = 0;

  // Filter state
  String? _selectedCategory;
  String? _selectedType;
  DateTimeRange? _dateRange;
  ExpenseSort _selectedSort = ExpenseSort.dateNewest;
  final _filterPanelKey = GlobalKey<_FilterPanelState>();

  bool get _hasActiveFilters {
    return _selectedCategory != null ||
        _selectedType != null ||
        _dateRange != null ||
        _selectedSort != ExpenseSort.dateNewest;
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategory != null) count++;
    if (_selectedType != null) count++;
    if (_dateRange != null) count++;
    if (_selectedSort != ExpenseSort.dateNewest) count++;
    return count;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _selectedIndex);
    _restoreCurrencyPreference();
    _loadPendingNotificationCount();
    _startNotificationParser();
    _checkFirstTimeNotificationPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  Future<void> _startNotificationParser() async {
    final service = NotificationExpenseService.instance;
    if (!await service.isParserEnabled() || !await service.isEnabled()) return;
    await service.start(
      _showNotificationParserError,
      onPendingNotificationAdded: _handlePendingNotificationAdded,
    );
  }

  Future<void> _handlePendingNotificationAdded() async {
    await _loadPendingNotificationCount();
    if (mounted) {
      showNotificationSnackBar(
        context,
        'A parsed notification is ready for review.',
      );
    }
  }

  Future<void> _loadPendingNotificationCount() async {
    try {
      final count = await DatabaseHelp.getPendingNotificationExpenseCount();
      if (mounted) setState(() => _pendingNotificationCount = count);
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Load pending notification count');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPendingNotificationCount();
    }
  }

  Future<void> _openPendingNotificationReview() async {
    await Navigator.of(context).push<void>(
      SmoothPageRoute<void>(
        page: PendingNotificationReviewPage(
          onExpenseApproved: () async {
            await listKey.currentState?._loadData();
          },
        ),
      ),
    );
    await _loadPendingNotificationCount();
  }

  Future<void> _showNotificationParserError(String error) async {
    if (!mounted) return;
    showNotificationSnackBar(
      context,
      'Could not parse notification: $error',
      isError: true,
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
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Restore currency preference');
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
          if (_isChangingCurrency)
            const _LoadingOverlay(message: 'Getting newest exchange rate...'),
          if (_isLoadingOnlineExpenses)
            const _LoadingOverlay(message: 'Loading online expenses...'),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFiltersButton(),
                    const SizedBox(width: 8),
                    if (_pendingNotificationCount >= 0)
                      Tooltip(
                        message: 'Review parsed notifications',
                        child: NeoBouncy(
                          onTap: _openPendingNotificationReview,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.black, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black,
                                  offset: Offset(2, 2),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Badge(
                                isLabelVisible: _pendingNotificationCount > 0,
                                label: Text(
                                  _pendingNotificationCount > 99
                                      ? '99+'
                                      : '$_pendingNotificationCount',
                                  style: const TextStyle(fontSize: 9),
                                ),
                                child: Icon(
                                  Icons.receipt_long_outlined,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
      onPendingNotificationAdded: _handlePendingNotificationAdded,
    );
  }

  void _onPageChanged(int index) {
    if (!mounted) return;
    if (index != 2) {
      _settingsTapCount = 0;
      _settingsTapStartedAt = null;
    }
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

  Widget _buildFiltersButton() {
    return NeoBouncy(
      onTap: _showFilterPanel,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _hasActiveFilters ? const Color(0xFF5DF9FF) : Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 18,
              color: Colors.black,
            ),
            const SizedBox(width: 6),
            Text(
              'Filters',
              style: GoogleFonts.itim(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            if (_activeFilterCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_activeFilterCount',
                  style: GoogleFonts.itim(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFilterPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterPanel(
        key: _filterPanelKey,
        initialCategory: _selectedCategory,
        initialType: _selectedType,
        initialDateRange: _dateRange,
        initialSort: _selectedSort,
        categories: listKey.currentState?._uniqueCategories ?? [],
        onApply: (category, type, dateRange, sort) {
          setState(() {
            _selectedCategory = category;
            _selectedType = type;
            _dateRange = dateRange;
            _selectedSort = sort;
          });
          listKey.currentState?._setFilter(category, type, dateRange, sort);
        },
        onReset: () {
          setState(() {
            _selectedCategory = null;
            _selectedType = null;
            _dateRange = null;
            _selectedSort = ExpenseSort.dateNewest;
          });
          listKey.currentState?._resetFilters();
        },
      ),
    );
  }

  Future<void> _onNavigationSelected(int index) async {
    if (index == 2) {
      final now = DateTime.now();
      final startedAt = _settingsTapStartedAt;
      if (startedAt == null ||
          now.difference(startedAt) > const Duration(seconds: 2)) {
        _settingsTapStartedAt = now;
        _settingsTapCount = 0;
      }
      _settingsTapCount++;
      if (_settingsTapCount == 3) {
        _settingsTapCount = 0;
        _settingsTapStartedAt = null;
        await Navigator.of(
          context,
        ).push(SmoothPageRoute(page: const DeveloperLogsPage()));
        return;
      }
    } else {
      _settingsTapCount = 0;
      _settingsTapStartedAt = null;
    }

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
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: Text(
          'Delete all expenses?',
          style: GoogleFonts.itim(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently delete every expense from this account. This action cannot be undone.',
          style: GoogleFonts.itim(),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.itim()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.black, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete all', style: GoogleFonts.itim()),
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
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Delete all expenses');
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
          const SnackBar(content: Text("There are no expenses to export.")),
        );
        return;
      }
      await PdfExportService.exportExpenses(context: context, expenses: expenses);
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, "Export expense report");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not export PDF: $error")),
      );
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
      } catch (error, stackTrace) {
        captureAppError(error, stackTrace, 'Fetch exchange rate');
        final cachedRate = await DatabaseHelp.getCachedExchangeRate(currency);
        if (cachedRate == null || cachedRate <= 0) {
          throw StateError('Exchange rate unavailable while offline');
        }
        appCurrency.value = currency;
        appExchangeRate.value = cachedRate;
        await DatabaseHelp.setSetting('currency', currency);
      }
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Change currency');
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
    try {
      await Throw.syncPendingExpenses();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync retry completed.')));
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Retry expense sync');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not retry sync: $error')));
    }
  }

  Future<void> _loadOnlineExpenses() async {
    if (!mounted || _isLoadingOnlineExpenses) return;
    setState(() => _isLoadingOnlineExpenses = true);
    try {
      final onlineExpenses = await Throw.getOnlineExpenses();
      final imported = await DatabaseHelp.importMissingExpenses(onlineExpenses);

      if (!mounted) return;
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
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Load online expenses');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load online expenses: $error')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingOnlineExpenses = false);
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
    } on FirebaseAuthException catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Change password');
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
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.black, width: 2),
        ),
        title: Text(
          'Delete account?',
          style: GoogleFonts.itim(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This permanently deletes your account and all local expenses.',
          style: GoogleFonts.itim(),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.itim()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.black, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete account', style: GoogleFonts.itim()),
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.black, width: 2),
      ),
      title: Text(
        'Change password',
        style: GoogleFonts.itim(fontWeight: FontWeight.bold),
      ),
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
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.itim()),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5DF9FF),
            foregroundColor: Colors.black,
            side: const BorderSide(color: Colors.black, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.pop(context, [
            _oldPasswordController.text,
            _newPasswordController.text,
          ]),
          child: Text('Update', style: GoogleFonts.itim()),
        ),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  final String message;

  const _LoadingOverlay({required this.message});

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.black),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: GoogleFonts.itim(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPanel extends StatefulWidget {
  final String? initialCategory;
  final String? initialType;
  final DateTimeRange? initialDateRange;
  final ExpenseSort initialSort;
  final List<String> categories;
  final Function(String?, String?, DateTimeRange?, ExpenseSort) onApply;
  final VoidCallback onReset;

  const _FilterPanel({
    super.key,
    this.initialCategory,
    this.initialType,
    this.initialDateRange,
    required this.initialSort,
    required this.categories,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  late String? _selectedCategory;
  late String? _selectedType;
  late DateTimeRange? _dateRange;
  late ExpenseSort _selectedSort;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _selectedType = widget.initialType;
    _dateRange = widget.initialDateRange;
    _selectedSort = widget.initialSort;
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
  }

  void _resetAll() {
    setState(() {
      _selectedCategory = null;
      _selectedType = null;
      _dateRange = null;
      _selectedSort = ExpenseSort.dateNewest;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark ? const Color(0xFF22262B) : Colors.white;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.black, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(0, -4), blurRadius: 0),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: GoogleFonts.itim(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                NeoBouncy(
                  onTap: () {
                    _resetAll();
                    widget.onReset();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5D5D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded, size: 16, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          'Reset',
                          style: GoogleFonts.itim(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Range Section
                  _buildSectionTitle('Date Range', isDark),
                  const SizedBox(height: 8),
                  _buildDateRangePicker(isDark),
                  const SizedBox(height: 20),

                  // Sort Section
                  _buildSectionTitle('Sort By', isDark),
                  const SizedBox(height: 8),
                  _buildSortOptions(isDark),
                  const SizedBox(height: 20),

                  // Type Section
                  _buildSectionTitle('Type', isDark),
                  const SizedBox(height: 8),
                  _buildTypeOptions(isDark),
                  const SizedBox(height: 20),

                  // Category Section
                  if (widget.categories.isNotEmpty) ...[
                    _buildSectionTitle('Category', isDark),
                    const SizedBox(height: 8),
                    _buildCategoryOptions(isDark),
                    const SizedBox(height: 20),
                  ],

                  // Apply Button
                  SizedBox(
                    width: double.infinity,
                    child: NeoBouncy(
                      onTap: () {
                        widget.onApply(_selectedCategory, _selectedType, _dateRange, _selectedSort);
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5DF9FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black, offset: Offset(3, 3), blurRadius: 0),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Apply Filters',
                            style: GoogleFonts.itim(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.itim(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: isDark ? const Color(0xFF5DF9FF) : Colors.black87,
      ),
    );
  }

  Widget _buildDateRangePicker(bool isDark) {
    final isActive = _dateRange != null;
    return GestureDetector(
      onTap: () => _showCustomCalendar(isDark),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF5DF9FF) : (isDark ? const Color(0xFF1E2830) : const Color(0xFFF5F5F5)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: isActive
              ? const [BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0)]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 22,
              color: Colors.black,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isActive
                    ? '${DateFormat('dd MMM yyyy', 'id_ID').format(_dateRange!.start)} - ${DateFormat('dd MMM yyyy', 'id_ID').format(_dateRange!.end)}'
                    : 'Select date range',
                style: GoogleFonts.itim(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            if (isActive)
              GestureDetector(
                onTap: () => _clearDateRange(),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 16, color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showCustomCalendar(bool isDark) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeoBrutalistCalendar(
              initialRange: _dateRange,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              onRangeSelected: (range) {
                if (range != null) {
                  setState(() => _dateRange = range);
                }
              },
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF5DF9FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black, offset: Offset(3, 3), blurRadius: 0),
                  ],
                ),
                child: Center(
                  child: Text(
                    'Done',
                    style: GoogleFonts.itim(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOptions(bool isDark) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildSortChip('Newest', ExpenseSort.dateNewest, isDark),
        _buildSortChip('Oldest', ExpenseSort.dateOldest, isDark),
        _buildSortChip('Highest', ExpenseSort.amountHighest, isDark),
        _buildSortChip('Lowest', ExpenseSort.amountLowest, isDark),
      ],
    );
  }

  Widget _buildSortChip(String label, ExpenseSort sort, bool isDark) {
    final isSelected = _selectedSort == sort;
    return GestureDetector(
      onTap: () => setState(() => _selectedSort = sort),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF9EB5D) : (isDark ? const Color(0xFF1E2830) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black,
            width: isSelected ? 2.5 : 2,
          ),
          boxShadow: isSelected
              ? const [BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0)]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.itim(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeOptions(bool isDark) {
    final types = ['expected', 'unexpected', 'others'];
    final typeLabels = {'expected': 'Expected', 'unexpected': 'Unexpected', 'others': 'Others'};
    final typeColors = {
      'expected': const Color(0xFFF9EB5D),
      'unexpected': const Color(0xFFFF5D5D),
      'others': const Color(0xFF5D9BFF),
    };

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: types.map((type) {
        final isSelected = _selectedType == type;
        return GestureDetector(
          onTap: () => setState(() => _selectedType = isSelected ? null : type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? typeColors[type] : (isDark ? const Color(0xFF1E2830) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.black,
                width: isSelected ? 2.5 : 2,
              ),
              boxShadow: isSelected
                  ? const [BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0)]
                  : null,
            ),
            child: Text(
              typeLabels[type]!,
              style: GoogleFonts.itim(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryOptions(bool isDark) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        // All category chip
        GestureDetector(
          onTap: () => setState(() => _selectedCategory = null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _selectedCategory == null ? const Color(0xFF5DF9FF) : (isDark ? const Color(0xFF1E2830) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.black,
                width: _selectedCategory == null ? 2.5 : 2,
              ),
              boxShadow: _selectedCategory == null
                  ? const [BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0)]
                  : null,
            ),
            child: Text(
              'All',
              style: GoogleFonts.itim(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
        ),
        // Category chips
        ...widget.categories.map((category) {
          final isSelected = _selectedCategory == category;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = category),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF5DF9FF) : (isDark ? const Color(0xFF1E2830) : Colors.white),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.black,
                  width: isSelected ? 2.5 : 2,
                ),
                boxShadow: isSelected
                    ? const [BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0)]
                    : null,
              ),
              child: Text(
                _capitalizeCategory(category),
                style: GoogleFonts.itim(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  String _capitalizeCategory(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

void showNotificationSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final foregroundColor = isError ? Colors.black : Colors.white;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError
          ? const Color(0xFFFFD6D6)
          : const Color(0xFF22262B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black, width: 1.5),
      ),
      content: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.notifications_active_rounded,
            color: isError ? const Color(0xFFFF5D5D) : const Color(0xFF5DF9FF),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.itim(
                color: foregroundColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
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

  // Filter state
  String _searchQuery = '';
  String? _filterCategory;
  String? _filterType;
  DateTimeRange? _filterDateRange;

  List<String> get _uniqueCategories {
    final cats = _expenses.map((e) => e.category.toLowerCase()).toSet().toList();
    cats.sort();
    return cats;
  }

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
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Sync pending expenses');
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
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Initialize expense database');
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
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Load expenses');
      setState(() => _isLoading = false);
    }
  }

  List<ExpenseModel> get _sortedExpenses {
    var result = [..._expenses];

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((e) {
        return e.name.toLowerCase().contains(query) ||
            e.category.toLowerCase().contains(query);
      }).toList();
    }

    // Apply category filter
    if (_filterCategory != null) {
      result = result
          .where((e) => e.category.toLowerCase() == _filterCategory!.toLowerCase())
          .toList();
    }

    // Apply type filter
    if (_filterType != null) {
      result = result
          .where((e) => e.type.toLowerCase() == _filterType!.toLowerCase())
          .toList();
    }

    // Apply date range filter
    if (_filterDateRange != null) {
      final start = DateTime(
        _filterDateRange!.start.year,
        _filterDateRange!.start.month,
        _filterDateRange!.start.day,
      );
      final end = DateTime(
        _filterDateRange!.end.year,
        _filterDateRange!.end.month,
        _filterDateRange!.end.day,
        23,
        59,
        59,
      );
      result = result.where((e) {
        return !e.date.isBefore(start) && !e.date.isAfter(end);
      }).toList();
    }

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
      locale: currencyLocale,
      symbol: currencySymbol,
      decimalDigits: currencyDecimalDigits,
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
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 340;
              final currencyChip = Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
              );
              final detailsButton = NeoBouncy(
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
              );
              final titleChip = Container(
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
                    Flexible(
                      child: Text(
                        'TOTAL PENGELUARAN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.itim(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: titleChip,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isCompact) ...[
                            currencyChip,
                            const SizedBox(width: 8),
                          ],
                          detailsButton,
                        ],
                      ),
                    ],
                  ),
                  if (isCompact)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: currencyChip,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatter.format(totalIdr * appExchangeRate.value),
              style: GoogleFonts.itim(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: 0,
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

  void _setFilter(String? category, String? type, DateTimeRange? dateRange, ExpenseSort sort) {
    setState(() {
      _filterCategory = category;
      _filterType = type;
      _filterDateRange = dateRange;
      _sort = sort;
    });
  }

  void _resetFilters() {
    setState(() {
      _filterCategory = null;
      _filterType = null;
      _filterDateRange = null;
      _sort = ExpenseSort.dateNewest;
    });
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
      locale: currencyLocale,
      symbol: currencySymbol,
      decimalDigits: currencyDecimalDigits,
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
              width: 44,
              height: 44,
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
              child: Icon(_getCategoryIcon(), color: Colors.black, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    expense.name,
                    style: GoogleFonts.itim(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    formatter.format(amountValue * appExchangeRate.value),
                    style: GoogleFonts.itim(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    DateFormat('dd MMM yyyy', 'id_ID').format(expense.date),
                    style: GoogleFonts.itim(
                      fontSize: 11,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
