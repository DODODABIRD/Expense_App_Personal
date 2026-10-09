import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/databaseHelper.dart';
import '../services/notification_expense_service.dart';
import '../services/error_log_service.dart';
import '../widgets/neo_animations.dart';

class SettingsPage extends StatefulWidget {
  final Future<void> Function() onDeleteAll;
  final Future<void> Function() onExportPdf;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function() onChangePassword;
  final Future<void> Function() onRetrySync;
  final Future<void> Function(String) onCurrencyChanged;
  final Future<void> Function() onLoadOnlineExpenses;
  final Future<void> Function() onPendingNotificationAdded;

  const SettingsPage({
    super.key,
    required this.onDeleteAll,
    required this.onExportPdf,
    required this.onDeleteAccount,
    required this.onChangePassword,
    required this.onRetrySync,
    required this.onCurrencyChanged,
    required this.onLoadOnlineExpenses,
    required this.onPendingNotificationAdded,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _pendingSync = 0;
  bool _notificationsEnabled = true;
  bool _autoExpenseParserEnabled = false;
  bool _isUpdatingAiReference = false;
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
      await service.start(
        _showParserError,
        onPendingNotificationAdded: widget.onPendingNotificationAdded,
      );
    }
  }

  Future<void> _showParserError(String error) async {
    if (!mounted) return;
    showNotificationSnackBar(
      context,
      'Could not parse notification: $error',
      isError: true,
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
    if (await service.isEnabled()) {
      await service.start(
        _showParserError,
        onPendingNotificationAdded: widget.onPendingNotificationAdded,
      );
    }
    if (mounted) setState(() => _autoExpenseParserEnabled = true);
  }

  Future<void> _loadSyncStatus() async {
    final pending = await DatabaseHelp.getUnsyncedData();
    if (mounted) setState(() => _pendingSync = pending.length);
  }

  Future<void> _retrySync() async {
    try {
      await widget.onRetrySync();
      if (!mounted) return;
      await _loadSyncStatus();
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Refresh expense sync status');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh sync status: $error')),
      );
    }
  }

  Future<void> _updateAiNotificationReference() async {
    if (_isUpdatingAiReference) return;
    setState(() => _isUpdatingAiReference = true);
    try {
      final count = await NotificationExpenseService.instance
          .updateAiNotificationReference();
      if (!mounted) return;
      showNotificationSnackBar(
        context,
        'AI notification reference updated with $count expenses.',
      );
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Update AI notification reference');
      if (!mounted) return;
      showNotificationSnackBar(
        context,
        'Could not update AI notification reference: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isUpdatingAiReference = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 150),
      children: [
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
          icon: Icons.auto_awesome_outlined,
          title: 'Update AI notification reference',
          subtitle: _isUpdatingAiReference
              ? 'Updating expense history...'
              : 'Refresh expense examples used by notification AI.',
          color: const Color(0xFFE5E7EB),
          onTap: _updateAiNotificationReference,
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
              const Icon(Icons.account_circle_outlined, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AuthService.currentUser?.email ?? 'Signed-in account',
                  style: GoogleFonts.itim(fontWeight: FontWeight.bold),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(
              'Expense App',
              style: GoogleFonts.itim(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Version 1.7.0',
              style: GoogleFonts.itim(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: GoogleFonts.itim(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
        ),
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
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
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
            title: Text(
              'Expense reminders',
              style: GoogleFonts.itim(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Enable reminders to record expenses',
              style: GoogleFonts.itim(),
            ),
            value: _notificationsEnabled,
            activeThumbColor: const Color(0xFF5DF9FF),
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: Text(
              'Auto Expense parser',
              style: GoogleFonts.itim(
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
            ),
            subtitle: Text(
              'Read selected payment notifications automatically.',
              style: GoogleFonts.itim(color: colors.onSurfaceVariant),
            ),
            value: _autoExpenseParserEnabled,
            activeThumbColor: const Color(0xFF5DF9FF),
            onChanged: _toggleAutoExpenseParser,
          ),
          const Divider(height: 1),
          ExpansionTile(
            leading: const Icon(Icons.filter_alt_outlined),
            iconColor: colors.onSurface,
            collapsedIconColor: colors.onSurface,
            title: Text(
              'Allowed payment apps',
              style: GoogleFonts.itim(
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
            ),
            subtitle: Text(
              _allowedNotificationApps.contains(
                    NotificationExpenseService.allNotificationsKey,
                  )
                  ? 'All notifications selected'
                  : '${_allowedNotificationApps.length} selected',
              style: GoogleFonts.itim(color: colors.onSurfaceVariant),
            ),
            children: [
              CheckboxListTile(
                dense: true,
                activeColor: const Color(0xFF5DF9FF),
                checkColor: Colors.black,
                title: Text(
                  'All notifications',
                  style: GoogleFonts.itim(
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Include notifications from every app',
                  style: GoogleFonts.itim(color: colors.onSurfaceVariant),
                ),
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
                  activeColor: const Color(0xFF5DF9FF),
                  checkColor: Colors.black,
                  title: Text(
                    entry.value,
                    style: GoogleFonts.itim(
                      fontWeight: FontWeight.bold,
                      color: colors.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    entry.key,
                    style: GoogleFonts.itim(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
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
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.black),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.itim(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.itim(
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
