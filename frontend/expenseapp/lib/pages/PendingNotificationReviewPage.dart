import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/databaseHelper.dart';
import '../services/error_log_service.dart';
import '../services/notification_expense_service.dart';
import '../widgets/neo_animations.dart';

class PendingNotificationReviewPage extends StatefulWidget {
  final Future<void> Function()? onExpenseApproved;

  const PendingNotificationReviewPage({super.key, this.onExpenseApproved});

  @override
  State<PendingNotificationReviewPage> createState() =>
      _PendingNotificationReviewPageState();
}

class _PendingNotificationDraft {
  final int id;
  final TextEditingController nameController;
  final TextEditingController amountController;
  final String sourceApp;
  final DateTime receivedAt;
  DateTime date;
  String category;
  String type;

  _PendingNotificationDraft(Map<String, dynamic> row)
    : id = row['id'] as int,
      nameController = TextEditingController(
        text: row['name']?.toString() ?? '',
      ),
      amountController = TextEditingController(
        text: row['amount']?.toString() ?? '',
      ),
      sourceApp = row['sourceApp']?.toString() ?? '',
      receivedAt =
          DateTime.tryParse(row['receivedAt']?.toString() ?? '') ??
          DateTime.now(),
      date = DateTime.tryParse(row['date']?.toString() ?? '') ?? DateTime.now(),
      category = row['category']?.toString() ?? 'lainnya',
      type = row['type']?.toString() ?? 'unexpected';

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}

class _PendingNotificationReviewPageState
    extends State<PendingNotificationReviewPage> {
  static const _categories = [
    'makanan',
    'transportasi',
    'hiburan',
    'school supply',
    'baju',
    'elektronik',
    'kesehatan',
    'lainnya',
  ];
  static const _types = ['expected', 'unexpected', 'others'];

  List<_PendingNotificationDraft> _items = [];
  final Set<int> _busyIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPending() async {
    setState(() => _isLoading = true);
    try {
      final rows = await DatabaseHelp.getPendingNotificationExpenses();
      final items = rows.map(_PendingNotificationDraft.new).toList();
      if (!mounted) {
        for (final item in items) {
          item.dispose();
        }
        return;
      }
      for (final item in _items) {
        item.dispose();
      }
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Load pending notifications');
      if (mounted) setState(() => _isLoading = false);
      _showMessage('Could not load pending notifications.');
    }
  }

  int _amount(_PendingNotificationDraft item) =>
      int.tryParse(
        item.amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
      ) ??
      0;

  Future<void> _persistDraft(_PendingNotificationDraft item) async {
    final name = item.nameController.text.trim();
    final amount = _amount(item);
    if (name.isEmpty || amount <= 0) {
      throw const FormatException(
        'Enter a name and an amount greater than zero.',
      );
    }

    final updated = await DatabaseHelp.updatePendingNotificationExpense(
      id: item.id,
      name: name,
      amount: amount,
      date: _dateString(item.date),
      category: _categories.contains(item.category) ? item.category : 'lainnya',
      type: _types.contains(item.type) ? item.type : 'unexpected',
    );
    if (updated == 0) {
      throw StateError('This pending notification no longer exists.');
    }
  }

  Future<void> _saveDraft(_PendingNotificationDraft item) async {
    if (!_beginAction(item.id)) return;
    try {
      await _persistDraft(item);
      _showMessage('Changes saved.');
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Save pending notification edits');
      _showMessage(
        error is FormatException ? error.message : 'Could not save changes.',
      );
    } finally {
      _endAction(item.id);
    }
  }

  Future<void> _approveDraft(_PendingNotificationDraft item) async {
    if (!_beginAction(item.id)) return;
    try {
      await _persistDraft(item);
      final approved = await DatabaseHelp.approvePendingNotificationExpense(
        item.id,
      );
      if (!approved) {
        throw StateError('This pending notification no longer exists.');
      }

      item.dispose();
      if (!mounted) return;
      setState(() => _items.remove(item));
      await widget.onExpenseApproved?.call();
      _showMessage('Added to expenses.');
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Approve pending notification');
      _showMessage(
        error is FormatException
            ? error.message
            : 'Could not add this expense.',
      );
    } finally {
      _endAction(item.id);
    }
  }

  Future<void> _discardDraft(_PendingNotificationDraft item) async {
    if (!_beginAction(item.id)) return;
    try {
      final deleted = await DatabaseHelp.discardPendingNotificationExpense(
        item.id,
      );
      if (deleted == 0) {
        throw StateError('This pending notification no longer exists.');
      }

      item.dispose();
      if (mounted) setState(() => _items.remove(item));
    } catch (error, stackTrace) {
      captureAppError(error, stackTrace, 'Discard pending notification');
      _showMessage('Could not discard this notification.');
    } finally {
      _endAction(item.id);
    }
  }

  bool _beginAction(int id) {
    if (_busyIds.contains(id)) return false;
    setState(() => _busyIds.add(id));
    return true;
  }

  void _endAction(int id) {
    if (mounted) setState(() => _busyIds.remove(id));
  }

  Future<void> _selectDate(_PendingNotificationDraft item) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: item.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) setState(() => item.date = selected);
  }

  String _dateString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _label(String value) => value
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  String _sourceLabel(String packageName) =>
      NotificationExpenseService.supportedApps[packageName] ?? packageName;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF22262B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 1.5),
        ),
        content: Text(
          message,
          style: GoogleFonts.itim(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: _buildToolbarButton(
            tooltip: 'Back',
            icon: Icons.arrow_back_rounded,
            color: Colors.white,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        title: Text(
          'Review notifications',
          style: GoogleFonts.itim(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildToolbarButton(
              tooltip: 'Refresh notifications',
              icon: Icons.refresh_rounded,
              color: const Color(0xFF5DF9FF),
              onTap: _isLoading
                  ? null
                  : () {
                      _loadPending();
                    },
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF5DF9FF)),
                  const SizedBox(height: 14),
                  Text(
                    'Loading notifications...',
                    style: GoogleFonts.itim(
                      fontWeight: FontWeight.bold,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 420),
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
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
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5DF9FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Icon(
                        Icons.inbox_outlined,
                        size: 30,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No parsed notifications to review.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.itim(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) =>
                  _buildDraftCard(_items[index], colors),
            ),
    );
  }

  Widget _buildToolbarButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: NeoBouncy(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
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
          child: Icon(icon, color: Colors.black, size: 21),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.black, width: 1.5),
    );

    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.itim(color: theme.colorScheme.onSurfaceVariant),
      floatingLabelStyle: GoogleFonts.itim(
        color: const Color(0xFF007A99),
        fontWeight: FontWeight.bold,
      ),
      filled: true,
      fillColor: theme.brightness == Brightness.dark
          ? const Color(0xFF22262B)
          : const Color(0xFFF4F7FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF007A99), width: 2),
      ),
    );
  }

  Widget _buildDraftActionButton({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: NeoBouncy(
        scaleFactor: 0.92,
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
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
          child: Icon(icon, color: Colors.black, size: 20),
        ),
      ),
    );
  }

  Widget _buildApproveButton(_PendingNotificationDraft item, bool busy) {
    return NeoBouncy(
      scaleFactor: 0.95,
      onTap: busy
          ? null
          : () {
              _approveDraft(item);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9EB5D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            else
              const Icon(Icons.check_rounded, color: Colors.black, size: 18),
            const SizedBox(width: 6),
            Text(
              'Add expense',
              style: GoogleFonts.itim(
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftCard(_PendingNotificationDraft item, ColorScheme colors) {
    final busy = _busyIds.contains(item.id);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Colors.black, offset: Offset(4, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5DF9FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_outlined,
                        color: Colors.black,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _sourceLabel(item.sourceApp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.itim(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  DateFormat('MMM d, y - HH:mm').format(item.receivedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: GoogleFonts.itim(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: item.nameController,
            enabled: !busy,
            style: GoogleFonts.itim(color: colors.onSurface),
            decoration: _fieldDecoration('Name or merchant'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: item.amountController,
            enabled: !busy,
            keyboardType: TextInputType.number,
            style: GoogleFonts.itim(
              color: colors.onSurface,
              fontWeight: FontWeight.bold,
            ),
            decoration: _fieldDecoration('Amount'),
          ),
          const SizedBox(height: 10),
          NeoBouncy(
            onTap: busy
                ? null
                : () {
                    _selectDate(item);
                  },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.black, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    color: Colors.black,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('yMMMd').format(item.date),
                    style: GoogleFonts.itim(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _categories.contains(item.category)
                ? item.category
                : 'lainnya',
            style: GoogleFonts.itim(color: colors.onSurface),
            decoration: _fieldDecoration('Category'),
            items: _categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category,
                    child: Text(
                      _label(category),
                      style: GoogleFonts.itim(color: colors.onSurface),
                    ),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) setState(() => item.category = value);
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _types.contains(item.type) ? item.type : 'unexpected',
            style: GoogleFonts.itim(color: colors.onSurface),
            decoration: _fieldDecoration('Type'),
            items: _types
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(
                      _label(type),
                      style: GoogleFonts.itim(color: colors.onSurface),
                    ),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) setState(() => item.type = value);
                  },
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDraftActionButton(
                    tooltip: 'Discard notification',
                    icon: Icons.delete_outline_rounded,
                    color: const Color(0xFFFFD6D6),
                    onTap: busy
                        ? null
                        : () {
                            _discardDraft(item);
                          },
                  ),
                  const SizedBox(width: 8),
                  _buildDraftActionButton(
                    tooltip: 'Save changes',
                    icon: Icons.save_outlined,
                    color: const Color(0xFF5DF9FF),
                    onTap: busy
                        ? null
                        : () {
                            _saveDraft(item);
                          },
                  ),
                ],
              ),
              _buildApproveButton(item, busy),
            ],
          ),
        ],
      ),
    );
  }
}
